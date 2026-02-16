import Vapor

/// Registers all IAM Server routes
/// Implements OAuth 2.0 Authorization Code + PKCE (RFC 6749, RFC 7636)
/// and OpenID Connect Discovery (DP4: Security and privacy by design)
func routes(_ app: Application) throws {
    // Health check
    app.get("health") { req -> HTTPStatus in
        .ok
    }

    // OpenID Connect Discovery
    app.get(".well-known", "openid-configuration") { req -> OIDCDiscoveryDocument in
        let baseURL = baseURL(from: req)
        return OIDCDiscoveryDocument(
            issuer: baseURL,
            authorizationEndpoint: "\(baseURL)/authorize",
            tokenEndpoint: "\(baseURL)/token",
            jwksURI: "\(baseURL)/jwks",
            revocationEndpoint: "\(baseURL)/revoke",
            responseTypesSupported: ["code"],
            grantTypesSupported: ["authorization_code", "refresh_token"],
            subjectTypesSupported: ["public"],
            idTokenSigningAlgValuesSupported: ["ES256"],
            codeChallengeMethodsSupported: ["S256"],
            scopesSupported: ["openid", "observation.write", "status.read"]
        )
    }

    // JWKS endpoint — public keys for token verification
    app.get("jwks") { req -> JWKSResponse in
        let jwk = req.application.keyManager.publicJWK()
        return JWKSResponse(keys: [jwk])
    }

    // Authorization endpoint — shows login page (GET)
    app.get("authorize") { req -> Response in
        let params = try req.query.decode(AuthorizationRequest.self)
        try params.validate()

        // Verify client_id is the registered iOS app
        guard params.clientId == knownClientId else {
            throw Abort(.badRequest, reason: "Unknown client_id")
        }

        // Render login page
        let html = loginPageHTML(
            clientId: params.clientId,
            redirectURI: params.redirectURI,
            scope: params.scope,
            state: params.state,
            codeChallenge: params.codeChallenge,
            codeChallengeMethod: params.codeChallengeMethod
        )

        return Response(
            status: .ok,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            body: .init(string: html)
        )
    }

    // Authorization endpoint — processes login form (POST)
    app.post("authorize") { req -> Response in
        // Decode OAuth parameters from hidden form fields
        let clientId = try req.content.get(String.self, at: "client_id")
        let redirectURI = try req.content.get(String.self, at: "redirect_uri")
        let scope = try req.content.get(String.self, at: "scope")
        let state = try req.content.get(String.self, at: "state")
        let codeChallenge = try req.content.get(String.self, at: "code_challenge")
        let codeChallengeMethod = try req.content.get(String.self, at: "code_challenge_method")

        // Verify client_id
        guard clientId == knownClientId else {
            throw Abort(.badRequest, reason: "Unknown client_id")
        }

        // Decode patient credentials
        let credentials = try req.content.decode(LoginCredentials.self)

        // Verify patient exists and credentials match
        guard let patient = await req.application.patientStore.get(patientId: credentials.patientId) else {
            let html = loginPageHTML(
                error: "Unknown patient ID. Please check your credentials.",
                clientId: clientId,
                redirectURI: redirectURI,
                scope: scope,
                state: state,
                codeChallenge: codeChallenge,
                codeChallengeMethod: codeChallengeMethod
            )
            return Response(
                status: .ok,
                headers: ["Content-Type": "text/html; charset=utf-8"],
                body: .init(string: html)
            )
        }

        // Verify date of birth matches
        guard patient.dateOfBirth == credentials.dateOfBirth else {
            let html = loginPageHTML(
                error: "Invalid credentials. Please try again.",
                clientId: clientId,
                redirectURI: redirectURI,
                scope: scope,
                state: state,
                codeChallenge: codeChallenge,
                codeChallengeMethod: codeChallengeMethod
            )
            return Response(
                status: .ok,
                headers: ["Content-Type": "text/html; charset=utf-8"],
                body: .init(string: html)
            )
        }

        // Authentication successful — generate authorization code
        let code = await req.application.authCodeStore.generate(
            clientId: clientId,
            patientId: patient.id,
            redirectURI: redirectURI,
            codeChallenge: codeChallenge,
            codeChallengeMethod: codeChallengeMethod,
            scope: scope,
            state: state
        )

        // Redirect back to app with code
        var redirectComponents = URLComponents(string: redirectURI)!
        redirectComponents.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "state", value: state),
        ]

        return req.redirect(to: redirectComponents.string!)
    }

    // Token endpoint — exchanges authorization code or refresh token for tokens
    app.post("token") { req -> TokenResponse in
        let params = try req.content.decode(TokenRequest.self)

        switch params.grantType {
        case "authorization_code":
            guard let code = params.code,
                  let redirectURI = params.redirectURI,
                  let codeVerifier = params.codeVerifier,
                  let clientId = params.clientId
            else {
                throw Abort(.badRequest, reason: "Missing required parameters for authorization_code grant")
            }

            // Validate authorization code
            guard let authCode = await req.application.authCodeStore.consume(code: code) else {
                throw Abort(.badRequest, reason: "Invalid or expired authorization code")
            }

            // Verify redirect URI matches
            guard authCode.redirectURI == redirectURI else {
                throw Abort(.badRequest, reason: "Redirect URI mismatch")
            }

            // Verify client ID matches
            guard authCode.clientId == clientId else {
                throw Abort(.badRequest, reason: "Client ID mismatch")
            }

            // Verify PKCE code challenge (RFC 7636)
            guard PKCEVerifier.verify(
                codeVerifier: codeVerifier,
                codeChallenge: authCode.codeChallenge,
                method: authCode.codeChallengeMethod
            ) else {
                throw Abort(.badRequest, reason: "PKCE verification failed")
            }

            // Look up patient demographics to embed in JWT claims
            // This avoids inter-service REST calls from Client-Facing to IAM.
            let patient = await req.application.patientStore.get(patientId: authCode.patientId)

            // Generate tokens — subject is the authenticated patient, not the client app
            let accessToken = try req.application.tokenService.generateAccessToken(
                subject: authCode.patientId,
                scope: authCode.scope,
                firstName: patient?.firstName,
                lastName: patient?.lastName,
                dateOfBirth: patient?.dateOfBirth
            )
            let refreshToken = await req.application.refreshTokenStore.generate(
                clientId: authCode.patientId,
                scope: authCode.scope
            )

            return TokenResponse(
                accessToken: accessToken,
                tokenType: "Bearer",
                expiresIn: 900, // 15 minutes
                refreshToken: refreshToken,
                scope: authCode.scope
            )

        case "refresh_token":
            guard let refreshTokenValue = params.refreshToken else {
                throw Abort(.badRequest, reason: "Missing refresh_token parameter")
            }

            // Validate refresh token
            guard let storedToken = await req.application.refreshTokenStore.consume(token: refreshTokenValue) else {
                throw Abort(.badRequest, reason: "Invalid or expired refresh token")
            }

            // Look up patient demographics to embed in JWT claims
            let patient = await req.application.patientStore.get(patientId: storedToken.clientId)

            // Generate new tokens
            let accessToken = try req.application.tokenService.generateAccessToken(
                subject: storedToken.clientId,
                scope: storedToken.scope,
                firstName: patient?.firstName,
                lastName: patient?.lastName,
                dateOfBirth: patient?.dateOfBirth
            )
            let newRefreshToken = await req.application.refreshTokenStore.generate(
                clientId: storedToken.clientId,
                scope: storedToken.scope
            )

            return TokenResponse(
                accessToken: accessToken,
                tokenType: "Bearer",
                expiresIn: 900,
                refreshToken: newRefreshToken,
                scope: storedToken.scope
            )

        default:
            throw Abort(.badRequest, reason: "Unsupported grant_type: \(params.grantType)")
        }
    }

    // Token revocation endpoint (RFC 7009)
    app.post("revoke") { req -> HTTPStatus in
        let params = try req.content.decode(RevocationRequest.self)
        await req.application.refreshTokenStore.revoke(token: params.token)
        return .ok
    }

    // Patient management endpoints (used by clinical staff)
    let patients = app.grouped("patients")

    patients.post { req -> PatientRegistrationResponse in
        let registration = try req.content.decode(PatientRegistrationRequest.self)
        try registration.validate()

        let patient = await req.application.patientStore.register(
            firstName: registration.firstName,
            lastName: registration.lastName,
            dateOfBirth: registration.dateOfBirth
        )

        return PatientRegistrationResponse(
            patientId: patient.id,
            message: "Patient registered successfully. Use patientId and dateOfBirth to log in."
        )
    }

    patients.delete(":patientId") { req -> HTTPStatus in
        guard let patientId = req.parameters.get("patientId") else {
            throw Abort(.badRequest)
        }

        guard await req.application.patientStore.delete(patientId: patientId) else {
            throw Abort(.notFound, reason: "Patient not found")
        }

        // Also revoke all refresh tokens for this patient
        await req.application.refreshTokenStore.revokeAll(clientId: patientId)

        return .noContent
    }

    patients.get { req -> [PatientRecord] in
        await req.application.patientStore.listAll()
    }

    patients.get(":patientId") { req -> PatientRecord in
        guard let patientId = req.parameters.get("patientId") else {
            throw Abort(.badRequest)
        }

        guard let patient = await req.application.patientStore.get(patientId: patientId) else {
            throw Abort(.notFound, reason: "Patient not found")
        }

        return patient
    }
}

// MARK: - Helpers

/// Derives the base URL from the incoming request
private func baseURL(from req: Request) -> String {
    let scheme = req.headers.first(name: "X-Forwarded-Proto") ?? "http"
    let host = req.headers.first(name: "Host") ?? "localhost:8081"
    return "\(scheme)://\(host)"
}
