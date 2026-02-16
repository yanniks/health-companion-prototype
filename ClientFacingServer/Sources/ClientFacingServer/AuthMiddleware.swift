import Foundation
import OpenAPIRuntime
import HTTPTypes

/// Middleware that validates Bearer tokens for protected endpoints
/// and stores the validated subject in a task-local for the handler
/// (DP4: Security and privacy by design)
struct AuthMiddleware: ServerMiddleware {
    let jwksProvider: JWKSProvider

    /// Paths that require authentication
    private static let protectedPaths: Set<String> = [
        "/api/v1/observations",
        "/api/v1/status"
    ]

    func intercept(
        _ request: HTTPTypes.HTTPRequest,
        body: HTTPBody?,
        metadata: ServerRequestMetadata,
        operationID: String,
        next: @Sendable (HTTPTypes.HTTPRequest, HTTPBody?, ServerRequestMetadata) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
        // Check if this operation requires authentication
        let requiresAuth = operationID == "submitObservations" || operationID == "getTransferStatus"

        guard requiresAuth else {
            return try await next(request, body, metadata)
        }

        // Extract Bearer token
        guard let authHeader = request.headerFields[.authorization],
              authHeader.lowercased().hasPrefix("bearer ")
        else {
            let errorBody = try JSONEncoder().encode(ErrorBody(error: "authentication_error", message: "Missing or invalid Authorization header"))
            return (
                HTTPResponse(status: .unauthorized),
                HTTPBody(errorBody)
            )
        }

        let token = String(authHeader.dropFirst(7))

        // Validate token
        let payload: JWKSProvider.JWTPayload
        do {
            payload = try jwksProvider.validateToken(token)
        } catch {
            let errorBody = try JSONEncoder().encode(ErrorBody(error: "authentication_error", message: error.localizedDescription))
            return (
                HTTPResponse(status: .unauthorized),
                HTTPBody(errorBody)
            )
        }

        // Set task-local auth context so the handler can access the validated subject
        return try await AuthContext.$currentSubject.withValue(payload.sub) {
            try await AuthContext.$currentScope.withValue(payload.scope) {
                try await AuthContext.$currentFirstName.withValue(payload.firstName) {
                    try await AuthContext.$currentLastName.withValue(payload.lastName) {
                        try await AuthContext.$currentDateOfBirth.withValue(payload.dateOfBirth) {
                            try await next(request, body, metadata)
                        }
                    }
                }
            }
        }
    }

    struct ErrorBody: Codable {
        let error: String
        let message: String
    }
}

