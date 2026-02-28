import Crypto
import Foundation

/// Provides JWT validation using JWKS fetched from the IAM server
/// (DP4: Security and privacy by design)
final class JWKSProvider: Sendable {
    private let iamBaseURL: String
    private let keys: LockedValueBox<[JWKData]>

    struct JWKData: Codable, Sendable {
        let kty: String
        let crv: String
        let x: String
        let y: String
        let kid: String
        let use: String
        let alg: String
    }

    struct JWKSResponse: Codable, Sendable {
        let keys: [JWKData]
    }

    struct JWTHeader: Codable, Sendable {
        let alg: String
        let typ: String
        let kid: String
    }

    struct JWTPayload: Codable, Sendable {
        let iss: String
        let sub: String
        let aud: String
        let exp: Int
        let iat: Int
        let scope: String
        /// Patient first name (embedded in JWT by IAM server)
        let firstName: String?
        /// Patient last name (embedded in JWT by IAM server)
        let lastName: String?
        /// Patient date of birth (embedded in JWT by IAM server)
        let dateOfBirth: String?
    }

    init(iamBaseURL: String) {
        self.iamBaseURL = iamBaseURL
        self.keys = LockedValueBox([])
    }

    /// Fetches JWKS from the IAM server
    func refresh() throws {
        let url = URL(string: "\(iamBaseURL)/jwks")!
        let data = try Data(contentsOf: url)
        let jwks = try JSONDecoder().decode(JWKSResponse.self, from: data)
        keys.withLockedValue { $0 = jwks.keys }
    }

    /// Validates a JWT access token and returns the payload
    func validateToken(_ token: String) throws -> JWTPayload {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else {
            throw JWTError.invalidFormat
        }

        let headerBase64 = String(parts[0])
        let payloadBase64 = String(parts[1])
        let signatureBase64 = String(parts[2])

        // Decode header to get kid
        guard let headerData = base64URLDecode(headerBase64) else {
            throw JWTError.invalidFormat
        }
        let header = try JSONDecoder().decode(JWTHeader.self, from: headerData)

        guard header.alg == "ES256" else {
            throw JWTError.unsupportedAlgorithm
        }

        // Find matching key
        let currentKeys = keys.withLockedValue { $0 }
        guard let jwk = currentKeys.first(where: { $0.kid == header.kid }) else {
            // Try refreshing keys once
            try? refresh()
            let refreshedKeys = keys.withLockedValue { $0 }
            guard let retryJWK = refreshedKeys.first(where: { $0.kid == header.kid }) else {
                throw JWTError.unknownKeyId
            }
            return try verifyWithKey(retryJWK, headerBase64: headerBase64, payloadBase64: payloadBase64, signatureBase64: signatureBase64)
        }

        return try verifyWithKey(jwk, headerBase64: headerBase64, payloadBase64: payloadBase64, signatureBase64: signatureBase64)
    }

    private func verifyWithKey(_ jwk: JWKData, headerBase64: String, payloadBase64: String, signatureBase64: String) throws -> JWTPayload {
        // Reconstruct public key from JWK
        guard let xData = base64URLDecode(jwk.x),
            let yData = base64URLDecode(jwk.y)
        else {
            throw JWTError.invalidKey
        }

        let rawKey = xData + yData
        let publicKey = try P256.Signing.PublicKey(rawRepresentation: rawKey)

        // Verify signature
        let signingInput = "\(headerBase64).\(payloadBase64)"
        guard let signingData = signingInput.data(using: .utf8),
            let signatureData = base64URLDecode(signatureBase64)
        else {
            throw JWTError.invalidFormat
        }

        let signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)
        guard publicKey.isValidSignature(signature, for: signingData) else {
            throw JWTError.invalidSignature
        }

        // Decode payload
        guard let payloadData = base64URLDecode(payloadBase64) else {
            throw JWTError.invalidFormat
        }
        let payload = try JSONDecoder().decode(JWTPayload.self, from: payloadData)

        // Check expiration
        let now = Int(Date().timeIntervalSince1970)
        guard payload.exp > now else {
            throw JWTError.expired
        }

        // Check audience
        guard payload.aud == "client-facing-server" else {
            throw JWTError.invalidAudience
        }

        return payload
    }
}

// MARK: - JWT Errors

enum JWTError: Error, CustomStringConvertible {
    case invalidFormat
    case unsupportedAlgorithm
    case unknownKeyId
    case invalidKey
    case invalidSignature
    case expired
    case invalidAudience
    case insufficientScope

    var description: String {
        switch self {
        case .invalidFormat: "Invalid JWT format"
        case .unsupportedAlgorithm: "Unsupported algorithm"
        case .unknownKeyId: "Unknown key ID"
        case .invalidKey: "Invalid key"
        case .invalidSignature: "Invalid signature"
        case .expired: "Token expired"
        case .invalidAudience: "Invalid audience"
        case .insufficientScope: "Insufficient scope"
        }
    }
}

// MARK: - Base64URL

func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

func base64URLDecode(_ string: String) -> Data? {
    var base64 =
        string
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let remainder = base64.count % 4
    if remainder > 0 {
        base64.append(String(repeating: "=", count: 4 - remainder))
    }
    return Data(base64Encoded: base64)
}

/// Thread-safe box for mutable values
final class LockedValueBox<T: Sendable>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()

    init(_ value: T) {
        self.value = value
    }

    func withLockedValue<Result>(_ body: (inout T) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}
