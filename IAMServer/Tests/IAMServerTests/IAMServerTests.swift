import Testing
import Vapor
import VaporTesting
@testable import IAMServer

/// IAM Server test suite validating OAuth 2.0 / OIDC implementation
/// Maps to: DP4 (Security and privacy by design), DR5 (Security requirements)
@Suite("IAM Server Tests")
struct IAMServerTests {

    // MARK: - Health Check

    @Test("Health endpoint returns 200")
    func healthCheck() async throws {
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "health") { res async in
                #expect(res.status == .ok)
            }
        }
    }

    // MARK: - OIDC Discovery

    @Suite("OpenID Connect Discovery")
    struct OIDCDiscoveryTests {

        @Test("Discovery document contains required fields")
        func discoveryDocument() async throws {
            try await withApp(configure: configure) { app in
                try await app.testing().test(.GET, ".well-known/openid-configuration") { res async throws in
                    #expect(res.status == .ok)

                    let doc = try res.content.decode(OIDCDiscoveryDocument.self)
                    #expect(doc.responseTypesSupported == ["code"])
                    #expect(doc.grantTypesSupported == ["authorization_code", "refresh_token"])
                    #expect(doc.codeChallengeMethodsSupported == ["S256"])
                    #expect(doc.idTokenSigningAlgValuesSupported == ["ES256"])
                    #expect(doc.scopesSupported.contains("openid"))
                    #expect(doc.scopesSupported.contains("observation.write"))
                    #expect(doc.scopesSupported.contains("status.read"))

                    // Verify endpoint URLs are present
                    #expect(!doc.authorizationEndpoint.isEmpty)
                    #expect(!doc.tokenEndpoint.isEmpty)
                    #expect(!doc.jwksURI.isEmpty)
                    #expect(!doc.revocationEndpoint.isEmpty)
                }
            }
        }
    }

    // MARK: - JWKS

    @Suite("JWKS Endpoint")
    struct JWKSTests {

        @Test("JWKS returns EC P-256 public key")
        func jwksEndpoint() async throws {
            try await withApp(configure: configure) { app in
                try await app.testing().test(.GET, "jwks") { res async throws in
                    #expect(res.status == .ok)

                    let jwks = try res.content.decode(JWKSResponse.self)
                    #expect(jwks.keys.count == 1)

                    let key = jwks.keys[0]
                    #expect(key.kty == "EC")
                    #expect(key.crv == "P-256")
                    #expect(key.alg == "ES256")
                    #expect(key.use == "sig")
                    #expect(!key.kid.isEmpty)
                    #expect(!key.x.isEmpty)
                    #expect(!key.y.isEmpty)
                }
            }
        }
    }

    // MARK: - Patient Management

    @Suite("Patient Management")
    struct PatientManagementTests {

        @Test("Register a new patient")
        func registerPatient() async throws {
            try await withApp(configure: configure) { app in
                try await app.testing().test(.POST, "patients", beforeRequest: { req async throws in
                    try req.content.encode(PatientRegistrationRequest(
                        firstName: "Max",
                        lastName: "Mustermann",
                        dateOfBirth: "1990-01-15"
                    ))
                }) { res async throws in
                    #expect(res.status == .ok)

                    let response = try res.content.decode(PatientRegistrationResponse.self)
                    #expect(!response.patientId.isEmpty)
                    #expect(response.message.contains("successfully"))
                }
            }
        }

        @Test("List patients returns registered patient")
        func listPatients() async throws {
            try await withApp(configure: configure) { app in
                // Register a patient
                var patientId = ""
                try await app.testing().test(.POST, "patients", beforeRequest: { req async throws in
                    try req.content.encode(PatientRegistrationRequest(
                        firstName: "Anna",
                        lastName: "Schmidt",
                        dateOfBirth: "1985-03-20"
                    ))
                }) { res async throws in
                    let response = try res.content.decode(PatientRegistrationResponse.self)
                    patientId = response.patientId
                }

                // List patients
                try await app.testing().test(.GET, "patients") { res async throws in
                    #expect(res.status == .ok)
                    let patients = try res.content.decode([PatientRecord].self)
                    #expect(patients.contains(where: { $0.id == patientId }))
                }
            }
        }

        @Test("Delete patient returns 204")
        func deletePatient() async throws {
            try await withApp(configure: configure) { app in
                // Register
                var patientId = ""
                try await app.testing().test(.POST, "patients", beforeRequest: { req async throws in
                    try req.content.encode(PatientRegistrationRequest(
                        firstName: "Test",
                        lastName: "Delete",
                        dateOfBirth: "2000-06-01"
                    ))
                }) { res async throws in
                    let response = try res.content.decode(PatientRegistrationResponse.self)
                    patientId = response.patientId
                }

                // Delete
                try await app.testing().test(.DELETE, "patients/\(patientId)") { res async in
                    #expect(res.status == .noContent)
                }

                // Verify gone
                try await app.testing().test(.GET, "patients/\(patientId)") { res async in
                    #expect(res.status == .notFound)
                }
            }
        }

        @Test("Delete nonexistent patient returns 404")
        func deleteNonexistentPatient() async throws {
            try await withApp(configure: configure) { app in
                try await app.testing().test(.DELETE, "patients/nonexistent-id") { res async in
                    #expect(res.status == .notFound)
                }
            }
        }

        @Test("Register with empty firstName fails")
        func registerEmptyFirstName() async throws {
            try await withApp(configure: configure) { app in
                try await app.testing().test(.POST, "patients", beforeRequest: { req async throws in
                    try req.content.encode(PatientRegistrationRequest(
                        firstName: "",
                        lastName: "Valid",
                        dateOfBirth: "1990-01-01"
                    ))
                }) { res async in
                    #expect(res.status == .badRequest)
                }
            }
        }
    }

    // MARK: - Full OAuth Flow

    @Suite("OAuth 2.0 Authorization Code + PKCE Flow")
    struct OAuthFlowTests {

        @Test("Complete authorization code flow with PKCE")
        func completeFlow() async throws {
            try await withApp(configure: configure) { app in
                // Step 1: Register patient to get credentials
                var patientId = ""
                let dateOfBirth = "1995-07-10"
                try await app.testing().test(.POST, "patients", beforeRequest: { req async throws in
                    try req.content.encode(PatientRegistrationRequest(
                        firstName: "OAuth",
                        lastName: "Test",
                        dateOfBirth: dateOfBirth
                    ))
                }) { res async throws in
                    let response = try res.content.decode(PatientRegistrationResponse.self)
                    patientId = response.patientId
                }

                // Step 2: Generate PKCE values
                let codeVerifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
                let codeChallenge = PKCEVerifier.generateChallenge(from: codeVerifier)!

                // Step 3: GET /authorize — should return HTML login page
                let authQuery = "response_type=code&client_id=\(knownClientId)&redirect_uri=healthcompanion://callback&scope=openid%20observation.write&state=test-state-123&code_challenge=\(codeChallenge)&code_challenge_method=S256"

                try await app.testing().test(.GET, "authorize?\(authQuery)") { res async throws in
                    #expect(res.status == .ok)
                    let body = String(buffer: res.body)
                    #expect(body.contains("<form"))
                    #expect(body.contains("patient_id"))
                    #expect(body.contains("date_of_birth"))
                }

                // Step 4: POST /authorize with credentials — should redirect with code
                var authCode = ""
                try await app.testing().test(.POST, "authorize", beforeRequest: { req async throws in
                    req.headers.contentType = .urlEncodedForm
                    let body = "client_id=\(knownClientId)&redirect_uri=healthcompanion://callback&scope=openid%20observation.write&state=test-state-123&code_challenge=\(codeChallenge)&code_challenge_method=S256&patient_id=\(patientId)&date_of_birth=\(dateOfBirth)"
                    req.body = .init(string: body)
                }) { res async throws in
                    #expect(res.status == .seeOther)

                    let location = res.headers.first(name: .location)!
                    #expect(location.contains("healthcompanion://callback"))
                    #expect(location.contains("state=test-state-123"))

                    let components = URLComponents(string: location)!
                    authCode = components.queryItems!.first(where: { $0.name == "code" })!.value!
                }

                // Step 5: Token exchange
                try await app.testing().test(.POST, "token", beforeRequest: { req async throws in
                    try req.content.encode(TokenRequest(
                        grantType: "authorization_code",
                        code: authCode,
                        redirectURI: "healthcompanion://callback",
                        codeVerifier: codeVerifier,
                        clientId: knownClientId,
                        refreshToken: nil
                    ))
                }) { res async throws in
                    #expect(res.status == .ok)

                    let tokenResponse = try res.content.decode(TokenResponse.self)
                    #expect(!tokenResponse.accessToken.isEmpty)
                    #expect(tokenResponse.tokenType == "Bearer")
                    #expect(tokenResponse.expiresIn == 900)
                    #expect(!tokenResponse.refreshToken.isEmpty)
                    #expect(tokenResponse.scope == "openid observation.write")

                    // Verify the JWT sub is the patientId, not the client_id
                    let payload = try app.tokenService.validateAccessToken(tokenResponse.accessToken)
                    #expect(payload.sub == patientId)
                    #expect(payload.scope == "openid observation.write")
                    #expect(payload.iss == "iam-server")
                    #expect(payload.aud == "client-facing-server")

                    // Verify patient demographics are embedded in JWT claims
                    #expect(payload.firstName == "OAuth")
                    #expect(payload.lastName == "Test")
                    #expect(payload.dateOfBirth == dateOfBirth)
                }
            }
        }

        @Test("Authorization code can only be used once")
        func codeReuse() async throws {
            try await withApp(configure: configure) { app in
                // Register patient
                var patientId = ""
                let dob = "1990-01-01"
                try await app.testing().test(.POST, "patients", beforeRequest: { req async throws in
                    try req.content.encode(PatientRegistrationRequest(
                        firstName: "Reuse",
                        lastName: "Test",
                        dateOfBirth: dob
                    ))
                }) { res async throws in
                    let response = try res.content.decode(PatientRegistrationResponse.self)
                    patientId = response.patientId
                }

                // Generate PKCE
                let codeVerifier = "test-code-verifier-for-reuse-test-minimum-43-chars"
                let codeChallenge = PKCEVerifier.generateChallenge(from: codeVerifier)!

                // Authenticate via POST /authorize
                var authCode = ""
                try await app.testing().test(.POST, "authorize", beforeRequest: { req async throws in
                    req.headers.contentType = .urlEncodedForm
                    let body = "client_id=\(knownClientId)&redirect_uri=healthcompanion://callback&scope=openid&state=state1&code_challenge=\(codeChallenge)&code_challenge_method=S256&patient_id=\(patientId)&date_of_birth=\(dob)"
                    req.body = .init(string: body)
                }) { res async throws in
                    let location = res.headers.first(name: .location)!
                    let components = URLComponents(string: location)!
                    authCode = components.queryItems!.first(where: { $0.name == "code" })!.value!
                }

                // First exchange — should succeed
                try await app.testing().test(.POST, "token", beforeRequest: { req async throws in
                    try req.content.encode(TokenRequest(
                        grantType: "authorization_code",
                        code: authCode,
                        redirectURI: "healthcompanion://callback",
                        codeVerifier: codeVerifier,
                        clientId: knownClientId,
                        refreshToken: nil
                    ))
                }) { res async in
                    #expect(res.status == .ok)
                }

                // Second exchange — should fail
                try await app.testing().test(.POST, "token", beforeRequest: { req async throws in
                    try req.content.encode(TokenRequest(
                        grantType: "authorization_code",
                        code: authCode,
                        redirectURI: "healthcompanion://callback",
                        codeVerifier: codeVerifier,
                        clientId: knownClientId,
                        refreshToken: nil
                    ))
                }) { res async in
                    #expect(res.status == .badRequest)
                }
            }
        }

        @Test("Wrong PKCE verifier rejects token exchange")
        func wrongPKCEVerifier() async throws {
            try await withApp(configure: configure) { app in
                var patientId = ""
                let dob = "1990-01-01"
                try await app.testing().test(.POST, "patients", beforeRequest: { req async throws in
                    try req.content.encode(PatientRegistrationRequest(
                        firstName: "PKCE",
                        lastName: "Wrong",
                        dateOfBirth: dob
                    ))
                }) { res async throws in
                    let response = try res.content.decode(PatientRegistrationResponse.self)
                    patientId = response.patientId
                }

                let correctVerifier = "correct-verifier-must-be-at-least-43-chars-here"
                let wrongVerifier = "wrong---verifier-must-be-at-least-43-chars-here"
                let codeChallenge = PKCEVerifier.generateChallenge(from: correctVerifier)!

                var authCode = ""
                try await app.testing().test(.POST, "authorize", beforeRequest: { req async throws in
                    req.headers.contentType = .urlEncodedForm
                    let body = "client_id=\(knownClientId)&redirect_uri=healthcompanion://callback&scope=openid&state=state2&code_challenge=\(codeChallenge)&code_challenge_method=S256&patient_id=\(patientId)&date_of_birth=\(dob)"
                    req.body = .init(string: body)
                }) { res async throws in
                    let location = res.headers.first(name: .location)!
                    let components = URLComponents(string: location)!
                    authCode = components.queryItems!.first(where: { $0.name == "code" })!.value!
                }

                // Exchange with wrong verifier
                try await app.testing().test(.POST, "token", beforeRequest: { req async throws in
                    try req.content.encode(TokenRequest(
                        grantType: "authorization_code",
                        code: authCode,
                        redirectURI: "healthcompanion://callback",
                        codeVerifier: wrongVerifier,
                        clientId: knownClientId,
                        refreshToken: nil
                    ))
                }) { res async in
                    #expect(res.status == .badRequest)
                }
            }
        }

        @Test("Refresh token flow issues new tokens")
        func refreshTokenFlow() async throws {
            try await withApp(configure: configure) { app in
                var patientId = ""
                let dob = "1990-01-01"
                try await app.testing().test(.POST, "patients", beforeRequest: { req async throws in
                    try req.content.encode(PatientRegistrationRequest(
                        firstName: "Refresh",
                        lastName: "Flow",
                        dateOfBirth: dob
                    ))
                }) { res async throws in
                    let response = try res.content.decode(PatientRegistrationResponse.self)
                    patientId = response.patientId
                }

                let codeVerifier = "refresh-test-verifier-must-be-at-least-43-chars"
                let codeChallenge = PKCEVerifier.generateChallenge(from: codeVerifier)!

                var authCode = ""
                try await app.testing().test(.POST, "authorize", beforeRequest: { req async throws in
                    req.headers.contentType = .urlEncodedForm
                    let body = "client_id=\(knownClientId)&redirect_uri=healthcompanion://callback&scope=openid%20observation.write&state=state3&code_challenge=\(codeChallenge)&code_challenge_method=S256&patient_id=\(patientId)&date_of_birth=\(dob)"
                    req.body = .init(string: body)
                }) { res async throws in
                    let location = res.headers.first(name: .location)!
                    let components = URLComponents(string: location)!
                    authCode = components.queryItems!.first(where: { $0.name == "code" })!.value!
                }

                var refreshToken = ""
                try await app.testing().test(.POST, "token", beforeRequest: { req async throws in
                    try req.content.encode(TokenRequest(
                        grantType: "authorization_code",
                        code: authCode,
                        redirectURI: "healthcompanion://callback",
                        codeVerifier: codeVerifier,
                        clientId: knownClientId,
                        refreshToken: nil
                    ))
                }) { res async throws in
                    let tokenResponse = try res.content.decode(TokenResponse.self)
                    refreshToken = tokenResponse.refreshToken
                }

                // Use refresh token to get new tokens
                try await app.testing().test(.POST, "token", beforeRequest: { req async throws in
                    try req.content.encode(TokenRequest(
                        grantType: "refresh_token",
                        code: nil,
                        redirectURI: nil,
                        codeVerifier: nil,
                        clientId: nil,
                        refreshToken: refreshToken
                    ))
                }) { res async throws in
                    #expect(res.status == .ok)

                    let newTokens = try res.content.decode(TokenResponse.self)
                    #expect(!newTokens.accessToken.isEmpty)
                    #expect(!newTokens.refreshToken.isEmpty)
                    // Refresh token rotation: new token should differ
                    #expect(newTokens.refreshToken != refreshToken)
                }
            }
        }

        @Test("Used refresh token cannot be reused (rotation)")
        func refreshTokenRotation() async throws {
            try await withApp(configure: configure) { app in
                var patientId = ""
                let dob = "1990-01-01"
                try await app.testing().test(.POST, "patients", beforeRequest: { req async throws in
                    try req.content.encode(PatientRegistrationRequest(
                        firstName: "Rotation",
                        lastName: "Test",
                        dateOfBirth: dob
                    ))
                }) { res async throws in
                    let response = try res.content.decode(PatientRegistrationResponse.self)
                    patientId = response.patientId
                }

                let codeVerifier = "rotation-test-code-verifier-at-least-43chars!"
                let codeChallenge = PKCEVerifier.generateChallenge(from: codeVerifier)!

                var authCode = ""
                try await app.testing().test(.POST, "authorize", beforeRequest: { req async throws in
                    req.headers.contentType = .urlEncodedForm
                    let body = "client_id=\(knownClientId)&redirect_uri=healthcompanion://callback&scope=openid&state=state4&code_challenge=\(codeChallenge)&code_challenge_method=S256&patient_id=\(patientId)&date_of_birth=\(dob)"
                    req.body = .init(string: body)
                }) { res async throws in
                    let location = res.headers.first(name: .location)!
                    let components = URLComponents(string: location)!
                    authCode = components.queryItems!.first(where: { $0.name == "code" })!.value!
                }

                var refreshToken = ""
                try await app.testing().test(.POST, "token", beforeRequest: { req async throws in
                    try req.content.encode(TokenRequest(
                        grantType: "authorization_code",
                        code: authCode,
                        redirectURI: "healthcompanion://callback",
                        codeVerifier: codeVerifier,
                        clientId: knownClientId,
                        refreshToken: nil
                    ))
                }) { res async throws in
                    let tokenResponse = try res.content.decode(TokenResponse.self)
                    refreshToken = tokenResponse.refreshToken
                }

                // Use refresh token once
                try await app.testing().test(.POST, "token", beforeRequest: { req async throws in
                    try req.content.encode(TokenRequest(
                        grantType: "refresh_token",
                        code: nil,
                        redirectURI: nil,
                        codeVerifier: nil,
                        clientId: nil,
                        refreshToken: refreshToken
                    ))
                }) { res async in
                    #expect(res.status == .ok)
                }

                // Try to reuse — should fail
                try await app.testing().test(.POST, "token", beforeRequest: { req async throws in
                    try req.content.encode(TokenRequest(
                        grantType: "refresh_token",
                        code: nil,
                        redirectURI: nil,
                        codeVerifier: nil,
                        clientId: nil,
                        refreshToken: refreshToken
                    ))
                }) { res async in
                    #expect(res.status == .badRequest)
                }
            }
        }

        @Test("Token revocation invalidates refresh token")
        func tokenRevocation() async throws {
            try await withApp(configure: configure) { app in
                var patientId = ""
                let dob = "1990-01-01"
                try await app.testing().test(.POST, "patients", beforeRequest: { req async throws in
                    try req.content.encode(PatientRegistrationRequest(
                        firstName: "Revoke",
                        lastName: "Test",
                        dateOfBirth: dob
                    ))
                }) { res async throws in
                    let response = try res.content.decode(PatientRegistrationResponse.self)
                    patientId = response.patientId
                }

                let codeVerifier = "revoke-test-code-verifier-at-least-43-chars!"
                let codeChallenge = PKCEVerifier.generateChallenge(from: codeVerifier)!

                var authCode = ""
                try await app.testing().test(.POST, "authorize", beforeRequest: { req async throws in
                    req.headers.contentType = .urlEncodedForm
                    let body = "client_id=\(knownClientId)&redirect_uri=healthcompanion://callback&scope=openid&state=state5&code_challenge=\(codeChallenge)&code_challenge_method=S256&patient_id=\(patientId)&date_of_birth=\(dob)"
                    req.body = .init(string: body)
                }) { res async throws in
                    let location = res.headers.first(name: .location)!
                    let components = URLComponents(string: location)!
                    authCode = components.queryItems!.first(where: { $0.name == "code" })!.value!
                }

                var refreshToken = ""
                try await app.testing().test(.POST, "token", beforeRequest: { req async throws in
                    try req.content.encode(TokenRequest(
                        grantType: "authorization_code",
                        code: authCode,
                        redirectURI: "healthcompanion://callback",
                        codeVerifier: codeVerifier,
                        clientId: knownClientId,
                        refreshToken: nil
                    ))
                }) { res async throws in
                    let tokenResponse = try res.content.decode(TokenResponse.self)
                    refreshToken = tokenResponse.refreshToken
                }

                // Revoke
                try await app.testing().test(.POST, "revoke", beforeRequest: { req async throws in
                    try req.content.encode(RevocationRequest(
                        token: refreshToken,
                        tokenTypeHint: "refresh_token"
                    ))
                }) { res async in
                    #expect(res.status == .ok)
                }

                // Try to use revoked token
                try await app.testing().test(.POST, "token", beforeRequest: { req async throws in
                    try req.content.encode(TokenRequest(
                        grantType: "refresh_token",
                        code: nil,
                        redirectURI: nil,
                        codeVerifier: nil,
                        clientId: nil,
                        refreshToken: refreshToken
                    ))
                }) { res async in
                    #expect(res.status == .badRequest)
                }
            }
        }

        @Test("Unknown client_id rejected at authorization")
        func unknownClientId() async throws {
            try await withApp(configure: configure) { app in
                let codeVerifier = "unknown-client-test-verifier-43-chars-long!"
                let codeChallenge = PKCEVerifier.generateChallenge(from: codeVerifier)!

                let authQuery = "response_type=code&client_id=nonexistent&redirect_uri=healthcompanion://callback&scope=openid&state=state6&code_challenge=\(codeChallenge)&code_challenge_method=S256"

                try await app.testing().test(.GET, "authorize?\(authQuery)") { res async in
                    #expect(res.status == .badRequest)
                }
            }
        }

        @Test("Wrong date of birth shows error on login page")
        func wrongCredentials() async throws {
            try await withApp(configure: configure) { app in
                var patientId = ""
                try await app.testing().test(.POST, "patients", beforeRequest: { req async throws in
                    try req.content.encode(PatientRegistrationRequest(
                        firstName: "Wrong",
                        lastName: "DOB",
                        dateOfBirth: "1990-01-01"
                    ))
                }) { res async throws in
                    let response = try res.content.decode(PatientRegistrationResponse.self)
                    patientId = response.patientId
                }

                let codeVerifier = "wrong-dob-test-code-verifier-at-least-43chars!"
                let codeChallenge = PKCEVerifier.generateChallenge(from: codeVerifier)!

                // POST with wrong date of birth — should return login page with error
                try await app.testing().test(.POST, "authorize", beforeRequest: { req async throws in
                    req.headers.contentType = .urlEncodedForm
                    let body = "client_id=\(knownClientId)&redirect_uri=healthcompanion://callback&scope=openid&state=state7&code_challenge=\(codeChallenge)&code_challenge_method=S256&patient_id=\(patientId)&date_of_birth=2000-12-31"
                    req.body = .init(string: body)
                }) { res async throws in
                    #expect(res.status == .ok)
                    let body = String(buffer: res.body)
                    #expect(body.contains("Invalid credentials"))
                }
            }
        }

        @Test("Nonexistent patient shows error on login page")
        func nonexistentPatient() async throws {
            try await withApp(configure: configure) { app in
                let codeVerifier = "nonexist-patient-verifier-at-least-43-chars!"
                let codeChallenge = PKCEVerifier.generateChallenge(from: codeVerifier)!

                try await app.testing().test(.POST, "authorize", beforeRequest: { req async throws in
                    req.headers.contentType = .urlEncodedForm
                    let body = "client_id=\(knownClientId)&redirect_uri=healthcompanion://callback&scope=openid&state=state8&code_challenge=\(codeChallenge)&code_challenge_method=S256&patient_id=nonexistent-id&date_of_birth=1990-01-01"
                    req.body = .init(string: body)
                }) { res async throws in
                    #expect(res.status == .ok)
                    let body = String(buffer: res.body)
                    #expect(body.contains("Unknown patient ID"))
                }
            }
        }
    }

    // MARK: - Token Service Unit Tests

    @Suite("Token Service")
    struct TokenServiceTests {

        @Test("Generated JWT has correct structure")
        func jwtStructure() throws {
            let keyManager = KeyManager(privateKey: .init())
            let tokenService = TokenService(keyManager: keyManager)

            let token = try tokenService.generateAccessToken(
                subject: "test-subject",
                scope: "openid observation.write"
            )

            let parts = token.split(separator: ".")
            #expect(parts.count == 3)

            // Decode header
            let headerData = base64URLDecode(String(parts[0]))!
            let header = try JSONDecoder().decode(JWTHeader.self, from: headerData)
            #expect(header.alg == "ES256")
            #expect(header.typ == "JWT")

            // Decode payload
            let payloadData = base64URLDecode(String(parts[1]))!
            let payload = try JSONDecoder().decode(JWTPayload.self, from: payloadData)
            #expect(payload.sub == "test-subject")
            #expect(payload.scope == "openid observation.write")
            #expect(payload.iss == "iam-server")
            #expect(payload.aud == "client-facing-server")
            #expect(payload.exp > payload.iat)
            #expect(payload.exp - payload.iat == 900)
        }

        @Test("Valid token passes validation")
        func validTokenValidation() throws {
            let keyManager = KeyManager(privateKey: .init())
            let tokenService = TokenService(keyManager: keyManager)

            let token = try tokenService.generateAccessToken(
                subject: "patient-123",
                scope: "openid"
            )

            let payload = try tokenService.validateAccessToken(token)
            #expect(payload.sub == "patient-123")
            #expect(payload.scope == "openid")
        }

        @Test("Tampered token fails validation")
        func tamperedToken() throws {
            let keyManager = KeyManager(privateKey: .init())
            let tokenService = TokenService(keyManager: keyManager)

            let token = try tokenService.generateAccessToken(
                subject: "patient-123",
                scope: "openid"
            )

            // Tamper with the payload
            var parts = token.split(separator: ".").map(String.init)
            let payloadData = base64URLDecode(parts[1])!
            var payload = try JSONDecoder().decode(JWTPayload.self, from: payloadData)
            // We can't mutate payload directly since it's a struct with lets,
            // so we'll modify the base64 to simulate tampering
            parts[1] = parts[1] + "x"
            let tampered = parts.joined(separator: ".")

            #expect(throws: (any Error).self) {
                try tokenService.validateAccessToken(tampered)
            }
        }

        @Test("Token signed with different key fails validation")
        func wrongKeyValidation() throws {
            let keyManager1 = KeyManager(privateKey: .init())
            let keyManager2 = KeyManager(privateKey: .init())

            let tokenService1 = TokenService(keyManager: keyManager1)
            let tokenService2 = TokenService(keyManager: keyManager2)

            let token = try tokenService1.generateAccessToken(
                subject: "patient-456",
                scope: "openid"
            )

            #expect(throws: (any Error).self) {
                try tokenService2.validateAccessToken(token)
            }
        }
    }

    // MARK: - PKCE Unit Tests

    @Suite("PKCE Verifier")
    struct PKCEVerifierTests {

        @Test("Valid code verifier passes S256 challenge")
        func validVerifier() {
            let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
            let challenge = PKCEVerifier.generateChallenge(from: verifier)!

            let result = PKCEVerifier.verify(
                codeVerifier: verifier,
                codeChallenge: challenge,
                method: "S256"
            )
            #expect(result == true)
        }

        @Test("Wrong code verifier fails S256 challenge")
        func wrongVerifier() {
            let correctVerifier = "correct-verifier-12345678901234567890123"
            let wrongVerifier = "wrong---verifier-12345678901234567890123"
            let challenge = PKCEVerifier.generateChallenge(from: correctVerifier)!

            let result = PKCEVerifier.verify(
                codeVerifier: wrongVerifier,
                codeChallenge: challenge,
                method: "S256"
            )
            #expect(result == false)
        }

        @Test("Non-S256 method is rejected")
        func plainMethodRejected() {
            let verifier = "test-verifier-with-enough-characters-here!"
            let result = PKCEVerifier.verify(
                codeVerifier: verifier,
                codeChallenge: verifier,
                method: "plain"
            )
            #expect(result == false)
        }

        @Test("Generate challenge produces deterministic output")
        func deterministicChallenge() {
            let verifier = "deterministic-test-verifier-123456789012"
            let challenge1 = PKCEVerifier.generateChallenge(from: verifier)
            let challenge2 = PKCEVerifier.generateChallenge(from: verifier)
            #expect(challenge1 == challenge2)
        }
    }

    // MARK: - Patient Store Unit Tests

    @Suite("Patient Store")
    struct PatientStoreTests {

        @Test("Register and retrieve patient")
        func registerAndRetrieve() async {
            let store = PatientStore(directory: NSTemporaryDirectory() + "iam-test-\(UUID().uuidString)")

            let patient = await store.register(
                firstName: "Test",
                lastName: "Patient",
                dateOfBirth: "1990-01-01"
            )

            #expect(!patient.id.isEmpty)
            #expect(patient.firstName == "Test")
            #expect(patient.lastName == "Patient")

            let retrieved = await store.get(patientId: patient.id)
            #expect(retrieved?.id == patient.id)
        }

        @Test("Exists returns correct boolean")
        func existsCheck() async {
            let store = PatientStore(directory: NSTemporaryDirectory() + "iam-test-\(UUID().uuidString)")

            let patient = await store.register(
                firstName: "Exists",
                lastName: "Check",
                dateOfBirth: "1990-01-01"
            )

            #expect(await store.exists(patientId: patient.id) == true)
            #expect(await store.exists(patientId: "nonexistent") == false)
        }

        @Test("Delete removes patient")
        func deletePatient() async {
            let store = PatientStore(directory: NSTemporaryDirectory() + "iam-test-\(UUID().uuidString)")

            let patient = await store.register(
                firstName: "Delete",
                lastName: "Me",
                dateOfBirth: "1990-01-01"
            )

            let deleted = await store.delete(patientId: patient.id)
            #expect(deleted == true)
            #expect(await store.exists(patientId: patient.id) == false)
        }
    }
}
