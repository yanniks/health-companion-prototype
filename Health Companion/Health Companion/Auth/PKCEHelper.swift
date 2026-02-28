//
//  PKCEHelper.swift
//  Health Companion
//
//  Implements PKCE (Proof Key for Code Exchange) per RFC 7636.
//  Maps to: DP4 (Security and privacy by design)
//

import CryptoKit
import Foundation

/// Generates PKCE code verifier and challenge pairs.
///
/// Uses the S256 challenge method as required by the IAM server:
/// `code_challenge = BASE64URL(SHA256(code_verifier))`
enum PKCEHelper {

    /// A PKCE code pair consisting of a verifier and its S256 challenge.
    struct CodePair: Sendable {
        /// High-entropy random string (43–128 characters).
        let verifier: String
        /// Base64-URL-encoded SHA-256 hash of the verifier.
        let challenge: String
    }

    /// Generates a new PKCE code pair.
    static func generate() -> CodePair {
        // Generate 32 random bytes → base64url-encoded = 43 characters
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes).base64URLEncoded()

        // SHA-256 hash of the verifier, then base64url-encode
        let challengeData = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(challengeData).base64URLEncoded()

        return CodePair(verifier: verifier, challenge: challenge)
    }
}

// MARK: - Base64URL Encoding

extension Data {
    /// Encodes data as a Base64-URL string (no padding), per RFC 4648 §5.
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
