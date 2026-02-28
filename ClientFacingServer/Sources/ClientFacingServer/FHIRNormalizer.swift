import Foundation
import ModelsR4

/// Normalizes FHIR Observations by replacing device-specific (HealthKit) coding
/// systems with standard LOINC / MDC / SNOMED equivalents.
///
/// This implements **DR4** (device-specific data abstraction) at the
/// client-facing integration layer so that downstream components (clinical
/// integration, PMS) never see vendor-specific code systems.
enum FHIRNormalizer: Sendable {

    // MARK: - Constants

    /// System URL emitted by SpeziFHIR for HealthKit-specific codes.
    private static let healthKitSystem = "http://developer.apple.com/documentation/healthkit"

    /// Maps HealthKit-specific codes to standard coding system equivalents.
    private static let codeReplacements: [String: (system: String, code: String, display: String)] = [
        "HKElectrocardiogram": (
            "http://loinc.org", "11524-6", "ECG study"
        ),
        "HKElectrocardiogram.Classification": (
            "http://loinc.org", "18844-5", "ECG impression"
        ),
        "HKElectrocardiogram.NumberOfVoltageMeasurements": (
            "urn:oid:2.16.840.1.113883.6.24", "67925", "Number of voltage measurements"
        ),
        "HKElectrocardiogram.SamplingFrequency": (
            "urn:oid:2.16.840.1.113883.6.24", "68220", "Sampling frequency"
        ),
        "HKElectrocardiogram.SymptomsStatus": (
            "http://snomed.info/sct", "418138009", "Patient symptom finding"
        ),
    ]

    /// Maps HealthKit ECG classification raw enum values to human-readable labels.
    private static let classificationLabels: [String: String] = [
        "sinusRhythm": "Sinus Rhythm",
        "atrialFibrillation": "Atrial Fibrillation",
        "inconclusiveHighHeartRate": "Inconclusive – High Heart Rate",
        "inconclusiveLowHeartRate": "Inconclusive – Low Heart Rate",
        "inconclusivePoorReading": "Inconclusive – Poor Reading",
        "inconclusiveOther": "Inconclusive",
        "unrecognized": "Unrecognized",
        "notSet": "Not Set",
    ]

    // MARK: - Public API

    /// Normalizes a single FHIR Observation in-place, replacing all
    /// HealthKit-specific codings with standard equivalents.
    static func normalize(_ observation: Observation) {
        // 1. Main code
        normalizeCodeableConcept(observation.code)

        // 2. Component codes + classification labels
        if let components = observation.component {
            for component in components {
                let isClassification =
                    component.code.coding?.contains {
                        $0.code?.value?.string == "HKElectrocardiogram.Classification"
                    } ?? false

                normalizeCodeableConcept(component.code)

                // Map raw classification enum values to readable labels
                if isClassification, case .string(let str) = component.value,
                    let raw = str.value?.string,
                    let label = classificationLabels[raw]
                {
                    component.value = .string(FHIRPrimitive(FHIRString(label)))
                }
            }
        }

        // 3. Category codes
        if let categories = observation.category {
            for category in categories {
                normalizeCodeableConcept(category)
            }
        }
    }

    /// Normalizes raw JSON observation data, returning the normalized JSON.
    ///
    /// Decodes the JSON as a FHIR Observation, applies normalization, then
    /// re-encodes. Returns `nil` if the data cannot be decoded as an Observation.
    static func normalizeJSON(_ data: Data) -> Data? {
        let decoder = JSONDecoder()
        guard let observation = try? decoder.decode(Observation.self, from: data) else {
            return nil
        }
        normalize(observation)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(observation)
    }

    // MARK: - Private Helpers

    /// Replaces HealthKit-specific codings inside a ``CodeableConcept`` with
    /// standard LOINC / MDC equivalents, preserving any non-HealthKit codings.
    private static func normalizeCodeableConcept(_ cc: CodeableConcept) {
        guard let codings = cc.coding else { return }
        let hasNonHK = codings.contains {
            $0.system?.value?.url.absoluteString != healthKitSystem
        }

        var normalized: [Coding] = []
        for coding in codings {
            let sys = coding.system?.value?.url.absoluteString
            guard sys == healthKitSystem else {
                normalized.append(coding)
                continue
            }
            let hkCode = coding.code?.value?.string ?? ""
            if let replacement = codeReplacements[hkCode] {
                if !hasNonHK
                    || !normalized.contains(where: {
                        $0.code?.value?.string == replacement.code
                    })
                {
                    normalized.insert(
                        Coding(
                            code: FHIRPrimitive(FHIRString(replacement.code)),
                            display: FHIRPrimitive(FHIRString(replacement.display)),
                            system: FHIRPrimitive(FHIRURI(stringLiteral: replacement.system))
                        ),
                        at: 0
                    )
                }
            }
            // Drop the original HealthKit coding
        }
        cc.coding = normalized.isEmpty ? nil : normalized
    }
}
