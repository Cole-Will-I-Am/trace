import Foundation
import CryptoKit
import Security

/// Nonce helpers for Sign in with Apple. The app sends SHA256(nonce) to Apple in the auth
/// request and the RAW nonce to our Worker, which recomputes the hash and matches it to the
/// identity token's `nonce` claim — preventing token replay.
enum AppleSignIn {
    static func randomNonce(_ length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
