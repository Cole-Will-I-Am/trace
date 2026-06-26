import Foundation

// Client for the Trace competitive backend (trace-api.manticthink.com). The client submits a
// level's elapsed time, backtrack count, and the final start→goal trail; the server validates
// it (legal corridor length + plausible-minimum time + trail hash) and keeps the best.

struct BackendAccount: Codable, Equatable {
    let id: String
    let username: String?
    let display: String
    let isAnonymous: Bool
}

struct AccountResponse: Codable { let token: String; let expiresAt: Int; let player: BackendAccount; let deviceSecret: String? }
struct PlayerWrap: Codable { let player: BackendAccount }

struct ScoreResponse: Codable {
    let levelId: Int
    let bestTimeMs: Int
    let rank: Int
    let percentile: Double
    let playerCount: Int
    let improved: Bool
}

struct BoardEntry: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let value: Int          // ms for time boards, count for backtrack boards / total ms
    let extra: Int?         // e.g. levels-completed on the total board
}
struct BoardMe: Codable, Equatable { let rank: Int; let value: Int; let percentile: Double }
struct BoardResponse: Codable, Equatable {
    let scope: String
    let metric: String
    let level: Int?
    let entries: [BoardEntry]
    let me: BoardMe?
}

private struct ErrorBody: Decodable { let error: String? }
private struct DeletedResp: Decodable { let deleted: Bool }

enum BackendError: Error { case network; case server(Int, String); case decode }

final class Backend {
    static let baseURLString = "https://trace-api.manticthink.com"
    private let session = URLSession.shared

    private func send<R: Decodable>(_ path: String, method: String = "GET",
                                    token: String? = nil, bodyData: Data? = nil) async throws -> R {
        guard let url = URL(string: Backend.baseURLString + path) else { throw BackendError.network }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let bodyData {
            req.httpBody = bodyData
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw BackendError.network }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "http \(http.statusCode)"
            throw BackendError.server(http.statusCode, msg)
        }
        do { return try JSONDecoder().decode(R.self, from: data) }
        catch { throw BackendError.decode }
    }

    private func enc<E: Encodable>(_ v: E) -> Data { (try? JSONEncoder().encode(v)) ?? Data("{}".utf8) }

    func registerAnon(deviceId: String, deviceSecret: String?) async throws -> AccountResponse {
        struct B: Encodable { let deviceId: String; let deviceSecret: String? }
        return try await send("/v1/account", method: "POST", bodyData: enc(B(deviceId: deviceId, deviceSecret: deviceSecret)))
    }

    func signInApple(identityToken: String, nonce: String, deviceId: String, deviceSecret: String?) async throws -> AccountResponse {
        struct B: Encodable { let appleIdentityToken: String; let nonce: String; let deviceId: String; let deviceSecret: String? }
        return try await send("/v1/account", method: "POST",
                              bodyData: enc(B(appleIdentityToken: identityToken, nonce: nonce, deviceId: deviceId, deviceSecret: deviceSecret)))
    }

    func submitScore(token: String, levelId: Int, timeMs: Int, backtracks: Int, trail: [[Int]]) async throws -> ScoreResponse {
        struct B: Encodable { let levelId: Int; let timeMs: Int; let backtracks: Int; let trail: [[Int]] }
        return try await send("/v1/score", method: "POST", token: token,
                              bodyData: enc(B(levelId: levelId, timeMs: timeMs, backtracks: backtracks, trail: trail)))
    }

    func board(level: Int, metric: String, token: String?) async throws -> BoardResponse {
        try await send("/v1/board?level=\(level)&metric=\(metric)&limit=50", token: token)
    }

    func totalBoard(token: String?) async throws -> BoardResponse {
        try await send("/v1/board/total?limit=50", token: token)
    }

    func setUsername(token: String, username: String) async throws -> BackendAccount {
        struct B: Encodable { let username: String }
        let w: PlayerWrap = try await send("/v1/username", method: "PUT", token: token, bodyData: enc(B(username: username)))
        return w.player
    }

    func me(token: String) async throws -> BackendAccount {
        let w: PlayerWrap = try await send("/v1/me", token: token)
        return w.player
    }

    func deleteAccount(token: String) async throws {
        let _: DeletedResp = try await send("/v1/account", method: "DELETE", token: token)
    }
}
