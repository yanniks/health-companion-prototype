import Crypto
import NIOSSL
import OpenAPIVapor
import Vapor

/// Configures the Client-Facing Integration Server
func configure(_ app: Application) async throws {
    let port = Environment.get("CLIENT_PORT").flatMap(Int.init) ?? 8082
    app.http.server.configuration.port = port
    app.http.server.configuration.hostname = "0.0.0.0"

    // TLS configuration (DP4, §5.5.1): All inter-component communication encrypted
    // Set TLS_CERT_PATH and TLS_KEY_PATH environment variables to enable TLS.
    // In production, a reverse proxy (e.g., nginx) may handle TLS termination instead.
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

    // Register FHIR content type
    let fhirContentType = HTTPMediaType(type: "application", subType: "fhir+json")
    ContentConfiguration.global.use(decoder: JSONDecoder(), for: fhirContentType)
    ContentConfiguration.global.use(encoder: JSONEncoder(), for: fhirContentType)

    // IAM configuration
    let iamBaseURL = Environment.get("IAM_BASE_URL") ?? "http://localhost:8081"
    let clinicalBaseURL = Environment.get("CLINICAL_BASE_URL") ?? "http://localhost:8083"
    let storageDir =
        Environment.get("CLIENT_STORAGE_DIR")
        ?? URL(string: #filePath)!.deletingLastPathComponent()
        .appending(path: "data").path()

    // Fetch JWKS from IAM server for token validation
    let jwksProvider = JWKSProvider(iamBaseURL: iamBaseURL)
    do {
        try jwksProvider.refresh()
    } catch {
        app.logger.warning("Could not fetch JWKS from IAM on startup: \(error). Will retry on first request.")
    }

    // Initialize stores
    let idempotencyStore = IdempotencyStore(directory: storageDir)
    let auditLogger = AuditLogger(directory: storageDir)

    // Rate limiter: configurable via environment (DP4, §5.5.1)
    let rateLimitMax = Environment.get("RATE_LIMIT_MAX").flatMap(Int.init) ?? 60
    let rateLimitWindow = Environment.get("RATE_LIMIT_WINDOW").flatMap(Double.init) ?? 60.0
    let rateLimiter = RateLimiter(maxRequests: rateLimitMax, windowSeconds: rateLimitWindow)

    app.storage[JWKSProviderKey.self] = jwksProvider
    app.storage[IdempotencyStoreKey.self] = idempotencyStore
    app.storage[AuditLoggerKey.self] = auditLogger
    app.storage[ClinicalBaseURLKey.self] = clinicalBaseURL
    app.storage[IAMBaseURLKey.self] = iamBaseURL

    // Register OpenAPI handler with auth middleware and rate limiter
    let handler = ClientFacingHandler(
        jwksProvider: jwksProvider,
        idempotencyStore: idempotencyStore,
        auditLogger: auditLogger,
        clinicalBaseURL: clinicalBaseURL,
        iamBaseURL: iamBaseURL
    )
    let authMiddleware = AuthMiddleware(jwksProvider: jwksProvider)
    let rateLimitMiddleware = RateLimitMiddleware(rateLimiter: rateLimiter, auditLogger: auditLogger)
    let transport = VaporTransport(routesBuilder: app)
    try handler.registerHandlers(
        on: transport,
        serverURL: URL(string: "/api/v1")!,
        middlewares: [authMiddleware, rateLimitMiddleware]
    )

    // Health check (outside OpenAPI)
    app.get("health") { _ in "OK" }
}

// MARK: - Storage Keys

struct JWKSProviderKey: StorageKey {
    typealias Value = JWKSProvider
}

struct IdempotencyStoreKey: StorageKey {
    typealias Value = IdempotencyStore
}

struct AuditLoggerKey: StorageKey {
    typealias Value = AuditLogger
}

struct ClinicalBaseURLKey: StorageKey {
    typealias Value = String
}

struct IAMBaseURLKey: StorageKey {
    typealias Value = String
}
