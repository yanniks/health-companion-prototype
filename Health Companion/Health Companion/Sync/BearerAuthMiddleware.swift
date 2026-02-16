//
//  BearerAuthMiddleware.swift
//  Health Companion
//
//  Created by Ehlert, Yannik on 15.02.26.
//

import Foundation
import HTTPTypes
import OpenAPIRuntime

// MARK: - Bearer Auth Middleware

/// A `ClientMiddleware` that injects a Bearer token into each request (DP4).
///
/// Obtains the current access token from `ServerAuthModule`, refreshing
/// transparently if needed.
struct BearerAuthMiddleware: OpenAPIRuntime.ClientMiddleware {
    let authModule: ServerAuthModule

    init(authModule: ServerAuthModule) {
        self.authModule = authModule
    }

    /// Intercepts an outgoing HTTP request and an incoming HTTP response.
    /// - Parameters:
    ///   - request: An HTTP request.
    ///   - body: An HTTP request body.
    ///   - baseURL: A server base URL.
    ///   - operationID: The identifier of the OpenAPI operation.
    ///   - next: A closure that calls the next middleware, or the transport.
    /// - Returns: An HTTP response and its body.
    /// - Throws: An error if interception of the request and response fails.
    nonisolated func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        let token = try await authModule.validAccessToken()
        request.headerFields[.authorization] = "Bearer \(token)"
        return try await next(request, body, baseURL)
    }
}
