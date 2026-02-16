import Vapor

/// Main entry point for the Clinical Integration Server
/// Converts FHIR observations to GDT 2.1 files for PMS integration
/// (DP2: PMS-agnostic interoperability, DR2: System-independent interface)
@main
struct ClinicalIntegrationServerMain {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)

        let app = try await Application.make(env)
        try configure(app)
        try await app.execute()
        try await app.asyncShutdown()
    }
}
