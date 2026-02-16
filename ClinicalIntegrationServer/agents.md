# Clinical Integration Server — Agent Instructions

## Purpose

The Clinical Integration Server receives normalized FHIR Observations from the Client-Facing Server, converts them to GDT 2.1 format, and writes `.gdt` files to a filesystem exchange directory for pickup by the PMS (Practice Management System).

**Spec references**: DP2 (PMS-agnostic interoperability), DP1 (simple integration), §5.2.2 (component model), §5.4.4 (clinical system interfaces), §5.5.1 (security controls)

## Architecture

```
Sources/
├── ClinicalIntegrationServer/
│   ├── ClinicalIntegrationServerMain.swift   # @main entry point
│   ├── configure.swift                        # Vapor config, GDT settings, TLS
│   ├── openapi.yaml                           # OpenAPI 3.1 spec
│   ├── openapi-generator-config.yaml          # swift-openapi-generator config
│   ├── ClinicalIntegrationHandler.swift       # APIProtocol impl: processObservations, getPatientStatus
│   └── StatusStore.swift                      # Actor: tracks per-patient transfer history
├── GDTKit/                                    # GDT format library (standalone, no external deps)
│   ├── GDTKit.swift                           # Public API re-exports
│   ├── GDTDocument.swift                      # GDT document builder (header, body, record length)
│   ├── GDTLine.swift                          # Individual GDT line formatting (LLLFFFFContent\r\n)
│   ├── GDTFieldIdentifier.swift               # Enum of all GDT field codes (8000, 3000, 6200, etc.)
│   ├── GDTRecordType.swift                    # GDT record types (6310, 6302, etc.)
│   └── GDTEncoding.swift                      # Character encoding (Latin-1, CP437, UTF-8)
└── FHIRToGDT/                                 # FHIR R4 → GDT 2.1 converter
    ├── FHIRToGDT.swift                        # Public API + configuration struct
    └── FHIRToGDTConverter.swift               # Main converter: Observation → GDT document → file

Tests/
├── ClinicalIntegrationServerTests/            # 4 suites: Health, Status, StatusStore, GDT Output
├── GDTKitTests/                               # 5 suites: Document, Encoding, FieldIdentifier, Line, RecordType
└── FHIRToGDTTests/                            # 4 suites: Converter, Configuration, PatientRef, ECG
```

## API (OpenAPI 3.1 — generated types)

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| GET | `/health` | No | Health check (plain Vapor route) |
| POST | `/api/v1/process` | No* | Process FHIR Observations → GDT files |
| GET | `/api/v1/status/{patientId}` | No* | Get transfer history for a patient |

*This server is internal (not internet-facing). In production, network-level access control applies.

Returns **404** for unknown patients on the status endpoint.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLINICAL_PORT` | `8083` | Server listen port |
| `CLINICAL_STORAGE_DIR` | `./data` | Directory for status tracking files |
| `GDT_OUTPUT_PATH` | `./gdt_exchange` | Directory where `.gdt` files are written |
| `GDT_SENDER_ID` | `HEALTH_COMPANION` | Sender ID in GDT headers (FK 9106) |
| `GDT_RECEIVER_ID` | `PVS` | Receiver ID in GDT headers (FK 9103) |
| `TLS_CERT_PATH` | — | PEM certificate file for TLS (optional) |
| `TLS_KEY_PATH` | — | PEM private key file for TLS (optional) |

## GDT 2.1 Format

The implementation uses **GDT version 02.10** (GDT 2.1) with Latin-1 encoding.

### Line Format
```
LLLFFFFContent\r\n
```
- `LLL`: 3-digit line length (self-inclusive)
- `FFFF`: 4-digit field identifier
- Content: Variable length
- Terminator: CR+LF

### Key Field Mappings (FHIR → GDT)

| FHIR Field | GDT FK | Description |
|------------|--------|-------------|
| patient reference → id | 3000 | Patient ID |
| patient → name.family | 3101 | Last name |
| patient → name.given | 3102 | First name |
| patient → birthDate | 3103 | Birth date (DDMMYYYY) |
| effectiveDateTime → date | 6200 | Examination date |
| effectiveDateTime → time | 6201 | Examination time |
| code.coding.display | 8410/8411 | Test name |
| valueQuantity.value | 8420 | Result value |
| valueQuantity.unit | 8421 | Unit |

### ECG-Specific Fields

| FHIR Component LOINC | GDT FK | Description |
|----------------------|--------|-------------|
| 8867-4 | 8501 | Heart rate (bpm) |
| 8626-4 | 8502 | P duration (ms) |
| 8625-6 | 8503 | PR interval (ms) |
| 8633-0 | 8504 | QRS duration (ms) |
| 8634-8 | 8505 | QT interval (ms) |
| 8636-3 | 8506 | QTc interval (ms) |

## PMS Integration Pattern

The server writes `.gdt` files to the configured `GDT_OUTPUT_PATH`. The PMS is expected to **poll this directory** for new files — this is the standard GDT integration pattern for German PMS systems (e.g., CGM MEDISTAR, TURBOMED).

File naming: `obs_<timestamp>_<UUID>.gdt`

## Testing

```bash
swift test  # Runs 44 tests in 13 suites
```

Suites span three test targets: `GDTKitTests` (5), `FHIRToGDTTests` (4), `ClinicalIntegrationServerTests` (4)

## Important Rules

1. **GDT version is 02.10** — not 03.50. Sender FK is 9106, receiver FK is 9103 (2.1 identifiers)
2. **Latin-1 encoding** — GDT files are encoded as ISO-8859-1, not UTF-8
3. **GDTKit has no external dependencies** — it is a pure Swift library
4. **FHIRToGDT depends on ModelsR4** — FHIR R4 types for Observation parsing
5. **This server does no device-specific processing** — DP3 requires that device abstraction happens upstream
6. **No medical interpretation** — the server converts and writes data; clinical evaluation is the physician's responsibility
