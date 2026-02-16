import Foundation
import OpenAPIRuntime
import HTTPTypes

/// Sliding-window rate limiter for the client-facing integration component (DP4, §5.5.1).
///
/// Restricts the number of requests per client within a configurable time window
/// to prevent abuse of patient-facing interfaces. Returns HTTP 429 when the
/// limit is exceeded, as defined in the OpenAPI specification.
///
/// Rate limits are applied per authenticated client (patient ID). Unauthenticated
/// requests (e.g., `/metadata`) are excluded from rate limiting.
actor RateLimiter {
    /// Maximum number of requests allowed per window.
    let maxRequests: Int

    /// Window duration in seconds.
    let windowSeconds: TimeInterval

    /// Tracks request timestamps per client.
    private var requestLog: [String: [Date]] = [:]

    init(maxRequests: Int = 60, windowSeconds: TimeInterval = 60) {
        self.maxRequests = maxRequests
        self.windowSeconds = windowSeconds
    }

    /// Check whether a request from `clientId` should be allowed.
    /// Returns `true` if the request is within limits.
    func allowRequest(clientId: String) -> Bool {
        let now = Date()
        let windowStart = now.addingTimeInterval(-windowSeconds)

        // Remove expired entries
        var timestamps = requestLog[clientId, default: []]
        timestamps = timestamps.filter { $0 > windowStart }

        guard timestamps.count < maxRequests else {
            requestLog[clientId] = timestamps
            return false
        }

        timestamps.append(now)
        requestLog[clientId] = timestamps
        return true
    }

    /// Returns the number of seconds until the next request would be allowed.
    func retryAfter(clientId: String) -> Int {
        guard let timestamps = requestLog[clientId], let oldest = timestamps.first else {
            return 0
        }
        let nextAllowed = oldest.addingTimeInterval(windowSeconds)
        return max(1, Int(nextAllowed.timeIntervalSinceNow.rounded(.up)))
    }
}


/// OpenAPI `ServerMiddleware` that enforces per-client rate limits (DP4).
///
/// Only applies to authenticated endpoints. Uses the JWT `sub` claim
/// (patient ID) as the client identifier for rate tracking.
struct RateLimitMiddleware: ServerMiddleware {
    let rateLimiter: RateLimiter
    let auditLogger: AuditLogger

    func intercept(
        _ request: HTTPTypes.HTTPRequest,
        body: HTTPBody?,
        metadata: ServerRequestMetadata,
        operationID: String,
        next: @Sendable (HTTPTypes.HTTPRequest, HTTPBody?, ServerRequestMetadata) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
        // Only rate-limit authenticated endpoints
        let isProtected = operationID == "submitObservations" || operationID == "getTransferStatus"
        guard isProtected else {
            return try await next(request, body, metadata)
        }

        // Extract client identity from Authorization header (best-effort, before full validation)
        // We use the raw token's sub claim if available, otherwise fallback to IP-based limiting
        let clientId: String
        if let subject = AuthContext.currentSubject {
            // Task-local set by AuthMiddleware (runs first in the chain)
            clientId = subject
        } else if let authHeader = request.headerFields[.authorization],
                  authHeader.lowercased().hasPrefix("bearer ") {
            // Parse sub claim from JWT payload (second segment, base64url)
            let token = String(authHeader.dropFirst(7))
            let parts = token.split(separator: ".")
            if parts.count >= 2,
               let payloadData = base64URLDecode(String(parts[1])),
               let payload = try? JSONDecoder().decode(MinimalJWTPayload.self, from: payloadData)
            {
                clientId = payload.sub
            } else {
                clientId = "unknown"
            }
        } else {
            clientId = "unknown"
        }

        let allowed = await rateLimiter.allowRequest(clientId: clientId)
        guard allowed else {
            let retryAfter = await rateLimiter.retryAfter(clientId: clientId)
            await auditLogger.logAuthFailure(reason: "rate_limit_exceeded:\(clientId)")

            let errorBody = try JSONEncoder().encode(RateLimitErrorBody(
                error: "rate_limit_exceeded",
                message: "Too many requests. Try again in \(retryAfter) seconds.",
                retryAfterSeconds: retryAfter
            ))
            var response = HTTPResponse(status: .tooManyRequests)
            response.headerFields[HTTPField.Name("Retry-After")!] = "\(retryAfter)"
            return (response, HTTPBody(errorBody))
        }

        return try await next(request, body, metadata)
    }

    // MARK: - Helpers

    private func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        return Data(base64Encoded: base64)
    }

    struct MinimalJWTPayload: Codable {
        let sub: String
    }

    struct RateLimitErrorBody: Codable {
        let error: String
        let message: String
        let retryAfterSeconds: Int
    }
}
