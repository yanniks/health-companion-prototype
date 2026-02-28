# PGHD Integration Artifact — Exemplary Implementation

Exemplary implementation of a health data integration artifact that enables the automated transfer of Apple Watch health data (Patient-Generated Health Data, PGHD) from a patient's iPhone to a medical practice's Practice Management System (PMS).

This implementation follows the reference architecture defined in the accompanying thesis and demonstrates technical feasibility of the integration concept.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Requirements](#requirements)
- [Getting Started](#getting-started)
- [Running with Docker](#running-with-docker)
- [Environment Variables](#environment-variables)
- [Testing](#testing)
- [OpenAPI Specifications](#openapi-specifications)
- [Security Considerations](#security-considerations)
- [Deviations from Specification](#deviations-from-specification)
- [Known Limitations](#known-limitations)
- [Project Structure](#project-structure)

## Architecture Overview

The artifact consists of four components as defined by the reference architecture:

```
┌──────────────┐     FHIR Bundle      ┌──────────────────┐     FHIR JSON     ┌─────────────────────┐
│              │   (Bearer + Idemp.)  │                  │                   │                     │
│  iOS Client  ├─────────────────────►│  Client-Facing   ├──────────────────►│ Clinical Integration│
│  (iPhone)    │◄─────────────────────┤  Server (:8082)  │◄──────────────────┤ Server (:8083)      │
│              │    SubmissionResult  │                  │   GDT Result      │                     │
└──────┬───────┘                      └────────┬─────────┘                   └──────────┬──────────┘
       │                                       │                                        │
       │  OAuth 2.0 + PKCE                     │  JWKS fetch                            │  GDT 2.1 files
       │                                       │  Patient info                          │
       ▼                                       ▼                                        ▼
┌──────────────┐                      ┌──────────────────┐                   ┌──────────────────────┐
│    IAM       │                      │   IAM Server     │                   │   PMS Exchange Dir   │
│  Server      │◄─────────────────────┤   (:8081)        │                   │   (filesystem)       │
│  (:8081)     │                      │                  │                   │                      │
└──────────────┘                      └──────────────────┘                   └──────────────────────┘
```

| Component | Directory | Port | Role |
|-----------|-----------|------|------|
| Patient-Facing Client | `Health Companion/` | — | iOS app: HealthKit data collection, OAuth login, FHIR sync |
| Client-Facing Integration | `ClientFacingServer/` | 8082 | Receives FHIR data, validates auth, forwards to clinical; stateless for PGHD |
| Identity & Access Management | `IAMServer/` | 8081 | OAuth 2.0 / OIDC: patient authentication, JWT issuance, patient management |
| Clinical System Integration | `ClinicalIntegrationServer/` | 8083 | FHIR → GDT 2.1 conversion, writes .gdt files for PMS pickup |

Additionally:
- `Specs/` — OpenAPI 3.1 specifications (canonical copies)

## Requirements

- **Swift 6.2** or later
- **macOS 14 or later / Linux-based OS** (for backend servers)
- **Xcode 16.2+** (for iOS app)
- **iOS 17+** target (for Health Companion app)
- No database required — all persistence uses text files (JSON lines)

## Getting Started

### 1. Build all backend servers

```bash
cd IAMServer && swift build
cd ../ClientFacingServer && swift build
cd ../ClinicalIntegrationServer && swift build
```

### 2. Start all servers (in separate terminals)

```bash
# Terminal 1 — IAM Server
cd IAMServer && swift run IAMServer

# Terminal 2 — Client-Facing Server
cd ClientFacingServer && swift run ClientFacingServer

# Terminal 3 — Clinical Integration Server
cd ClinicalIntegrationServer && swift run ClinicalIntegrationServer
```

### 3. Register a test patient

```bash
curl -X POST http://localhost:8081/patients \
  -H "Content-Type: application/json" \
  -d '{"firstName": "Max", "lastName": "Mustermann", "dateOfBirth": "1990-01-15"}'
```

The response includes a `patientId` (incrementing number, e.g., `1`, `2`, `3`) used as the login credential together with the date of birth.

### 4. Build the iOS app

```bash
cd "Health Companion"
xcodebuild -scheme "Health Companion" -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' build
```

### 5. Configure the iOS app

In the app's onboarding flow:
1. Enter the Server URL (e.g., `http://localhost:8082`) — the app automatically discovers the IAM server configuration via the Client-Facing Server's `/api/v1/metadata` endpoint
2. Enter the `patientId` from step 3
3. Complete the OAuth login

## Running with Docker

All three backend servers can be built and run as Docker containers using the included `docker-compose.yml`.

### Prerequisites

- **Docker** 20.10+ and **Docker Compose** v2

### Start all services

```bash
docker compose up --build
```

This builds all three server images from source (using `swift:6.2` build stage and `ubuntu:noble` runtime) and starts them with correct inter-service networking:

| Service | Container Port | Host Port | Health Check |
|---------|---------------|-----------|---|
| `iam-server` | 8081 | 8081 | `GET /.well-known/openid-configuration` |
| `client-facing-server` | 8082 | 8082 | `GET /api/v1/metadata` |
| `clinical-integration-server` | 8083 | 8083 | `GET /api/v1/metadata` |

The Client-Facing Server waits for the IAM Server's health check to pass before starting.

### Persistent volumes

| Volume | Purpose |
|--------|---------|
| `iam-data` | Patient store, key material, audit logs |
| `client-data` | Idempotency store, audit logs |
| `clinical-data` | Status store, audit logs |
| `gdt-exchange` | GDT 2.1 output files for PMS pickup |

To reset all data:

```bash
docker compose down -v
```

### Run in detached mode

```bash
docker compose up --build -d
docker compose logs -f          # follow logs
docker compose down              # stop all services
```

### Register a test patient (Docker)

```bash
curl -X POST http://localhost:8081/patients \
  -H "Content-Type: application/json" \
  -d '{"firstName": "Max", "lastName": "Mustermann", "dateOfBirth": "1990-01-15"}'
```

### Accessing GDT output

GDT files written by the Clinical Integration Server are stored in the `gdt-exchange` volume. To inspect them:

```bash
docker compose exec clinical-integration-server ls /app/gdt-output
```

Or mount a local directory instead of the named volume for direct PMS access:

```yaml
# In docker-compose.yml, replace the gdt-exchange volume with a bind mount:
volumes:
  - ./gdt_exchange:/app/gdt-output
```

## Environment Variables

### IAM Server

| Variable | Default | Description |
|----------|---------|-------------|
| `IAM_PORT` | `8081` | Listen port |
| `IAM_STORAGE_DIR` | `./data` | Persistence directory |
| `TLS_CERT_PATH` | — | PEM certificate for TLS |
| `TLS_KEY_PATH` | — | PEM private key for TLS |

### Client-Facing Server

| Variable | Default | Description |
|----------|---------|-------------|
| `CLIENT_PORT` | `8082` | Listen port |
| `CLIENT_STORAGE_DIR` | `./data` | Persistence directory (idempotency, audit) |
| `IAM_BASE_URL` | `http://localhost:8081` | IAM server URL |
| `CLINICAL_BASE_URL` | `http://localhost:8083` | Clinical Integration Server URL |
| `RATE_LIMIT_MAX` | `60` | Max requests per window per client |
| `RATE_LIMIT_WINDOW` | `60.0` | Rate limit window (seconds) |
| `TLS_CERT_PATH` | — | PEM certificate for TLS |
| `TLS_KEY_PATH` | — | PEM private key for TLS |

### Clinical Integration Server

| Variable | Default | Description |
|----------|---------|-------------|
| `CLINICAL_PORT` | `8083` | Listen port |
| `CLINICAL_STORAGE_DIR` | `./data` | Persistence directory (status tracking) |
| `GDT_OUTPUT_PATH` | `./gdt_exchange` | Directory for .gdt file output |
| `GDT_SENDER_ID` | `HEALTH_COMPANION` | GDT sender identifier (FK 9106) |
| `GDT_RECEIVER_ID` | `PVS` | GDT receiver identifier (FK 9103) |
| `TLS_CERT_PATH` | — | PEM certificate for TLS |
| `TLS_KEY_PATH` | — | PEM private key for TLS |

## Testing

```bash
# All backend tests (92 total)
cd IAMServer && swift test            # 26 tests, 8 suites
cd ../ClientFacingServer && swift test    # 22 tests, 8 suites
cd ../ClinicalIntegrationServer && swift test  # 44 tests, 13 suites

# iOS app build verification
cd "../Health Companion" && xcodebuild -scheme "Health Companion" \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```

All tests use Swift Testing (`@Suite`, `@Test`, `#expect`, `#require`) and VaporTesting.

## OpenAPI Specifications

The Client-Facing and Clinical Integration servers use `swift-openapi-generator` with OpenAPI 3.1 specs:

- `Specs/openapi-client-facing.yaml` — canonical spec (copied to `ClientFacingServer/Sources/ClientFacingServer/openapi.yaml`)
- `Specs/openapi-clinical-integration.yaml` — canonical spec (copied to `ClinicalIntegrationServer/Sources/ClinicalIntegrationServer/openapi.yaml`)

Types are generated at build time. Do not manually create DTOs for API contracts.

## Security Considerations

The following security measures are implemented per the specification's DP4 requirements:

| Measure | Status | Details |
|---------|--------|---------|
| OAuth 2.0 + PKCE | ✅ | RFC 6749, 7636; S256 method required |
| Short-lived access tokens | ✅ | JWT ES256, 15-minute lifetime, audience validation |
| Refresh token rotation | ✅ | 30-day lifetime; old token invalidated on use |
| Token revocation | ✅ | RFC 7009; also revokes on patient deletion |
| Consent withdrawal | ✅ | Logout revokes tokens server-side + clears iOS Keychain |
| PGHD statelessness | ✅ | Client-Facing Server never persists health data |
| Audit logging | ✅ | SHA-256 payload hashes, timestamps, message IDs; append-only |
| Data minimization in logs | ✅ | No PGHD in log output; only UUIDs and error categories |
| Idempotency enforcement | ✅ | Required `Idempotency-Key` header via OpenAPI schema |
| Rate limiting | ✅ | Per-client sliding-window; configurable limits |
| TLS support | ✅ | NIOSSL configuration via env vars (not active by default) |
| iOS Keychain storage | ✅ | `kSecAttrAccessibleAfterFirstUnlock` for tokens |
| Retry with backoff | ✅ | Exponential backoff (3 attempts) on iOS sync failures |

### What requires manual security setup in production

- **TLS certificates** — set `TLS_CERT_PATH` and `TLS_KEY_PATH`, or use a reverse proxy
- **Patient management endpoint protection** — currently unauthenticated (see deviations)
- **Network segmentation** — Clinical Integration Server should not be internet-accessible
- **GDT exchange directory permissions** — restrict filesystem access to the PMS user
- **CORS configuration** — not configured (not needed for native iOS client)

## Deviations from Specification

The following intentional deviations from the reference architecture are documented:

### 1. IAM ↔ PMS Patient Verification

**Spec (§5.2.2)**: *"The IAM component interacts with the PMS to verify whether the person authenticating is actually a patient of the practice. This integration is important so that manual management of patient lists in the component is not necessary."*

**Implementation**: The IAM uses a local `PatientStore` (text-file based) with REST endpoints for patient registration. A `PatientVerificationService` protocol has been introduced to abstract this, allowing a PMS-backed implementation to be substituted.

**Rationale**: Connecting to a real PMS requires access to a specific PMS instance and its proprietary or GDT-based patient query interface, which is outside the scope of an exemplary implementation. The protocol abstraction ensures architectural compliance while keeping the prototype self-contained.

### 2. Patient Management Endpoints Are Unauthenticated

**Spec (§5.3)**: Practice staff manage patient onboarding via the PMS.

**Implementation**: The `POST/GET/DELETE /patients` endpoints on the IAM server are not protected by authentication. In production, these would be restricted to the clinical network or protected by a separate staff authentication mechanism.

**Rationale**: Implementing a second auth system for clinical staff is orthogonal to the core patient data flow and would add complexity without demonstrating the primary artifact capabilities.

### 3. TLS Not Active by Default

**Spec (§5.5.1)**: *"Communication between all components must be encrypted using TLS."*

**Implementation**: TLS is supported via `TLS_CERT_PATH` / `TLS_KEY_PATH` environment variables using NIOSSL, but defaults to plain HTTP for development convenience.

**Rationale**: Self-signed certificates complicate local development. In production deployments, TLS would be enabled either at the application level or via a reverse proxy (nginx, Caddy, cloud load balancer). The code path for TLS is fully implemented and tested at the framework level.

### 4. No Backend-to-PMS Import Confirmation

**Spec (§5.4.2)**: *"Ideally, the last transfer date from the PMS should be consulted."*

**Implementation**: "Successful transfer" refers to confirmed handover to the clinical integration server and writing of the GDT file. There is no callback from the PMS confirming import.

**Rationale**: GDT is a file-based protocol — the PMS polls a directory. There is no standardized mechanism for the PMS to acknowledge successful import back to the artifact. The spec explicitly acknowledges this: *"When reliable confirmation of import into the PMS is unavailable (e.g., file-based integrations), 'successful transfer' refers to confirmed handover to the practice-side integration endpoint."*

### 5. SMART on FHIR Not Adopted

**Spec (§5.4.5)**: SMART on FHIR is discussed as a potential standard for patient-facing interfaces.

**Implementation**: Uses versioned REST/JSON APIs with OAuth 2.0 + PKCE instead of SMART on FHIR.

**Rationale**: The spec explicitly defers SMART on FHIR to future iterations: *"SMART on FHIR is treated as an option for a further artifact iteration for more mature FHIR-enabled environments, rather than a prerequisite for the exemplary implementation."*

### 6. No Deletion of Previously Submitted Health Data on Consent Withdrawal

**Spec (§5.5.2)**: Users should be able to withdraw consent and stop further transmission.

**Implementation**: Logout revokes OAuth tokens and stops future data transmission. However, GDT files already written to the PMS exchange directory are not deleted.

**Rationale**: Once GDT files are handed over to the PMS, they may already be imported. Deleting files from the exchange directory would be unreliable and potentially violate medical record retention requirements. The spec focuses on revoking access ("trigger token revocation and stop further transmission"), which is fully implemented.

### 7. Client-Facing ↔ Clinical Integration Communication Uses Plain JSON

**Spec (§5.4.5)**: Internal interfaces should use documented, versioned APIs.

**Implementation**: The Client-Facing Server forwards observations to the Clinical Integration Server as plain JSON (manually serialized), not via the OpenAPI-generated client types.

**Rationale**: Using `swift-openapi-urlsession` for this internal call would introduce a circular dependency and additional complexity. The JSON contract is documented in the OpenAPI spec and used identically on both sides.

### 8. Rate Limiter Is In-Memory Only

**Implementation**: The `RateLimiter` actor tracks request timestamps in memory. These are lost on server restart.

**Rationale**: For a single-instance deployment, in-memory rate limiting is sufficient. Distributed deployments would require a shared store (e.g., Redis), which is outside the scope of this exemplary implementation.

## Known Limitations

- **Single-instance only** — no clustering or distributed state; all stores are file-based
- **No HTTPS by default** — requires manual TLS setup or a reverse proxy
- **No automated patient onboarding from PMS** — patients are registered via REST API
- **ECG data only** — the current FHIR-to-GDT mapping covers ECG observations; additional PGHD types (blood pressure, SpO2, etc.) would require extending the converter
- **No automated background sync on iOS** — sync is triggered manually or on app launch; iOS background task scheduling is not implemented
- **No push notifications** — the iOS app does not receive push notifications for sync failures
- **GDT 2.1 only** — GDT 3.5 is not supported in the clinical integration server (though GDTKit supports both versions)
- **No FHIR validation** — incoming FHIR Bundles are not validated against the FHIR R4 schema beyond basic structural checks
- **No multi-practice support** — the architecture assumes a single practice deployment per instance

## Project Structure

```
Swift-Code/
├── agents.md                          # Root agent instructions (this file references)
├── README.md                          # This file
├── docker-compose.yml                 # Docker Compose for all backend services
├── Specs/
│   ├── openapi-client-facing.yaml        # OpenAPI 3.1 spec for Client-Facing API
│   └── openapi-clinical-integration.yaml # OpenAPI 3.1 spec for Clinical Integration API
├── IAMServer/                         # OAuth 2.0 / OIDC identity provider
│   ├── Package.swift
│   ├── Dockerfile
│   ├── agents.md
│   ├── Sources/IAMServer/
│   └── Tests/IAMServerTests/
├── ClientFacingServer/                # FHIR data reception + auth validation
│   ├── Package.swift
│   ├── Dockerfile
│   ├── agents.md
│   ├── Sources/ClientFacingServer/
│   └── Tests/ClientFacingServerTests/
├── ClinicalIntegrationServer/         # FHIR → GDT 2.1 conversion
│   ├── Package.swift
│   ├── Dockerfile
│   ├── agents.md
│   ├── Sources/{ClinicalIntegrationServer,GDTKit,FHIRToGDT}/
│   └── Tests/{ClinicalIntegrationServerTests,GDTKitTests,FHIRToGDTTests}/
├── Health Companion/                  # iOS patient-facing app
│   ├── agents.md
│   ├── Health Companion/
│   │   ├── Auth/                      # OAuth 2.0 + PKCE modules
│   │   ├── Sync/                      # FHIR sync with retry
│   │   ├── ECG/                       # ECG FHIR processing
│   │   ├── Onboarding/                # Setup + login flow
│   │   └── Views/                     # SwiftUI views
│   ├── Health Companion.xcodeproj/
│   ├── Health CompanionTests/
│   └── Health CompanionUITests/
```
