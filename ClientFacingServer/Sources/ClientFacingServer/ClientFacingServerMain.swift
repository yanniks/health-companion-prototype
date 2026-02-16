import Vapor

/// Main entry point for the Client-Facing Integration Server
/// Receives FHIR observations from patient-facing clients and forwards
/// to the Clinical Integration Server (DP3: Layered architecture)
@main
struct ClientFacingServerMain {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)

        let app = try await Application.make(env)
        try await configure(app)
        try await app.execute()
        try await app.asyncShutdown()
    }
}
