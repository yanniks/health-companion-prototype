//
//  OIDCDiscovery.swift
//  Health Companion
//
//  Fetches and caches OpenID Connect discovery documents from the IAM server.
//  Maps to: DP4 (Security and privacy by design), DR5 (Standards-based authentication)
//

import Foundation
import OSLog


/// Represents an OpenID Connect Discovery Document as returned by
/// `/.well-known/openid-configuration`.
struct OIDCConfiguration: Codable, Sendable {
    let issuer: String
    let authorizationEndpoint: String
    let tokenEndpoint: String
    let jwksURI: String
    let revocationEndpoint: String
    let responseTypesSupported: [String]
    let grantTypesSupported: [String]
    let codeChallengeMethodsSupported: [String]
    let scopesSupported: [String]

    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case jwksURI = "jwks_uri"
        case revocationEndpoint = "revocation_endpoint"
        case responseTypesSupported = "response_types_supported"
        case grantTypesSupported = "grant_types_supported"
        case codeChallengeMethodsSupported = "code_challenge_methods_supported"
        case scopesSupported = "scopes_supported"
    }
}


/// Discovers OIDC configuration from a given IAM base URL.
enum OIDCDiscoveryClient {
    private static let logger = Logger(subsystem: "HealthCompanion", category: "OIDCDiscovery")

    /// Fetches the OIDC discovery document from the IAM server.
    /// - Parameter baseURL: The IAM server base URL (e.g. `http://localhost:8081`).
    /// - Returns: The parsed OIDC configuration.
    static func discover(from baseURL: URL) async throws -> OIDCConfiguration {
        let discoveryURL = baseURL.appendingPathComponent(".well-known/openid-configuration")
        logger.info("Fetching OIDC discovery from \(discoveryURL)")

        let (data, response) = try await URLSession.shared.data(from: discoveryURL)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw OIDCError.discoveryFailed
        }

        let decoder = JSONDecoder()
        let config = try decoder.decode(OIDCConfiguration.self, from: data)
        logger.info("OIDC discovery successful: issuer=\(config.issuer)")
        return config
    }
}


// MARK: - Errors

/// Errors that can occur during OIDC operations.
enum OIDCError: LocalizedError {
    case discoveryFailed
    case invalidAuthorizationEndpoint
    case invalidTokenEndpoint

    var errorDescription: String? {
        switch self {
        case .discoveryFailed:
            "Failed to fetch OIDC discovery document"
        case .invalidAuthorizationEndpoint:
            "Invalid authorization endpoint URL"
        case .invalidTokenEndpoint:
            "Invalid token endpoint URL"
        }
    }
}
