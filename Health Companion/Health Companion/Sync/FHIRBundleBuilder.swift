//
//  FHIRBundleBuilder.swift
//  Health Companion
//
//  Builds FHIR R4 transaction Bundles from SpeziFHIR resources.
//  Separated to avoid namespace collision between ModelsR4.Observation and @Observable.
//
//  Maps to: DP1 (FHIR as canonical data format)
//
//  Note: Device-specific code normalization (DR4) is performed server-side
//  in the Client-Facing Integration component (FHIRNormalizer), keeping
//  this client as a thin pass-through.
//

import Foundation
import ModelsR4
import SpeziFHIR

/// Builds FHIR R4 Bundles from SpeziFHIR resources for server submission.
///
/// Each resource is wrapped as a `POST Observation` entry inside a FHIR
/// transaction Bundle. Device-specific coding normalization (DR4) is
/// handled by the Client-Facing Integration server, so raw HealthKit
/// codes are forwarded as-is.
enum FHIRBundleBuilder {

    /// Creates a FHIR transaction Bundle from the given FHIR resources.
    ///
    /// Each resource is wrapped as a `POST Observation` entry. Resources that
    /// cannot be decoded as FHIR Observations are skipped.
    static func buildBundle(from resources: [FHIRResource]) -> ModelsR4.Bundle {
        let entries = resources.compactMap { resource -> BundleEntry? in
            guard let jsonData = resource.jsonDescription.data(using: .utf8) else { return nil }
            let decoder = JSONDecoder()

            guard let resourceId = resource.fhirId else { return nil }

            if let observation = try? decoder.decode(ModelsR4.Observation.self, from: jsonData) {
                let fullUrl = FHIRPrimitive(FHIRURI(stringLiteral: "urn:uuid:\(resourceId)"))
                let requestURL: FHIRPrimitive<FHIRURI> = "Observation"
                return BundleEntry(
                    fullUrl: fullUrl,
                    request: BundleEntryRequest(
                        method: FHIRPrimitive(.POST),
                        url: requestURL
                    ),
                    resource: .observation(observation)
                )
            }
            return nil
        }

        return ModelsR4.Bundle(
            entry: entries.isEmpty ? nil : entries,
            type: FHIRPrimitive(.transaction)
        )
    }
}
