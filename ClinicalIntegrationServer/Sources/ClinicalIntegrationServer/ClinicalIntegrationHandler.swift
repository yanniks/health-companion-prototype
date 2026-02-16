import Foundation
import OpenAPIRuntime
import FHIRToGDT
import GDTKit
import ModelsR4

/// Implements the OpenAPI-generated APIProtocol for clinical integration
/// Converts FHIR observations to GDT 2.1 and writes to PMS exchange directory
/// (DR2: System-independent interface, DP2: PMS-agnostic interoperability)
struct ClinicalIntegrationHandler: APIProtocol {
    let converterConfig: FHIRToGDTConfiguration
    let statusStore: StatusStore

    // MARK: - POST /process

    func processObservations(
        _ input: Operations.processObservations.Input
    ) async throws -> Operations.processObservations.Output {
        let request: Components.Schemas.ProcessingRequest
        switch input.body {
        case .json(let body):
            request = body
        }

        let converter = FHIRToGDTConverter(configuration: converterConfig)
        var gdtResults: [Components.Schemas.GDTResult] = []

        for normalizedObs in request.observations {
            do {
                // Convert the normalized observation JSON to a FHIR Observation
                let observation = try buildFHIRObservation(
                    from: normalizedObs,
                    patientId: request.patientId,
                    firstName: request.patientFirstName,
                    lastName: request.patientLastName,
                    dateOfBirth: request.patientDateOfBirth
                )

                // Convert to GDT and write to file
                let result = try converter.convertAndWrite(observation)

                gdtResults.append(Components.Schemas.GDTResult(
                    gdtFileName: result.filePath?.lastPathComponent,
                    warnings: result.warnings.isEmpty ? nil : result.warnings,
                    error: nil
                ))
            } catch {
                gdtResults.append(Components.Schemas.GDTResult(
                    gdtFileName: nil,
                    warnings: nil,
                    error: error.localizedDescription
                ))
            }
        }

        // Update status tracking
        await statusStore.recordTransfer(patientId: request.patientId)

        let successCount = gdtResults.filter { $0.error == nil }.count
        let failedCount = gdtResults.count - successCount
        let response = Components.Schemas.ProcessingResult(
            status: failedCount == 0 ? .success : .partial,
            totalProcessed: gdtResults.count,
            successful: successCount,
            failed: failedCount,
            results: gdtResults
        )

        return .ok(.init(body: .json(response)))
    }

    // MARK: - GET /status/{patientId}

    func getPatientStatus(
        _ input: Operations.getPatientStatus.Input
    ) async throws -> Operations.getPatientStatus.Output {
        let patientId = input.path.patientId

        if let status = await statusStore.getStatus(patientId: patientId) {
            let formatter = ISO8601DateFormatter()
            let timestamp = formatter.date(from: status.lastTransferTimestamp)
            return .ok(.init(body: .json(Components.Schemas.PatientStatus(
                patientId: status.patientId,
                hasRecords: true,
                lastTransferTimestamp: timestamp,
                lastTransferStatus: .success,
                totalTransfers: status.totalTransfers
            ))))
        } else {
            return .notFound(.init(body: .json(Components.Schemas.ErrorResponse(
                error: "not_found",
                message: "No transfer records found for patient \(patientId)"
            ))))
        }
    }

    // MARK: - FHIR Observation Builder

    /// Builds a FHIR R4 Observation from normalized observation data + patient context
    private func buildFHIRObservation(
        from normalized: Components.Schemas.NormalizedObservation,
        patientId: String,
        firstName: String?,
        lastName: String?,
        dateOfBirth: String?
    ) throws -> Observation {
        // Re-encode the normalized observation to JSON, then decode as FHIR Observation
        let encoder = JSONEncoder()
        let data = try encoder.encode(normalized)
        let decoder = JSONDecoder()
        let observation = try decoder.decode(Observation.self, from: data)

        // If subject reference is missing, set it on the existing observation
        // (preserves all properties including component, category, identifier, etc.)
        if observation.subject == nil {
            var displayName: String?
            if let last = lastName {
                if let first = firstName {
                    displayName = "\(last), \(first)"
                } else {
                    displayName = last
                }
            }

            observation.subject = Reference(
                display: displayName.map { FHIRPrimitive(FHIRString($0)) },
                reference: FHIRPrimitive(FHIRString("Patient/\(patientId)"))
            )
        }

        return observation
    }
}
