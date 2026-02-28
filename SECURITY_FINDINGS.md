# Security Findings

> **Scope:** This report covers findings identified by automated security review of the codebase as of February 2026. It is **not exhaustive** — additional vulnerabilities may exist that were not identified. The findings listed here represent high-confidence, directly exploitable issues only.

---

## Finding 1: Authorization Code Theft via Unvalidated `redirect_uri`

| | |
|---|---|
| **Severity** | High |
| **Category** | OAuth 2.0 — Authorization Code Theft |
| **Location** | `IAMServer/Sources/IAMServer/routes.swift:129` |

### Description

The IAM authorization server validates the `client_id` but performs no validation on the `redirect_uri`. Any arbitrary URI is accepted, stored in the authorization code record, and the authorization code is redirected to it after successful user authentication. The token endpoint (`routes.swift:158`) only performs a consistency check (the URI sent at token time must match what was stored) — it never validates against an allowlist of registered values. RFC 6749 §10.6 explicitly requires the authorization server to validate `redirect_uri` against pre-registered URIs.

```swift
// routes.swift:129-135 — redirects the auth code to an attacker-controlled URI
var redirectComponents = URLComponents(string: redirectURI)!
redirectComponents.queryItems = [
    URLQueryItem(name: "code", value: code),
    URLQueryItem(name: "state", value: state),
]
return req.redirect(to: redirectComponents.string!)

// routes.swift:158-159 — consistency check only, NOT an allowlist check
guard authCode.redirectURI == redirectURI else {
    throw Abort(.badRequest, reason: "Redirect URI mismatch")
}
```

### Exploit Scenario

An attacker crafts a malicious authorization URL with `redirect_uri=https://evil.example.com/callback` and sends it to a patient via phishing. The patient authenticates on the legitimate IAM login page. The server issues a real authorization code and redirects it to the attacker's URI. Because the attacker **initiated** the flow, they already control the PKCE `code_verifier` — PKCE provides no protection in this scenario. The attacker passes the consistency check at the token endpoint and the PKCE verification, receiving a valid access and refresh token pair that fully impersonates the patient.

### Recommendation

Register a per-client `redirect_uri` allowlist (e.g., alongside `knownClientId` in `Models.swift`, add `let knownRedirectURI = "healthcompanion://oauth/callback"`). Validate the submitted `redirect_uri` against this allowlist in both GET and POST `/authorize`, and reject unregistered URIs with `400 Bad Request`.

---

## Finding 2: Unauthenticated Patient Administration Endpoints

| | |
|---|---|
| **Severity** | High |
| **Category** | Missing Access Control |
| **Location** | `IAMServer/Sources/IAMServer/routes.swift:250` |

### Description

The IAM server exposes four `/patients` CRUD endpoints with no authentication or authorization middleware. All four — `POST /patients` (register), `DELETE /patients/:patientId` (delete + revoke tokens), `GET /patients` (list all), and `GET /patients/:patientId` (get one) — are registered with zero middleware. Port 8081 is published to all host interfaces in `docker-compose.yml` (`"8081:8081"`), making these endpoints reachable by any network-adjacent host.

```swift
// routes.swift:250-297 — no auth middleware, all routes are fully public
let patients = app.grouped("patients")
patients.post { ... }                     // registers new patient — no auth
patients.delete(":patientId") { ... }     // deletes patient + revokes tokens — no auth
patients.get { req -> [PatientRecord] in  // dumps ALL patient PII — no auth
    await req.application.patientStore.listAll()
}
patients.get(":patientId") { ... }        // returns name + date of birth — no auth
```

### Exploit Scenario

An attacker with network access to port 8081 sends `GET http://<host>:8081/patients` to enumerate all registered patients including their full names and dates of birth (which serve as login credentials). With these credentials, the attacker can immediately authenticate as any patient via the normal OAuth login flow. Alternatively, `POST /patients` with a known date of birth creates a new account the attacker controls, or `DELETE /patients/:id` silently revokes a legitimate patient's access and tokens.

### Recommendation

Protect all `/patients` management routes behind an admin authentication mechanism — at minimum a shared secret verified by a middleware layer. The `GET /patients` list endpoint is particularly sensitive as it constitutes a full PII enumeration attack surface and should either be removed or restricted to an internal-only network interface. Consider binding the management API to a separate, non-externally-published port.

---

## Finding 3: Unauthenticated Clinical Data Injection Endpoint

| | |
|---|---|
| **Severity** | High |
| **Category** | Missing Access Control |
| **Location** | `ClinicalIntegrationServer/Sources/ClinicalIntegrationServer/configure.swift:56` |

### Description

The Clinical Integration Server registers its entire API handler with no authentication, no token validation, no IP allowlist, and no shared secret. The `POST /api/v1/process` endpoint — which accepts FHIR observations and writes GDT files directly into the PMS exchange directory — is completely open to the network. Port 8083 is published externally in `docker-compose.yml` (`"8083:8083"`), which bypasses the ClientFacingServer's entire security layer (JWT validation, rate limiting, idempotency, audit logging).

```swift
// configure.swift:56-61 — handler registered with zero middleware
// Compare with ClientFacingServer configure.swift which passes [authMiddleware, rateLimitMiddleware]
try handler.registerHandlers(on: transport, serverURL: URL(string: "/api/v1")!)

// ClinicalIntegrationHandler.swift:40 — GDT file written unconditionally on any valid request
converter.convertAndWrite(observation)
```

### Exploit Scenario

An external attacker POSTs a crafted request directly to `http://<host>:8083/api/v1/process` with a real patient ID and fabricated ECG or health observation data. The server converts this to a GDT file and writes it into the PMS exchange directory. The PMS ingests this file as a legitimate clinical observation. Attacker-fabricated medical data enters the clinical record without any form of authentication, entirely bypassing all access controls in the system.

### Recommendation

Either (1) remove port 8083 from the docker-compose `ports` binding so the service is only reachable within the Docker-internal network (use `expose` instead of `ports`), or (2) add a shared-secret or mTLS authentication middleware to the ClinicalIntegrationServer before `registerHandlers`, matching the security model of the ClientFacingServer. The intended architecture is for this service to be internal-only — the deployment configuration should enforce that boundary.

---

## Finding 4: Medical PHI Transmitted in Cleartext HTTP by Default

| | |
|---|---|
| **Severity** | High |
| **Category** | Cleartext Transmission of Sensitive Data |
| **Location** | `docker-compose.yml:29`, `ClientFacingServer/Sources/ClientFacingServer/configure.swift:33` |

### Description

TLS across all three server components is opt-in only, gated behind `TLS_CERT_PATH`/`TLS_KEY_PATH` environment variables that are not set in the provided docker-compose deployment file. All services therefore start with plain HTTP. The IAM base URL is hardcoded as a bare LAN IP: `IAM_BASE_URL: "http://10.23.162.196:8081"`. No reverse proxy or TLS terminator is present in the repository. As a result:

- JWT bearer tokens are transmitted in cleartext between the iOS app and the ClientFacingServer
- JWKS public keys (used to validate all token signatures) are fetched over plaintext HTTP — a MITM attacker who replaces these keys can forge arbitrary JWTs for any patient
- FHIR patient health observations (PHI including ECG data) are transmitted in cleartext between ClientFacingServer and ClinicalIntegrationServer

The hardcoded LAN IP (`10.23.162.196`) indicates this is an actual deployment configuration, not merely a development placeholder.

### Exploit Scenario

An attacker on the same network segment passively captures all HTTP traffic to/from port 8082 and collects bearer tokens directly from `Authorization: Bearer <token>` headers for immediate replay. More critically, by intercepting the JWKS fetch from `http://10.23.162.196:8081/jwks`, the attacker can substitute their own public key, enabling them to forge JWTs for any patient ID and gain access to any patient's account.

### Recommendation

Enable TLS for all three services in the docker-compose deployment by setting `TLS_CERT_PATH` and `TLS_KEY_PATH`, or place a reverse proxy (nginx, Caddy) with TLS termination in front of all externally-facing services. Update `IAM_BASE_URL` and `CLINICAL_BASE_URL` in docker-compose to `https://` schemes. The JWKS fetch in particular must use TLS to protect the integrity of the signing key material.

---

## Disclaimer

This list represents findings identified during a single automated security review pass. **It is not a comprehensive security audit.** Additional vulnerabilities — including those in areas not covered by this review, in third-party dependencies, or arising from deployment-specific configuration — may exist. This codebase is an exemplary research prototype and has not undergone the security hardening required for clinical production use.
