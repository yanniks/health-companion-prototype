import Vapor

// MARK: - Known Clients

/// The registered OAuth client ID for the Health Companion iOS app.
/// In a production system this would be a database of registered clients.
let knownClientId = "healthcompanion-ios"

// MARK: - OIDC Discovery

/// OpenID Connect Discovery Document
struct OIDCDiscoveryDocument: Content {
    let issuer: String
    let authorizationEndpoint: String
    let tokenEndpoint: String
    let jwksURI: String
    let revocationEndpoint: String
    let responseTypesSupported: [String]
    let grantTypesSupported: [String]
    let subjectTypesSupported: [String]
    let idTokenSigningAlgValuesSupported: [String]
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
        case subjectTypesSupported = "subject_types_supported"
        case idTokenSigningAlgValuesSupported = "id_token_signing_alg_values_supported"
        case codeChallengeMethodsSupported = "code_challenge_methods_supported"
        case scopesSupported = "scopes_supported"
    }
}

// MARK: - JWK / JWKS

/// JSON Web Key representation
struct JWK: Content {
    let kty: String
    let crv: String
    let x: String
    let y: String
    let kid: String
    let use: String
    let alg: String
}

/// JWKS response wrapper
struct JWKSResponse: Content {
    let keys: [JWK]
}

// MARK: - JWT

/// JWT header
struct JWTHeader: Codable {
    let alg: String
    let typ: String
    let kid: String
}

/// JWT payload for access tokens
struct JWTPayload: Codable, Sendable {
    let iss: String
    let sub: String
    let aud: String
    let exp: Int
    let iat: Int
    let scope: String
    /// Patient first name (embedded to avoid inter-service REST calls)
    let firstName: String?
    /// Patient last name (embedded to avoid inter-service REST calls)
    let lastName: String?
    /// Patient date of birth (embedded to avoid inter-service REST calls)
    let dateOfBirth: String?
}

// MARK: - Authorization Request

/// OAuth 2.0 authorization request parameters
struct AuthorizationRequest: Content {
    let responseType: String
    let clientId: String
    let redirectURI: String
    let scope: String
    let state: String
    let codeChallenge: String
    let codeChallengeMethod: String

    enum CodingKeys: String, CodingKey {
        case responseType = "response_type"
        case clientId = "client_id"
        case redirectURI = "redirect_uri"
        case scope
        case state
        case codeChallenge = "code_challenge"
        case codeChallengeMethod = "code_challenge_method"
    }

    func validate() throws {
        guard responseType == "code" else {
            throw Abort(.badRequest, reason: "Only response_type=code is supported")
        }
        guard codeChallengeMethod == "S256" else {
            throw Abort(.badRequest, reason: "Only code_challenge_method=S256 is supported")
        }
        guard !codeChallenge.isEmpty else {
            throw Abort(.badRequest, reason: "code_challenge is required (PKCE)")
        }
        guard !state.isEmpty else {
            throw Abort(.badRequest, reason: "state is required")
        }
    }
}

// MARK: - Token Request

/// OAuth 2.0 token request parameters
struct TokenRequest: Content {
    let grantType: String
    let code: String?
    let redirectURI: String?
    let codeVerifier: String?
    let clientId: String?
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case grantType = "grant_type"
        case code
        case redirectURI = "redirect_uri"
        case codeVerifier = "code_verifier"
        case clientId = "client_id"
        case refreshToken = "refresh_token"
    }
}

// MARK: - Token Response

/// OAuth 2.0 token response
struct TokenResponse: Content {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String
    let scope: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

// MARK: - Revocation

/// Token revocation request
struct RevocationRequest: Content {
    let token: String
    let tokenTypeHint: String?

    enum CodingKeys: String, CodingKey {
        case token
        case tokenTypeHint = "token_type_hint"
    }
}

// MARK: - Authorization Code

/// Stored authorization code
struct AuthorizationCode: Codable, Sendable {
    let code: String
    let clientId: String
    /// The authenticated patient ID (the OAuth resource owner / subject)
    let patientId: String
    let redirectURI: String
    let codeChallenge: String
    let codeChallengeMethod: String
    let scope: String
    let state: String
    let createdAt: Double
}

// MARK: - Login Credentials

/// Credentials submitted on the IAM login page
struct LoginCredentials: Content {
    let patientId: String
    let dateOfBirth: String

    enum CodingKeys: String, CodingKey {
        case patientId = "patient_id"
        case dateOfBirth = "date_of_birth"
    }
}

// MARK: - Refresh Token

/// Stored refresh token
struct RefreshToken: Codable, Sendable {
    let token: String
    let clientId: String
    let scope: String
    let createdAt: Double
}

// MARK: - Patient

/// Patient registration request
struct PatientRegistrationRequest: Content {
    let firstName: String
    let lastName: String
    let dateOfBirth: String

    func validate() throws {
        guard !firstName.isEmpty else {
            throw Abort(.badRequest, reason: "firstName is required")
        }
        guard !lastName.isEmpty else {
            throw Abort(.badRequest, reason: "lastName is required")
        }
        guard !dateOfBirth.isEmpty else {
            throw Abort(.badRequest, reason: "dateOfBirth is required")
        }
    }
}

/// Patient record stored in the patient store
struct PatientRecord: Content, Sendable {
    let id: String
    let firstName: String
    let lastName: String
    let dateOfBirth: String
    let createdAt: String
}

/// Patient registration response
struct PatientRegistrationResponse: Content {
    let patientId: String
    let message: String
}
