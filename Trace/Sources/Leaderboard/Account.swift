import Foundation
import Combine
import AuthenticationServices

/// Owns the leaderboard session: a stable anonymous identity minted on first launch (so you
/// rank without signing in), optionally upgraded to Sign in with Apple. Submitting a score is
/// fire-and-forget from the UI's perspective — failures never block play.
@MainActor
final class Account: NSObject, ObservableObject {
    @Published private(set) var player: BackendAccount?
    @Published private(set) var ready = false
    @Published var lastError: String?

    private let backend = Backend()
    private let tokenKey = "trace.sessionToken"
    private let secretKey = "trace.deviceSecret"
    private var token: String? { Keychain.get(tokenKey) }
    private var currentNonce: String?
    private var signInContinuation: CheckedContinuation<Void, Error>?

    var displayName: String { player?.username ?? player?.display ?? "You" }
    var isSignedIn: Bool { player?.isAnonymous == false }

    /// Mint or resume the anonymous account. Safe to call on launch; never throws to the UI.
    func bootstrap() async {
        if ready { return }
        do {
            let resp = try await backend.registerAnon(deviceId: Keychain.deviceId(),
                                                      deviceSecret: Keychain.get(secretKey))
            persist(resp)
        } catch {
            lastError = describe(error)
        }
        ready = true
    }

    func submit(levelId: Int, timeMs: Int, backtracks: Int, trail: [[Int]]) async -> ScoreResponse? {
        if token == nil { await bootstrap() }
        guard let token else { return nil }
        do { return try await backend.submitScore(token: token, levelId: levelId, timeMs: timeMs, backtracks: backtracks, trail: trail) }
        catch { lastError = describe(error); return nil }
    }

    /// Re-fetch the player from the server (picks up a username set on another device).
    func refresh() async {
        guard let token else { return }
        do { player = try await backend.me(token: token) } catch { /* keep the cached player */ }
    }

    func board(level: Int, metric: String) async -> BoardResponse? {
        do { return try await backend.board(level: level, metric: metric, token: token) }
        catch { lastError = describe(error); return nil }
    }

    func totalBoard() async -> BoardResponse? {
        do { return try await backend.totalBoard(token: token) }
        catch { lastError = describe(error); return nil }
    }

    func setUsername(_ name: String) async -> Bool {
        guard let token else { return false }
        do { player = try await backend.setUsername(token: token, username: name); return true }
        catch { lastError = describe(error); return false }
    }

    func deleteAccount() async {
        guard let token else { return }
        try? await backend.deleteAccount(token: token)
        Keychain.delete(tokenKey); Keychain.delete(secretKey)
        player = nil; ready = false
        await bootstrap()
    }

    // MARK: Sign in with Apple

    func startSignIn() {
        let nonce = AppleSignIn.randomNonce()
        currentNonce = nonce
        let req = ASAuthorizationAppleIDProvider().createRequest()
        req.requestedScopes = [.fullName]
        req.nonce = AppleSignIn.sha256Hex(nonce)
        let ctrl = ASAuthorizationController(authorizationRequests: [req])
        ctrl.delegate = self
        ctrl.presentationContextProvider = self
        ctrl.performRequests()
    }

    private func persist(_ resp: AccountResponse) {
        Keychain.set(tokenKey, resp.token)
        if let secret = resp.deviceSecret { Keychain.set(secretKey, secret) }
        player = resp.player
    }

    private func describe(_ error: Error) -> String {
        if case let BackendError.server(_, msg) = error { return msg }
        return "offline"
    }
}

extension Account: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = cred.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8),
              let nonce = currentNonce else { lastError = "sign-in failed"; return }
        Task { @MainActor in
            do {
                let resp = try await backend.signInApple(identityToken: idToken, nonce: nonce,
                                                         deviceId: Keychain.deviceId(),
                                                         deviceSecret: Keychain.get(secretKey))
                persist(resp)
            } catch { lastError = describe(error) }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        lastError = "sign-in cancelled"
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if canImport(UIKit)
        return UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}

#if canImport(UIKit)
import UIKit
extension UIWindowScene { var keyWindow: UIWindow? { windows.first { $0.isKeyWindow } } }
#endif
