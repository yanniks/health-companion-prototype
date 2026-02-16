import Foundation
import Crypto

/// Verifies PKCE code challenges (RFC 7636)
/// Supports S256 method (SHA-256 hash of code verifier)
enum PKCEVerifier {
    /// Verifies a PKCE code verifier against the stored code challenge
    /// - Parameters:
    ///   - codeVerifier: The plaintext code verifier from the token request
    ///   - codeChallenge: The stored code challenge from the authorization request
    ///   - method: The code challenge method (must be "S256")
    /// - Returns: Whether the code verifier is valid
    static func verify(codeVerifier: String, codeChallenge: String, method: String) -> Bool {
        guard method == "S256" else { return false }
        guard let verifierData = codeVerifier.data(using: .ascii) else { return false }

        let hash = SHA256.hash(data: verifierData)
        let computedChallenge = base64URLEncode(Data(hash))

        return computedChallenge == codeChallenge
    }

    /// Generates a PKCE code challenge from a code verifier (for testing)
    /// - Parameter codeVerifier: The plaintext code verifier
    /// - Returns: The S256 code challenge
    static func generateChallenge(from codeVerifier: String) -> String? {
        guard let verifierData = codeVerifier.data(using: .ascii) else { return nil }
        let hash = SHA256.hash(data: verifierData)
        return base64URLEncode(Data(hash))
    }
}
