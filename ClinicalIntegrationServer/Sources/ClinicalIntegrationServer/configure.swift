import FHIRToGDT
import GDTKit
import NIOSSL
import OpenAPIVapor
import Vapor

/// Configures the Clinical Integration Server application
func configure(_ app: Application) throws {
    let port = Environment.get("CLINICAL_PORT").flatMap(Int.init) ?? 8083
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

    // GDT configuration
    let gdtOutputPath =
        Environment.get("GDT_OUTPUT_PATH")
        ?? URL(string: #filePath)!.deletingLastPathComponent()
        .appending(path: "gdt_exchange").path()
    let gdtSenderID = Environment.get("GDT_SENDER_ID") ?? "HEALTH_COMPANION"
    let gdtReceiverID = Environment.get("GDT_RECEIVER_ID") ?? "PVS"

    let converterConfig = FHIRToGDTConfiguration(
        gdtVersion: "02.10",
        encoding: .latin1,
        senderID: gdtSenderID,
        receiverID: gdtReceiverID,
        outputDirectory: URL(fileURLWithPath: gdtOutputPath),
        fileNamePrefix: "obs"
    )

    // Storage directory for status tracking
    let storageDir =
        Environment.get("CLINICAL_STORAGE_DIR")
        ?? URL(string: #filePath)!.deletingLastPathComponent()
        .appending(path: "data").path()
    print("Using GDT output directory: \(gdtOutputPath)")
    print("Using storage directory: \(storageDir)")

    app.storage[ConverterConfigKey.self] = converterConfig
    app.storage[StatusStoreKey.self] = StatusStore(directory: storageDir)

    // Register OpenAPI handler
    let handler = ClinicalIntegrationHandler(
        converterConfig: converterConfig,
        statusStore: app.storage[StatusStoreKey.self]!
    )
    let transport = VaporTransport(routesBuilder: app)
    try handler.registerHandlers(on: transport, serverURL: URL(string: "/api/v1")!)

    // Health check (outside OpenAPI)
    app.get("health") { _ in "OK" }
}

// MARK: - Storage Keys

struct ConverterConfigKey: StorageKey {
    typealias Value = FHIRToGDTConfiguration
}

struct StatusStoreKey: StorageKey {
    typealias Value = StatusStore
}
