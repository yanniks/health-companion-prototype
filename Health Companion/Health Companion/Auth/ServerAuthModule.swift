//
//  ServerAuthModule.swift
//  Health Companion
//
//  Spezi Module managing OAuth 2.0 Authorization Code + PKCE authentication
//  against the IAM server.
//
//  Maps to:
//  - DR5 (Standards-based authentication and authorization)
//  - DP4 (Security and privacy by design)
//  - DO3 (Systematic integration of authentication mechanisms)
//

import AuthenticationServices
import Foundation
import OSLog
import Spezi
import SpeziFoundation
import SwiftUI


/// A Spezi `Module` that manages the OAuth 2.0 Authorization Code + PKCE flow.
///
/// Responsibilities:
/// - Discovers OIDC configuration from the IAM server
/// - Performs the authorization code flow via `ASWebAuthenticationSession`
/// - Exchanges authorization codes for access + refresh tokens
/// - Stores tokens securely in the Keychain
/// - Auto-refreshes expired access tokens
/// - Provides a `validAccessToken()` method for other modules
///
/// Usage in `Configuration`:
/// ```swift
/// Configuration(standard: HealthCompanionStandard()) {
///     ServerAuthModule()
///     // ...
/// }
/// ```
///
/// Usage in Views:
/// ```swift
/// @Environment(ServerAuthModule.self) private var auth
/// ```
@Observable
final class ServerAuthModule: Module, EnvironmentAccessible, @unchecked Sendable {
    private let logger = Logger(subsystem: "HealthCompanion", category: "ServerAuth")
    private let keychain = KeychainStore()

    /// The custom URL scheme used for the OAuth redirect callback.
    static let callbackScheme = "healthcompanion"
    static let redirectURI = "healthcompanion://oauth/callback"

    /// The fixed OAuth client_id identifying this app.
    static let clientId = "healthcompanion-ios"

    static let defaultIamServerURL = "http://localhost:8081"
    static let defaultClientFacingServerURL = "http://localhost:8082"

    // MARK: - Observable State

    /// Whether the user is currently authenticated (has a valid or refreshable token).
    private(set) var isAuthenticated = false

    /// The authenticated patient's ID (extracted from the JWT `sub` claim).
    private(set) var patientId: String?

    /// An error message to display in the UI, if any.
    private(set) var authError: String?

    /// Whether a login/refresh operation is in progress.
    private(set) var isLoading = false

    // MARK: - Internal State

    /// Cached OIDC configuration from the IAM server.
    private var oidcConfig: OIDCConfiguration?

    /// The current access token (kept in memory for fast access).
    private var accessToken: String?

    /// The token expiry date.
    private var tokenExpiry: Date?

    // MARK: - Module Lifecycle

    func configure() {
        // Restore saved session from Keychain
        if let savedToken = keychain.load(key: KeychainStore.Keys.accessToken),
           let savedPatientId = keychain.load(key: KeychainStore.Keys.patientId) {
            accessToken = savedToken
            patientId = savedPatientId

            if let expiryString = keychain.load(key: KeychainStore.Keys.tokenExpiry),
               let expiryInterval = Double(expiryString) {
                tokenExpiry = Date(timeIntervalSince1970: expiryInterval)
            }

            // Check if we have a refresh token → consider authenticated
            let hasRefreshToken = keychain.load(key: KeychainStore.Keys.refreshToken) != nil
            isAuthenticated = hasRefreshToken
            logger.info("Restored auth session for patient \(savedPatientId)")
        }
    }

    // MARK: - Server URL

    /// The IAM server base URL, read from UserDefaults.
    var iamBaseURL: URL? {
        let urlString = UserDefaults.standard.string(forKey: StorageKeys.iamServerURL) ?? Self.defaultIamServerURL
        guard let url = URL(string: urlString) else {
            return nil
        }
        return url
    }

    /// The Client-Facing server base URL, read from UserDefaults.
    var clientFacingBaseURL: URL? {
        let urlString = UserDefaults.standard.string(forKey: StorageKeys.clientFacingServerURL) ?? Self.defaultClientFacingServerURL
        guard let url = URL(string: urlString) else {
            return nil
        }
        return url
    }

    // MARK: - Login

    /// Initiates the OAuth 2.0 Authorization Code + PKCE flow.
    ///
    /// Opens an `ASWebAuthenticationSession` to the IAM server's authorization
    /// endpoint. The patient authenticates on the web page. On success,
    /// exchanges the authorization code for tokens and extracts the
    /// patient ID from the JWT `sub` claim.
    @MainActor
    func login() async throws {
        guard let baseURL = iamBaseURL else {
            throw AuthError.serverURLNotConfigured
        }

        isLoading = true
        authError = nil
        defer { isLoading = false }

        do {
            // 1. Discover OIDC configuration
            let config = try await discoverOIDC(baseURL: baseURL)

            // 2. Generate PKCE pair
            let pkce = PKCEHelper.generate()

            // 3. Build authorization URL
            let authURL = try buildAuthorizationURL(
                config: config,
                clientId: Self.clientId,
                codeChallenge: pkce.challenge
            )

            // 4. Open ASWebAuthenticationSession
            let callbackURL = try await performWebAuthentication(url: authURL)

            // 5. Extract authorization code from callback
            let code = try extractAuthorizationCode(from: callbackURL)

            // 6. Exchange code for tokens
            try await exchangeCodeForTokens(
                config: config,
                code: code,
                clientId: Self.clientId,
                codeVerifier: pkce.verifier
            )

            // 7. Extract patient ID from the JWT access token's sub claim
            let extractedPatientId = try extractSubjectFromJWT(accessToken!)
            self.patientId = extractedPatientId
            isAuthenticated = true
            keychain.save(key: KeychainStore.Keys.patientId, value: extractedPatientId)
            logger.info("Login successful for patient \(extractedPatientId)")
        } catch {
            authError = error.localizedDescription
            logger.error("Login failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Logout

    /// Revokes the refresh token and clears all stored credentials.
    func logout() async {
        // Revoke refresh token on server
        if let baseURL = iamBaseURL,
           let refreshToken = keychain.load(key: KeychainStore.Keys.refreshToken) {
            let config: OIDCConfiguration?
            if let cached = oidcConfig {
                config = cached
            } else {
                config = try? await OIDCDiscoveryClient.discover(from: baseURL)
            }
            if let config {
                await revokeToken(refreshToken, config: config)
            }
        }

        // Clear local state
        keychain.deleteAll()
        accessToken = nil
        tokenExpiry = nil
        patientId = nil
        isAuthenticated = false
        oidcConfig = nil
        authError = nil
        logger.info("Logged out")
    }

    // MARK: - Token Access

    /// Returns a valid access token, refreshing it automatically if expired.
    ///
    /// Other modules (e.g. `ServerSyncModule`) call this method to get
    /// a bearer token for API requests.
    ///
    /// - Returns: A valid access token string.
    /// - Throws: `AuthError` if refresh fails or user is not authenticated.
    func validAccessToken() async throws -> String {
        // If token is still valid, return it
        if let token = accessToken,
           let expiry = tokenExpiry,
           expiry > Date().addingTimeInterval(30) { // 30s buffer
            return token
        }

        // Try to refresh
        try await refreshAccessToken()

        guard let token = accessToken else {
            throw AuthError.notAuthenticated
        }
        return token
    }

    // MARK: - Private: OIDC Discovery

    private func discoverOIDC(baseURL: URL) async throws -> OIDCConfiguration {
        if let cached = oidcConfig {
            return cached
        }
        let config = try await OIDCDiscoveryClient.discover(from: baseURL)
        oidcConfig = config
        return config
    }

    // MARK: - Private: Authorization URL

    private func buildAuthorizationURL(
        config: OIDCConfiguration,
        clientId: String,
        codeChallenge: String
    ) throws -> URL {
        guard var components = URLComponents(string: config.authorizationEndpoint) else {
            throw OIDCError.invalidAuthorizationEndpoint
        }

        let state = UUID().uuidString

        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: "openid observation.write status.read"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        guard let url = components.url else {
            throw OIDCError.invalidAuthorizationEndpoint
        }
        return url
    }

    // MARK: - Private: Web Authentication

    @MainActor
    private func performWebAuthentication(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: Self.callbackScheme
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: AuthError.authenticationCancelled)
                }
            }
            session.prefersEphemeralWebBrowserSession = true

            let contextProvider = WebAuthContextProvider()
            session.presentationContextProvider = contextProvider
            session.start()
        }
    }

    // MARK: - Private: Code Extraction

    private func extractAuthorizationCode(from url: URL) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let codeItem = components.queryItems?.first(where: { $0.name == "code" }),
              let code = codeItem.value
        else {
            // Check for error response
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let errorItem = components.queryItems?.first(where: { $0.name == "error" }) {
                throw AuthError.authorizationDenied(errorItem.value ?? "unknown")
            }
            throw AuthError.missingAuthorizationCode
        }
        return code
    }

    // MARK: - Private: Token Exchange

    private func exchangeCodeForTokens(
        config: OIDCConfiguration,
        code: String,
        clientId: String,
        codeVerifier: String
    ) async throws {
        guard let tokenURL = URL(string: config.tokenEndpoint) else {
            throw OIDCError.invalidTokenEndpoint
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type=authorization_code",
            "code=\(code)",
            "redirect_uri=\(Self.redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? Self.redirectURI)",
            "code_verifier=\(codeVerifier)",
            "client_id=\(clientId)",
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            logger.error("Token exchange failed: \(String(data: data, encoding: .utf8) ?? "no body")")
            throw AuthError.tokenExchangeFailed
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponseDTO.self, from: data)
        storeTokens(tokenResponse)
    }

    // MARK: - Private: Token Refresh

    private func refreshAccessToken() async throws {
        guard let baseURL = iamBaseURL else {
            throw AuthError.serverURLNotConfigured
        }

        guard let refreshToken = keychain.load(key: KeychainStore.Keys.refreshToken) else {
            isAuthenticated = false
            throw AuthError.notAuthenticated
        }

        let config = try await discoverOIDC(baseURL: baseURL)

        guard let tokenURL = URL(string: config.tokenEndpoint) else {
            throw OIDCError.invalidTokenEndpoint
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type=refresh_token",
            "refresh_token=\(refreshToken)",
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            logger.warning("Token refresh failed, forcing logout")
            isAuthenticated = false
            keychain.deleteAll()
            accessToken = nil
            tokenExpiry = nil
            throw AuthError.tokenRefreshFailed
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponseDTO.self, from: data)
        storeTokens(tokenResponse)
        logger.info("Access token refreshed successfully")
    }

    // MARK: - Private: Token Revocation

    private func revokeToken(_ token: String, config: OIDCConfiguration) async {
        guard let revokeURL = URL(string: config.revocationEndpoint) else { return }

        var request = URLRequest(url: revokeURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "token=\(token)&token_type_hint=refresh_token".data(using: .utf8)

        do {
            let _ = try await URLSession.shared.data(for: request)
            logger.info("Token revoked successfully")
        } catch {
            logger.warning("Token revocation failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private: Token Storage

    private func storeTokens(_ response: TokenResponseDTO) {
        accessToken = response.accessToken
        keychain.save(key: KeychainStore.Keys.accessToken, value: response.accessToken)
        keychain.save(key: KeychainStore.Keys.refreshToken, value: response.refreshToken)

        let expiry = Date().addingTimeInterval(TimeInterval(response.expiresIn))
        tokenExpiry = expiry
        keychain.save(
            key: KeychainStore.Keys.tokenExpiry,
            value: String(expiry.timeIntervalSince1970)
        )

        if let scope = response.scope {
            keychain.save(key: KeychainStore.Keys.scope, value: scope)
        }
    }

    // MARK: - Private: JWT Parsing

    /// Extracts the `sub` (subject / patient ID) claim from a JWT access token.
    ///
    /// The IAM server sets `sub` to the authenticated patient's ID.
    /// This is a lightweight decode — signature verification is not needed
    /// here since the token was just received from the trusted IAM server.
    private func extractSubjectFromJWT(_ jwt: String) throws -> String {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else {
            throw AuthError.tokenExchangeFailed
        }

        // Base64URL decode the payload (second segment)
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Pad to multiple of 4
        while base64.count % 4 != 0 {
            base64.append("=")
        }

        guard let payloadData = Data(base64Encoded: base64) else {
            throw AuthError.tokenExchangeFailed
        }

        struct JWTSubject: Decodable {
            let sub: String
        }

        let payload = try JSONDecoder().decode(JWTSubject.self, from: payloadData)
        return payload.sub
    }
}

// MARK: - DTOs

/// OAuth 2.0 token response from the IAM server.
private struct TokenResponseDTO: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

// MARK: - Errors

/// Authentication errors for the OAuth flow.
enum AuthError: LocalizedError {
    case serverURLNotConfigured
    case notAuthenticated
    case authenticationCancelled
    case authorizationDenied(String)
    case missingAuthorizationCode
    case tokenExchangeFailed
    case tokenRefreshFailed

    var errorDescription: String? {
        switch self {
        case .serverURLNotConfigured:
            "Server URL is not configured. Please set up the server in Settings."
        case .notAuthenticated:
            "Not authenticated. Please log in."
        case .authenticationCancelled:
            "Authentication was cancelled."
        case .authorizationDenied(let reason):
            "Authorization denied: \(reason)"
        case .missingAuthorizationCode:
            "No authorization code received from server."
        case .tokenExchangeFailed:
            "Failed to exchange authorization code for tokens."
        case .tokenRefreshFailed:
            "Failed to refresh access token. Please log in again."
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

/// Provides the presentation anchor (key window) for `ASWebAuthenticationSession`.
private final class WebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow })
        else {
            // Fallback: return the first available window
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            return scene?.windows.first ?? ASPresentationAnchor()
        }
        return window
    }
}
