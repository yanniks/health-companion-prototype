# Client-Facing Integration Server — Agent Instructions

## Purpose

The Client-Facing Integration Server receives FHIR health data from the patient-facing iOS client, validates authentication, and forwards normalized data to the Clinical Integration Server. It is intentionally **stateless** for health data — no PGHD is persisted.

**Spec references**: DP3 (layered architecture), DP4 (stateless, security), §5.2.2 (component model), §5.4.2 (patient-facing interfaces), §5.5.1 (security controls)

## Architecture

```
Sources/ClientFacingServer/
├── ClientFacingServerMain.swift   # @main entry point
├── configure.swift                # Vapor config, TLS, rate limiter, storage keys
├── openapi.yaml                   # OpenAPI 3.1 spec (source of truth for API contract)
├── openapi-generator-config.yaml  # swift-openapi-generator plugin config
├── ClientFacingHandler.swift      # APIProtocol impl: getMetadata, submitObservations, getTransferStatus
├── AuthMiddleware.swift           # OpenAPI ServerMiddleware: Bearer token → JWT validation → TaskLocal
├── JWKSProvider.swift             # Fetches JWKS from IAM, validates JWTs locally (ES256)
├── IdempotencyStore.swift         # Actor: deduplicates submissions using Idempotency-Key header
├── PatientInfoStore.swift         # Fetches patient demographics from IAM for clinical context
├── AuditLogger.swift              # Actor: append-only audit trail with SHA-256 payload hashes
└── RateLimiter.swift              # Actor + ServerMiddleware: per-client sliding-window rate limiting

Tests/ClientFacingServerTests/
└── ClientFacingServerTests.swift  # 22 tests in 8 suites
```

## API (OpenAPI 3.1 — generated types)

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| GET | `/health` | No | Health check (plain Vapor route) |
| GET | `/api/v1/metadata` | No | Public server metadata + IAM discovery URL |
| POST | `/api/v1/observations` | Bearer | Submit FHIR Bundle of Observations |
| GET | `/api/v1/status` | Bearer | Get transfer status for authenticated patient |

The `Idempotency-Key` header is **required** on `POST /observations` (enforced via OpenAPI schema).

Generated types live in `.build/` and include: `Components.Schemas.ServerMetadata`, `Components.Schemas.SubmissionResult`, `Components.Schemas.TransferStatus`, `Components.Schemas.FHIRBundle`, `Components.Schemas.ObservationResult`, `Components.Schemas.ErrorResponse`.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLIENT_PORT` | `8082` | Server listen port |
| `CLIENT_STORAGE_DIR` | `./data` | Directory for idempotency store and audit logs |
| `IAM_BASE_URL` | `http://localhost:8081` | IAM server URL for JWKS + patient info |
| `CLINICAL_BASE_URL` | `http://localhost:8083` | Clinical Integration Server URL |
| `RATE_LIMIT_MAX` | `60` | Max requests per window per client |
| `RATE_LIMIT_WINDOW` | `60.0` | Rate limit window in seconds |
| `TLS_CERT_PATH` | — | PEM certificate file for TLS (optional) |
| `TLS_KEY_PATH` | — | PEM private key file for TLS (optional) |

## Key Design Decisions

### Statelessness (DP4)
The server **never persists health data**. The `IdempotencyStore` caches only:
- Composite key (`clientId:idempotencyKey`)
- Serialized `SubmissionResult` metadata (status, counts, errors — not PGHD)
- 24-hour automatic expiry

### Auth Flow
1. `AuthMiddleware` extracts Bearer token from `Authorization` header
2. `JWKSProvider.validateToken()` verifies JWT signature (ES256) against IAM public keys
3. `AuthContext.$currentSubject` task-local is set with the `sub` claim (patient ID)
4. Handler reads `AuthContext.currentSubject` to identify the patient
5. `RateLimitMiddleware` enforces per-client request limits

### Audit Logging (DP4, §5.5.1)
The `AuditLogger` records every submission and status query:
- SHA-256 hash of the request payload (never the payload itself)
- Idempotency key, pseudonymous patient reference, timestamp, outcome
- Append-only JSON lines file (`audit.log`)

### Forwarding to Clinical Integration
Observations are forwarded as plain JSON (not OpenAPI-generated types) to `POST /api/v1/process` on the Clinical Integration Server. The `ClinicalProcessingResponse` and `ClinicalPatientStatus` DTOs are defined locally in `ClientFacingHandler.swift`.

## Testing

```bash
swift test  # Runs 22 tests in 8 suites
```

Test suites: Health, Metadata, Authentication (5 tests), IdempotencyStore (3), JWKSProvider (4), AuthContext (2), Base64URL (3), LockedValueBox (2)

## Important Rules

1. **Do not modify `openapi.yaml` without re-building** — the OpenAPI generator plugin runs at build time
2. **Do not create manual DTOs** for API types — use `Components.Schemas.*` and `Operations.*`
3. **Never log request bodies or PGHD** — only use `AuditLogger` for structured audit entries
4. **Rate limit applies after auth** — unauthenticated endpoints (metadata) are exempt
5. **JWKS is cached** — `JWKSProvider.refresh()` is called on startup; manual refresh on validation failure
