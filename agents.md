# Workspace Agent Instructions

## Project Overview

This workspace implements the **exemplary implementation** of a health data integration artifact as specified in the LaTeX documentation under `docs/`. The artifact enables the automated transfer of Apple Watch health data (PGHD) from a patient's iPhone to a medical practice's PMS (Practice Management System).

The implementation follows the Design Science Research methodology and strictly adheres to the reference architecture, which specifies four components:

| Component | Directory | Port | Purpose |
|-----------|-----------|------|---------|
| Patient-Facing Client | `Health Companion/` | — | iOS app collecting PGHD via HealthKit, authenticating via OAuth 2.0 + PKCE, syncing FHIR bundles |
| Client-Facing Integration | `ClientFacingServer/` | 8082 | Receives FHIR data, validates auth, forwards to clinical integration; stateless for PGHD |
| Identity & Access Management | `IAMServer/` | 8081 | OAuth 2.0 / OIDC provider; patient authentication and authorization |
| Clinical System Integration | `ClinicalIntegrationServer/` | 8083 | Converts FHIR Observations to GDT 2.1 files for PMS pickup |

Additionally:
- `Specs/` — OpenAPI 3.1 specifications for Client-Facing and Clinical Integration APIs

## Design Principles (from specification)

- **DP1**: Simple integration into a practice's IT and processes
- **DP2**: PMS-agnostic interoperability using standardized interfaces and data models
- **DP3**: Layered architecture with device abstraction and modular expansion
- **DP4**: Security and privacy by design

## Design Requirements (from specification)

- **DR1**: No manual routine tasks beyond initial onboarding
- **DR2**: System-independent integration interface
- **DR3**: Standardized data models (FHIR R4, GDT 2.1)
- **DR4**: Device-specific data abstraction from clinical usage
- **DR5**: Common security and data protection principles
- **DR6**: Extensibility for additional PGHD sources

## Technology Stack

- **Language**: Swift 6.2 (strict concurrency)
- **Backend Framework**: Vapor 4.110.1+
- **API Generation**: swift-openapi-generator 1.7.2+ (Client-Facing, Clinical Integration)
- **FHIR**: Apple FHIRModels 0.6.0+ (ModelsR4)
- **Cryptography**: swift-crypto 3.0.0+ (EC P-256, JWT ES256)
- **iOS Framework**: Stanford Spezi 1.10.0 (SpeziHealthKit, SpeziFHIR, SpeziOnboarding)
- **Clinical Standard**: GDT 2.1 (Gerätedatentransfer), Latin-1 encoding
- **Auth Protocol**: OAuth 2.0 Authorization Code + PKCE (RFC 6749, 7636)
- **Testing**: Swift Testing (`@Suite`, `@Test`, `#expect`) + VaporTesting

## Key Conventions

### Code Style
- All types are `Sendable`-safe (Swift 6 strict concurrency)
- Actors for mutable shared state (`PatientStore`, `IdempotencyStore`, `StatusStore`, `AuditLogger`, `RateLimiter`)
- `@TaskLocal` for propagating auth context from middleware to handlers
- Text-file persistence (JSON lines in `.txt` files) — no database dependency
- OpenAPI-generated types (`Components.Schemas.*`, `Operations.*`) for typed API contracts

### Testing
- Use Swift Testing framework (not XCTest) for new tests
- Use `@Suite("Name")` for test suites, `@Test("Description")` for individual tests
- Use `#expect(...)` and `#require(...)` assertions
- Use `VaporTesting` with `app.testing().test(...)` for HTTP endpoint tests
- 92 tests total across all backend servers (26 + 22 + 44)

### Inter-Component Communication
- Client-Facing ↔ IAM: JWKS fetch, patient info lookup (HTTP)
- Client-Facing → Clinical: POST /api/v1/process with FHIR observations (HTTP)
- Clinical → PMS: GDT 2.1 files written to filesystem exchange directory
- iOS → Client-Facing: FHIR Bundles via REST API with Bearer token
- iOS → IAM: OAuth 2.0 Authorization Code + PKCE flow

### Security
- Access tokens: JWT ES256, 15-minute lifetime, audience `client-facing-server`
- Refresh tokens: 30-day lifetime with rotation (old token invalidated on use)
- PKCE: Required for all authorization requests (S256 method)
- TLS: Configurable via `TLS_CERT_PATH` / `TLS_KEY_PATH` environment variables
- Rate limiting: Sliding-window per-client (default 60 req/min)
- Audit logging: Append-only, SHA-256 payload hashes, no PGHD in logs
- iOS: Keychain storage for tokens (`kSecAttrAccessibleAfterFirstUnlock`)

## Module-Specific Documentation

Each module has its own `agents.md` with detailed instructions:
- `IAMServer/agents.md` — OAuth 2.0 / OIDC endpoints, token management, patient CRUD
- `ClientFacingServer/agents.md` — OpenAPI handler, auth middleware, idempotency, rate limiting
- `ClinicalIntegrationServer/agents.md` — FHIR-to-GDT conversion, GDTKit library, file output
- `Health Companion/agents.md` — iOS app, Spezi modules, auth flow, sync module

## How to Build and Run

```bash
# Build all backend servers
cd IAMServer && swift build
cd ../ClientFacingServer && swift build
cd ../ClinicalIntegrationServer && swift build

# Run all servers (separate terminals)
cd IAMServer && swift run IAMServer
cd ClientFacingServer && swift run ClientFacingServer
cd ClinicalIntegrationServer && swift run ClinicalIntegrationServer

# Run all tests
cd IAMServer && swift test
cd ../ClientFacingServer && swift test
cd ../ClinicalIntegrationServer && swift test

# Build iOS app
cd "Health Companion" && xcodebuild -scheme "Health Companion" -sdk iphonesimulator build
```

## Important Rules

1. **Never store PGHD in logs** — only SHA-256 hashes, timestamps, and pseudonymous patient refs
2. **Client-Facing Server is stateless for health data** — it only caches idempotency metadata
3. **All OpenAPI types are generated** — do not manually create DTOs that duplicate generated types
4. **GDT output uses Latin-1** encoding and GDT version `02.10` (not 3.5)
5. **FHIR resource IDs** — use `.fhirId` (public API), NOT `.fhirResourceId` (private `@_spi`)
6. **Avoid `ModelsR4.Observation`** in files with `@Observable` — the names collide; isolate FHIR imports
