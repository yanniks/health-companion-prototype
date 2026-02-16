import Foundation
import Crypto

/// Manages EC P-256 key pair for JWT signing and verification
/// Keys are persisted to the storage directory for restartability
final class KeyManager: Sendable {
    private let privateKey: P256.Signing.PrivateKey
    private let keyId: String

    /// Initializes KeyManager, loading existing key or generating a new one
    /// - Parameter directory: Directory to store the key file
    init(directory: String) throws {
        let fileManager = FileManager.default
        let keyFilePath = "\(directory)/ec_private_key.pem"

        try fileManager.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: keyFilePath),
           let keyData = fileManager.contents(atPath: keyFilePath),
           let pemString = String(data: keyData, encoding: .utf8)
        {
            self.privateKey = try P256.Signing.PrivateKey(pemRepresentation: pemString)
            // Derive stable key ID from public key
            let pubKeyData = privateKey.publicKey.rawRepresentation
            let hash = SHA256.hash(data: pubKeyData)
            self.keyId = Data(hash.prefix(8)).map { String(format: "%02x", $0) }.joined()
        } else {
            // Generate new key pair
            let newKey = P256.Signing.PrivateKey()
            let pem = newKey.pemRepresentation
            try pem.write(toFile: keyFilePath, atomically: true, encoding: .utf8)

            self.privateKey = newKey
            let pubKeyData = newKey.publicKey.rawRepresentation
            let hash = SHA256.hash(data: pubKeyData)
            self.keyId = Data(hash.prefix(8)).map { String(format: "%02x", $0) }.joined()
        }
    }

    /// Initializes KeyManager with a provided key (for testing)
    init(privateKey: P256.Signing.PrivateKey) {
        self.privateKey = privateKey
        let pubKeyData = privateKey.publicKey.rawRepresentation
        let hash = SHA256.hash(data: pubKeyData)
        self.keyId = Data(hash.prefix(8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Signs data with the private key
    /// - Parameter data: Data to sign
    /// - Returns: The EC signature
    func sign(_ data: Data) throws -> P256.Signing.ECDSASignature {
        try privateKey.signature(for: data)
    }

    /// Verifies a signature against data using the public key
    /// - Parameters:
    ///   - signature: The signature to verify
    ///   - data: The original data
    /// - Returns: Whether the signature is valid
    func verify(signature: P256.Signing.ECDSASignature, for data: Data) -> Bool {
        privateKey.publicKey.isValidSignature(signature, for: data)
    }

    /// Returns the public key in JWK format for the JWKS endpoint
    /// - Returns: JWK dictionary representation
    func publicJWK() -> JWK {
        let publicKey = privateKey.publicKey
        let rawKey = publicKey.rawRepresentation

        // EC P-256 raw representation is 64 bytes: 32 bytes x, 32 bytes y
        let x = rawKey.prefix(32)
        let y = rawKey.suffix(32)

        return JWK(
            kty: "EC",
            crv: "P-256",
            x: base64URLEncode(Data(x)),
            y: base64URLEncode(Data(y)),
            kid: keyId,
            use: "sig",
            alg: "ES256"
        )
    }

    /// The key identifier for this key pair
    var kid: String { keyId }
}

// MARK: - Base64URL Encoding

func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

func base64URLDecode(_ string: String) -> Data? {
    var base64 = string
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")

    // Pad to multiple of 4
    let remainder = base64.count % 4
    if remainder > 0 {
        base64.append(String(repeating: "=", count: 4 - remainder))
    }

    return Data(base64Encoded: base64)
}
