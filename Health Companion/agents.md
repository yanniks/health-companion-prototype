# Health Companion iOS App — Agent Instructions

## Purpose

The Health Companion app is the **patient-facing client** of the PGHD integration artifact. It collects health data from the Apple Watch via HealthKit, displays ECG recordings, authenticates the patient via OAuth 2.0 + PKCE, and syncs FHIR Observations to the Client-Facing Integration Server.

**Spec references**: DP1 (simple integration), DP3 (device abstraction), DP4 (security/privacy), §5.2.2 (component model), §5.4.2 (patient-facing interfaces), §5.5.1 (security controls)

## Architecture

```
Health Companion/
├── Health_CompanionApp.swift            # SwiftUI @main App
├── HealthCompanionAppDelegate.swift     # Spezi Configuration: registers all modules
├── ContentView.swift                     # TabView: ECG, Sync Status, Settings
├── Auth/
│   ├── ServerAuthModule.swift            # Spezi Module: OAuth 2.0 + PKCE via ASWebAuthenticationSession
│   ├── KeychainStore.swift               # Keychain wrapper for secure token storage
│   ├── PKCEHelper.swift                  # S256 code_verifier + code_challenge generation
│   └── OIDCDiscovery.swift               # Fetches /.well-known/openid-configuration from IAM
├── Sync/
│   ├── ServerSyncModule.swift            # Spezi Module: FHIR Bundle sync with retry + idempotency
│   └── FHIRBundleBuilder.swift           # Builds FHIR transaction Bundles (isolated from @Observable)
├── ECG/
│   └── ECGFHIRProcessor.swift            # Converts HKElectrocardiogram to FHIR Observation
├── Models/
│   └── StorageKeys.swift                 # UserDefaults/AppStorage keys
├── Onboarding/
│   ├── OnboardingFlow.swift              # HealthKit perms → Server setup → Login
│   ├── HealthKitPermissions.swift        # HealthKit authorization request
│   ├── ServerSetupView.swift             # IAM URL, Client-Facing URL, Patient ID input
│   └── LoginView.swift                   # OAuth login button → ASWebAuthenticationSession
└── Views/
    ├── ChartView.swift                   # Line chart for ECG waveform display
    ├── SyncStatusView.swift              # Connection status, sync controls, server status
    ├── SettingsView.swift                # Account info, server config, logout
    └── Electrocardiogram/
        ├── ECGDetailsView.swift
        ├── ECGWaveformView.swift
        ├── ElectrocardiogramCellView.swift
        └── ElectrocardiogramDetailView.swift
```

## Spezi Module Dependencies

```
HealthCompanionAppDelegate
├── HealthKit (SpeziHealthKit)
├── FHIR (SpeziFHIR)
├── ServerAuthModule       ← custom
│   └── KeychainStore, PKCEHelper, OIDCDiscovery
├── ServerSyncModule       ← custom
│   ├── @Dependency(ServerAuthModule)
│   ├── @Dependency(FHIRStore)
│   └── FHIRBundleBuilder
└── Onboarding (SpeziOnboarding)
```

## Key Flows

### Authentication (OAuth 2.0 + PKCE)
1. User enters IAM URL, Client-Facing URL, Patient ID in `ServerSetupView`
2. `OIDCDiscovery` fetches `/.well-known/openid-configuration` from IAM
3. `PKCEHelper` generates S256 code_verifier + code_challenge
4. `ASWebAuthenticationSession` opens browser for `/authorize` endpoint
5. Callback with auth code → `POST /token` exchange → access + refresh tokens
6. Tokens stored in Keychain (`kSecAttrAccessibleAfterFirstUnlock`)
7. Automatic token refresh 30 seconds before expiry

### Data Sync (with retry)
1. `ServerSyncModule.syncNow()` collects unsynced FHIR observations from `FHIRStore`
2. `FHIRBundleBuilder` wraps them in a transaction Bundle
3. Idempotency key generated from sorted resource IDs (base64-encoded SHA)
4. POST to `/api/v1/observations` with Bearer token + Idempotency-Key header
5. On success: mark resource IDs as synced (persisted to `synced_resource_ids.txt`)
6. On failure: **exponential backoff retry** (3 attempts, 2s/4s/8s delays)
   - 401 → refresh token and retry
   - 429 → retriable (rate limited)
   - 4xx → non-retriable (abort)
   - 5xx / network error → retriable

### Consent Withdrawal
1. User taps "Sign Out" in `SettingsView`
2. `ServerAuthModule.logout()` revokes refresh token via IAM `/revoke` endpoint
3. All tokens cleared from Keychain
4. Server URL configuration cleared

## Dependencies

- **Stanford Spezi 1.10.0**: SpeziHealthKit 1.3.1, SpeziFHIR 0.9.0, SpeziOnboarding 2.0.4
- **iOS 17+** / **watchOS 10+** (via HealthKit)
- Xcode 16.2+

## Build

```bash
xcodebuild -scheme "Health Companion" -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```

## Important Rules

1. **Never import `ModelsR4` in files with `@Observable`** — `ModelsR4.Observation` collides with Swift's `@Observable` macro. FHIR operations are isolated in `FHIRBundleBuilder.swift`.
2. **Use `.fhirId` not `.fhirResourceId`** — the latter is `@_spi(Testing)` protected
3. **Keychain storage** — tokens are stored with `kSecAttrAccessibleAfterFirstUnlock`, not plain UserDefaults
4. **Retry is mandatory** — the spec requires the patient-facing client to "handle unavailability gracefully" with retry patterns
5. **Idempotency keys** — derived from resource IDs to ensure at-most-once delivery
6. **No PGHD in logs** — `OSLog` messages contain only UUIDs and error categories
7. **`FHIRURI` initialization** — use `FHIRURI(stringLiteral: ...)` for interpolated strings, type annotation for plain literals
8. **`BundleEntry` parameter order** — `request` must precede `resource` in the initializer
