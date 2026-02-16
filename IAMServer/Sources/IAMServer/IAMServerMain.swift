import Vapor

/// Main entry point for the IAM Server
/// Provides OAuth 2.0 / OpenID Connect compatible authentication
/// for the PGHD integration artifact (DP4: Security and privacy by design)
@main
struct IAMServerMain {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)

        let app = try await Application.make(env)
        try configure(app)
        try await app.execute()
        try await app.asyncShutdown()
    }
}
