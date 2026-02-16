import Vapor
import NIOSSL

/// Configures the IAM Server application
/// - Parameter app: The Vapor Application instance
func configure(_ app: Application) throws {
    // Configure server port (default 8081)
    let port = Environment.get("IAM_PORT").flatMap(Int.init) ?? 8081
    app.http.server.configuration.port = port
    app.http.server.configuration.hostname = "0.0.0.0"

    // TLS configuration (DP4, §5.5.1): All inter-component communication encrypted
    // Set TLS_CERT_PATH and TLS_KEY_PATH environment variables to enable TLS.
    if let certPath = Environment.get("TLS_CERT_PATH"),
       let keyPath = Environment.get("TLS_KEY_PATH")
    {
        let certs = try NIOSSLCertificate.fromPEMFile(certPath)
        let privateKey = try NIOSSLPrivateKey(file: keyPath, format: .pem)
        let tlsConfig = TLSConfiguration.makeServerConfiguration(
            certificateChain: certs.map { .certificate($0) },
            privateKey: .privateKey(privateKey)
        )
        app.http.server.configuration.tlsConfiguration = tlsConfig
    }

    // Configure storage directory
    let storageDir = Environment.get("IAM_STORAGE_DIR") ?? "./data"
    app.storage[StorageDirectoryKey.self] = storageDir

    // Initialize stores
    let patientStore = PatientStore(directory: storageDir)
    let authCodeStore = AuthorizationCodeStore(directory: storageDir)
    let refreshTokenStore = RefreshTokenStore(directory: storageDir)
    let keyManager = try KeyManager(directory: storageDir)
    let tokenService = TokenService(keyManager: keyManager)

    app.storage[PatientStoreKey.self] = patientStore
    app.storage[AuthorizationCodeStoreKey.self] = authCodeStore
    app.storage[RefreshTokenStoreKey.self] = refreshTokenStore
    app.storage[KeyManagerKey.self] = keyManager
    app.storage[TokenServiceKey.self] = tokenService

    // Register routes
    try routes(app)
}

// MARK: - Storage Keys

struct StorageDirectoryKey: StorageKey {
    typealias Value = String
}

struct PatientStoreKey: StorageKey {
    typealias Value = PatientStore
}

struct AuthorizationCodeStoreKey: StorageKey {
    typealias Value = AuthorizationCodeStore
}

struct RefreshTokenStoreKey: StorageKey {
    typealias Value = RefreshTokenStore
}

struct KeyManagerKey: StorageKey {
    typealias Value = KeyManager
}

struct TokenServiceKey: StorageKey {
    typealias Value = TokenService
}

// MARK: - Application Extensions

extension Application {
    var patientStore: PatientStore {
        guard let store = storage[PatientStoreKey.self] else {
            fatalError("PatientStore not configured")
        }
        return store
    }

    var authCodeStore: AuthorizationCodeStore {
        guard let store = storage[AuthorizationCodeStoreKey.self] else {
            fatalError("AuthorizationCodeStore not configured")
        }
        return store
    }

    var refreshTokenStore: RefreshTokenStore {
        guard let store = storage[RefreshTokenStoreKey.self] else {
            fatalError("RefreshTokenStore not configured")
        }
        return store
    }

    var keyManager: KeyManager {
        guard let manager = storage[KeyManagerKey.self] else {
            fatalError("KeyManager not configured")
        }
        return manager
    }

    var tokenService: TokenService {
        guard let service = storage[TokenServiceKey.self] else {
            fatalError("TokenService not configured")
        }
        return service
    }
}
