# IAM Server — Agent Instructions

## Purpose

The Identity and Access Management (IAM) Server authenticates patients and enables unambiguous assignment of PGHD to specific patient files. It implements OAuth 2.0 Authorization Code + PKCE (RFC 6749, RFC 7636) with OpenID Connect Discovery.

**Spec references**: DP4 (security/privacy by design), DP1 (simple integration), §5.2.2 (component model), §5.4.3 (identity and access interfaces)

## Architecture

```
Sources/IAMServer/
├── IAMServerMain.swift          # @main entry point
├── configure.swift              # Vapor app config, storage keys, TLS setup
├── routes.swift                 # All HTTP routes (OIDC, OAuth, patient CRUD)
├── Models.swift                 # DTOs: OIDCDiscoveryDocument, JWK/JWKS, TokenRequest/Response, etc.
├── KeyManager.swift             # EC P-256 key pair generation and PEM persistence
├── TokenService.swift           # JWT ES256 signing (access tokens, 15-min lifetime)
├── PKCEVerifier.swift           # S256 PKCE code_challenge verification
├── PatientStore.swift           # Actor: patient records in JSON lines text file
├── PatientVerificationService.swift  # Protocol abstracting patient identity source (PMS-ready)
├── AuthorizationCodeStore.swift # Actor: single-use auth codes (10-min expiry)
└── RefreshTokenStore.swift      # Actor: refresh tokens (30-day, rotation)

Tests/IAMServerTests/
└── IAMServerTests.swift         # 26 tests in 8 suites
```

## Endpoints

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| GET | `/health` | No | Health check |
| GET | `/.well-known/openid-configuration` | No | OIDC Discovery document |
| GET | `/jwks` | No | JSON Web Key Set (public keys for token verification) |
| POST | `/authorize` | No | OAuth authorization (issues auth code, requires PKCE) |
| POST | `/token` | No | Token exchange (auth_code → tokens, refresh_token → tokens) |
| POST | `/revoke` | No | Token revocation (RFC 7009) |
| POST | `/patients` | No* | Register a new patient (clinical staff) |
| GET | `/patients` | No* | List all patients |
| GET | `/patients/:patientId` | No* | Get patient by ID |
| DELETE | `/patients/:patientId` | No* | Delete patient + revoke all tokens |

*Patient management endpoints would be protected in production (out of scope for exemplary impl.)

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `IAM_PORT` | `8081` | Server listen port |
| `IAM_STORAGE_DIR` | `./data` | Directory for text-file persistence |
| `TLS_CERT_PATH` | — | PEM certificate file for TLS (optional) |
| `TLS_KEY_PATH` | — | PEM private key file for TLS (optional) |

## Key Design Decisions

### Token Lifetimes
- **Access token**: 15 minutes (JWT ES256, `aud: "client-facing-server"`)
- **Refresh token**: 30 days, rotation on use (old token invalidated)
- **Authorization code**: 10 minutes, single-use

### Patient Verification Service
The `PatientVerificationService` protocol abstracts patient identity verification:
- The bundled `PatientStore` (text-file based) implements it for the exemplary implementation
- In production, a PMS-backed implementation would conform to this protocol
- The spec requires IAM to "interact with the PMS to verify whether the person authenticating is actually a patient" (§5.2.2)

### Persistence
All data stored as JSON lines in text files (no database):
- `patients.txt` — patient records
- `auth_codes.txt` — active authorization codes
- `refresh_tokens.txt` — active refresh tokens
- `private_key.pem` / `public_key.pem` — EC P-256 signing keys

## Testing

```bash
swift test  # Runs 26 tests in 8 suites
```

Test suites: Health Endpoint, OIDC Discovery, JWKS Endpoint, Authorization Endpoint, Token Service, Patient Store, PKCE Verifier, OAuth 2.0 Authorization Code + PKCE Flow

## Important Rules

1. **Never log tokens** — access tokens and refresh tokens must never appear in log output
2. **PKCE is mandatory** — all authorization requests must include `code_challenge` + `code_challenge_method=S256`
3. **Refresh token rotation** — consuming a refresh token always invalidates it; a new one is issued
4. **Patient IDs are UUIDs** — generated server-side, not user-provided
5. **Key persistence** — EC P-256 keys are persisted as PEM; restarting the server reuses existing keys
