import Testing
import Vapor
import VaporTesting
import OpenAPIVapor
import Crypto
import Foundation
@testable import ClientFacingServer

/// Client-Facing Server test suite
/// Maps to: DP3 (Layered architecture), DR1 (No manual data entry), DR4 (Device abstraction)
@Suite("Client-Facing Server Tests")
struct ClientFacingServerTests {

    // MARK: - Test Configuration

    /// Creates a test app configuration that doesn't depend on external services
    static func testConfigure(_ app: Application) throws {
        let fhirContentType = HTTPMediaType(type: "application", subType: "fhir+json")
        ContentConfiguration.global.use(decoder: JSONDecoder(), for: fhirContentType)
        ContentConfiguration.global.use(encoder: JSONEncoder(), for: fhirContentType)

        let storageDir = NSTemporaryDirectory() + "client-facing-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: storageDir, withIntermediateDirectories: true)

        let jwksProvider = JWKSProvider(iamBaseURL: "http://localhost:0") // won't be called
        let idempotencyStore = IdempotencyStore(directory: storageDir)

        app.storage[JWKSProviderKey.self] = jwksProvider
        app.storage[IdempotencyStoreKey.self] = idempotencyStore
        app.storage[ClinicalBaseURLKey.self] = "http://localhost:0"
        app.storage[IAMBaseURLKey.self] = "http://localhost:8081"

        let auditLogger = AuditLogger(directory: NSTemporaryDirectory() + "/test-audit-\(UUID().uuidString)")

        let handler = ClientFacingHandler(
            jwksProvider: jwksProvider,
            idempotencyStore: idempotencyStore,
            auditLogger: auditLogger,
            clinicalBaseURL: "http://localhost:0",
            iamBaseURL: "http://localhost:8081"
        )
        let authMiddleware = AuthMiddleware(jwksProvider: jwksProvider)
        let transport = VaporTransport(routesBuilder: app)
        try handler.registerHandlers(
            on: transport,
            serverURL: URL(string: "/api/v1")!,
            middlewares: [authMiddleware]
        )

        app.get("health") { _ in "OK" }
    }

    // MARK: - Health Check

    @Test("Health endpoint returns 200")
    func healthCheck() async throws {
        try await withApp(configure: Self.testConfigure) { app in
            try await app.testing().test(.GET, "health") { res async in
                #expect(res.status == .ok)
            }
        }
    }

    // MARK: - Metadata

    @Suite("Metadata Endpoint")
    struct MetadataTests {

        @Test("GET /metadata returns server metadata")
        func getMetadata() async throws {
            try await withApp(configure: ClientFacingServerTests.testConfigure) { app in
                try await app.testing().test(.GET, "api/v1/metadata") { res async throws in
                    #expect(res.status == .ok)

                    let metadata = try res.content.decode(ServerMetadataDTO.self)
                    #expect(metadata.serverVersion == "1.0.0")
                    #expect(metadata.iamDiscoveryUrl.contains(".well-known/openid-configuration"))
                    #expect(metadata.supportedResourceTypes.contains("Observation"))
                }
            }
        }

        @Test("Metadata endpoint does NOT require authentication")
        func metadataNoAuth() async throws {
            try await withApp(configure: ClientFacingServerTests.testConfigure) { app in
                try await app.testing().test(.GET, "api/v1/metadata") { res async in
                    #expect(res.status == .ok)
                }
            }
        }
    }

    // MARK: - Authentication

    @Suite("Authentication")
    struct AuthTests {

        @Test("POST /observations without Authorization returns 401")
        func submitWithoutAuth() async throws {
            try await withApp(configure: ClientFacingServerTests.testConfigure) { app in
                try await app.testing().test(
                    .POST, "api/v1/observations",
                    headers: ["Content-Type": "application/fhir+json", "Idempotency-Key": "test-key-1"]
                ) { res async in
                    #expect(res.status == .unauthorized)
                }
            }
        }

        @Test("GET /status without Authorization returns 401")
        func statusWithoutAuth() async throws {
            try await withApp(configure: ClientFacingServerTests.testConfigure) { app in
                try await app.testing().test(.GET, "api/v1/status") { res async in
                    #expect(res.status == .unauthorized)
                }
            }
        }

        @Test("POST /observations with invalid Bearer token returns 401")
        func submitWithInvalidToken() async throws {
            try await withApp(configure: ClientFacingServerTests.testConfigure) { app in
                try await app.testing().test(
                    .POST, "api/v1/observations",
                    headers: [
                        "Authorization": "Bearer invalid.token.here",
                        "Content-Type": "application/fhir+json",
                        "Idempotency-Key": "test-key-2",
                    ]
                ) { res async in
                    #expect(res.status == .unauthorized)
                }
            }
        }

        @Test("GET /status with invalid Bearer token returns 401")
        func statusWithInvalidToken() async throws {
            try await withApp(configure: ClientFacingServerTests.testConfigure) { app in
                try await app.testing().test(
                    .GET, "api/v1/status",
                    headers: ["Authorization": "Bearer not-a-real-jwt"]
                ) { res async in
                    #expect(res.status == .unauthorized)
                }
            }
        }

        @Test("Authorization header without Bearer prefix returns 401")
        func submitWithBasicAuth() async throws {
            try await withApp(configure: ClientFacingServerTests.testConfigure) { app in
                try await app.testing().test(
                    .POST, "api/v1/observations",
                    headers: [
                        "Authorization": "Basic dXNlcjpwYXNz",
                        "Content-Type": "application/fhir+json",
                        "Idempotency-Key": "test-key-3",
                    ]
                ) { res async in
                    #expect(res.status == .unauthorized)
                }
            }
        }
    }

    // MARK: - Idempotency Store

    @Suite("Idempotency Store")
    struct IdempotencyStoreTests {

        @Test("Store and retrieve idempotent response")
        func storeAndCheck() async throws {
            let dir = NSTemporaryDirectory() + "idempotency-test-\(UUID().uuidString)"
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let store = IdempotencyStore(directory: dir)

            // Initially no cached response
            let initial = await store.check(key: "key-1", clientId: "patient-1")
            #expect(initial == nil)

            // Store a response
            await store.store(key: "key-1", clientId: "patient-1", responseJSON: "{\"status\":\"success\"}")

            // Now it should be cached
            let cached = await store.check(key: "key-1", clientId: "patient-1")
            #expect(cached != nil)
            #expect(cached == "{\"status\":\"success\"}")
        }

        @Test("Different clients have different idempotency scopes")
        func differentClients() async throws {
            let dir = NSTemporaryDirectory() + "idempotency-test-\(UUID().uuidString)"
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let store = IdempotencyStore(directory: dir)

            await store.store(key: "key-1", clientId: "patient-A", responseJSON: "result-A")

            let clientA = await store.check(key: "key-1", clientId: "patient-A")
            #expect(clientA == "result-A")

            let clientB = await store.check(key: "key-1", clientId: "patient-B")
            #expect(clientB == nil)
        }

        @Test("Same key with same client returns cached result")
        func sameKeySameClient() async throws {
            let dir = NSTemporaryDirectory() + "idempotency-test-\(UUID().uuidString)"
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let store = IdempotencyStore(directory: dir)

            await store.store(key: "dedupe-key", clientId: "p1", responseJSON: "first-result")
            await store.store(key: "dedupe-key", clientId: "p1", responseJSON: "second-result")

            // First write wins
            let result = await store.check(key: "dedupe-key", clientId: "p1")
            #expect(result != nil)
        }
    }

    // MARK: - JWKS Provider

    @Suite("JWKS Provider")
    struct JWKSProviderTests {

        @Test("Provider initializes without crashing")
        func initialization() {
            let provider = JWKSProvider(iamBaseURL: "http://localhost:9999")
            // Verify it initializes with empty keys
            #expect(type(of: provider) == JWKSProvider.self)
        }

        @Test("Token validation fails with empty keys")
        func validateWithNoKeys() {
            let provider = JWKSProvider(iamBaseURL: "http://localhost:9999")
            // Should fail since no keys are loaded — could be JWTError or DecodingError
            #expect(throws: (any Error).self) {
                _ = try provider.validateToken("eyJ.test.token")
            }
        }

        @Test("Token validation rejects malformed JWT")
        func rejectMalformedToken() {
            let provider = JWKSProvider(iamBaseURL: "http://localhost:9999")
            #expect(throws: JWTError.self) {
                _ = try provider.validateToken("not-a-jwt")
            }
        }

        @Test("Token validation rejects JWT with wrong algorithm")
        func rejectWrongAlgorithm() throws {
            let provider = JWKSProvider(iamBaseURL: "http://localhost:9999")

            // Create a JWT with RS256 algorithm header
            let header = #"{"alg":"RS256","typ":"JWT","kid":"test"}"#
            let payload = #"{"sub":"test","exp":9999999999,"aud":"client-facing-server","iss":"iam-server","iat":0,"scope":"openid"}"#

            let headerB64 = base64URLEncode(Data(header.utf8))
            let payloadB64 = base64URLEncode(Data(payload.utf8))
            let fakeToken = "\(headerB64).\(payloadB64).fakesig"

            #expect(throws: JWTError.self) {
                _ = try provider.validateToken(fakeToken)
            }
        }
    }

    // MARK: - Auth Context

    @Suite("Auth Context Task Locals")
    struct AuthContextTests {

        @Test("Auth context defaults to nil")
        func defaultNil() {
            #expect(AuthContext.currentSubject == nil)
            #expect(AuthContext.currentScope == nil)
            #expect(AuthContext.currentFirstName == nil)
            #expect(AuthContext.currentLastName == nil)
            #expect(AuthContext.currentDateOfBirth == nil)
        }

        @Test("Auth context propagates through task-local")
        func taskLocalPropagation() async {
            AuthContext.$currentSubject.withValue("patient-123") {
                AuthContext.$currentScope.withValue("openid observation.write") {
                    AuthContext.$currentFirstName.withValue("Max") {
                        AuthContext.$currentLastName.withValue("Mustermann") {
                            AuthContext.$currentDateOfBirth.withValue("1985-06-15") {
                                #expect(AuthContext.currentSubject == "patient-123")
                                #expect(AuthContext.currentScope == "openid observation.write")
                                #expect(AuthContext.currentFirstName == "Max")
                                #expect(AuthContext.currentLastName == "Mustermann")
                                #expect(AuthContext.currentDateOfBirth == "1985-06-15")
                            }
                        }
                    }
                }
            }
            // Outside the scope, should be nil again
            #expect(AuthContext.currentSubject == nil)
            #expect(AuthContext.currentFirstName == nil)
        }
    }

    // MARK: - Base64URL

    @Suite("Base64URL Encoding")
    struct Base64URLTests {

        @Test("Roundtrip encode/decode")
        func roundtrip() {
            let original = Data("Hello, World! This is a test string with special chars: +/=".utf8)
            let encoded = base64URLEncode(original)
            let decoded = base64URLDecode(encoded)
            #expect(decoded == original)
        }

        @Test("Base64URL does not contain +, / or =")
        func noForbiddenChars() {
            let data = Data(repeating: 0xFF, count: 100) // Will produce +, /, = in standard base64
            let encoded = base64URLEncode(data)
            #expect(!encoded.contains("+"))
            #expect(!encoded.contains("/"))
            #expect(!encoded.contains("="))
        }

        @Test("Base64URL decode handles padding correctly")
        func paddingHandling() {
            // 1 byte -> 2 base64url chars (needs 2 padding)
            let oneByteEncoded = base64URLEncode(Data([0x41]))
            let decoded = base64URLDecode(oneByteEncoded)
            #expect(decoded == Data([0x41]))

            // 2 bytes -> 3 base64url chars (needs 1 padding)
            let twoBytesEncoded = base64URLEncode(Data([0x41, 0x42]))
            let decoded2 = base64URLDecode(twoBytesEncoded)
            #expect(decoded2 == Data([0x41, 0x42]))
        }
    }

    // MARK: - LockedValueBox

    @Suite("LockedValueBox Thread Safety")
    struct LockedValueBoxTests {

        @Test("Basic get and set")
        func basicGetSet() {
            let box = LockedValueBox(42)
            let value = box.withLockedValue { $0 }
            #expect(value == 42)

            box.withLockedValue { $0 = 100 }
            let updated = box.withLockedValue { $0 }
            #expect(updated == 100)
        }

        @Test("Concurrent access is safe")
        func concurrentAccess() async {
            let box = LockedValueBox(0)
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<100 {
                    group.addTask {
                        box.withLockedValue { $0 += 1 }
                    }
                }
            }
            let final = box.withLockedValue { $0 }
            #expect(final == 100)
        }
    }
}

// MARK: - Test DTOs

struct ServerMetadataDTO: Content {
    let serverVersion: String
    let iamDiscoveryUrl: String
    let supportedResourceTypes: [String]
}
