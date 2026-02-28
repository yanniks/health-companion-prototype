import Crypto
import Foundation

/// Generates and validates JWT access tokens (RFC 7519)
/// Uses EC P-256 / ES256 algorithm (DP4: Security and privacy by design)
final class TokenService: Sendable {
    private let keyManager: KeyManager
    private let accessTokenLifetime: TimeInterval = 900  // 15 minutes

    init(keyManager: KeyManager) {
        self.keyManager = keyManager
    }

    /// Generates a signed JWT access token
    /// - Parameters:
    ///   - subject: The subject (patient/client ID)
    ///   - scope: The granted OAuth scope
    ///   - firstName: Patient first name (optional, embedded as claim)
    ///   - lastName: Patient last name (optional, embedded as claim)
    ///   - dateOfBirth: Patient date of birth (optional, embedded as claim)
    /// - Returns: Signed JWT string
    func generateAccessToken(subject: String, scope: String, firstName: String? = nil, lastName: String? = nil, dateOfBirth: String? = nil) throws
        -> String
    {
        let now = Date()
        let expiration = now.addingTimeInterval(accessTokenLifetime)

        let header = JWTHeader(alg: "ES256", typ: "JWT", kid: keyManager.kid)
        let payload = JWTPayload(
            iss: "iam-server",
            sub: subject,
            aud: "client-facing-server",
            exp: Int(expiration.timeIntervalSince1970),
            iat: Int(now.timeIntervalSince1970),
            scope: scope,
            firstName: firstName,
            lastName: lastName,
            dateOfBirth: dateOfBirth
        )

        let headerJSON = try JSONEncoder().encode(header)
        let payloadJSON = try JSONEncoder().encode(payload)

        let headerBase64 = base64URLEncode(headerJSON)
        let payloadBase64 = base64URLEncode(payloadJSON)

        let signingInput = "\(headerBase64).\(payloadBase64)"
        guard let signingData = signingInput.data(using: .utf8) else {
            throw TokenError.encodingFailed
        }

        let signature = try keyManager.sign(signingData)
        let signatureBase64 = base64URLEncode(signature.rawRepresentation)

        return "\(signingInput).\(signatureBase64)"
    }

    /// Validates a JWT access token and returns the payload
    /// - Parameter token: The JWT string to validate
    /// - Returns: The decoded payload if valid
    func validateAccessToken(_ token: String) throws -> JWTPayload {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else {
            throw TokenError.invalidFormat
        }

        let headerBase64 = String(parts[0])
        let payloadBase64 = String(parts[1])
        let signatureBase64 = String(parts[2])

        // Verify signature
        let signingInput = "\(headerBase64).\(payloadBase64)"
        guard let signingData = signingInput.data(using: .utf8),
            let signatureData = base64URLDecode(signatureBase64)
        else {
            throw TokenError.invalidFormat
        }

        let signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)
        guard keyManager.verify(signature: signature, for: signingData) else {
            throw TokenError.invalidSignature
        }

        // Decode payload
        guard let payloadData = base64URLDecode(payloadBase64) else {
            throw TokenError.invalidFormat
        }

        let payload = try JSONDecoder().decode(JWTPayload.self, from: payloadData)

        // Check expiration
        let now = Int(Date().timeIntervalSince1970)
        guard payload.exp > now else {
            throw TokenError.expired
        }

        return payload
    }
}

// MARK: - Token Errors

enum TokenError: Error, CustomStringConvertible {
    case encodingFailed
    case invalidFormat
    case invalidSignature
    case expired

    var description: String {
        switch self {
        case .encodingFailed: "Failed to encode token"
        case .invalidFormat: "Invalid token format"
        case .invalidSignature: "Invalid token signature"
        case .expired: "Token has expired"
        }
    }
}
