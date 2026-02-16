import Foundation
import ModelsR4
import OpenAPIRuntime

/// Implements the OpenAPI-generated APIProtocol for client-facing integration
/// Receives FHIR observations from iOS client, validates auth, forwards to clinical integration
/// (DP3: Layered architecture, DR1: No manual data entry tasks, DR4: Device abstraction)
struct ClientFacingHandler: APIProtocol {
    let jwksProvider: JWKSProvider
    let idempotencyStore: IdempotencyStore
    let auditLogger: AuditLogger
    let clinicalBaseURL: String
    let iamBaseURL: String

    // MARK: - GET /metadata

    func getMetadata(
        _ input: Operations.getMetadata.Input
    ) async throws -> Operations.getMetadata.Output {
        let metadata = Components.Schemas.ServerMetadata(
            serverVersion: "1.0.0",
            iamDiscoveryUrl: "\(iamBaseURL)/.well-known/openid-configuration",
            supportedResourceTypes: ["Observation"]
        )
        return .ok(.init(body: .json(metadata)))
    }

    // MARK: - POST /observations

    func submitObservations(
        _ input: Operations.submitObservations.Input
    ) async throws -> Operations.submitObservations.Output {
        // Auth is validated by AuthMiddleware; subject is in TaskLocal
        guard let patientId = AuthContext.currentSubject else {
            return .unauthorized(.init(body: .json(
                .init(error: "authentication_error", message: "Not authenticated")
            )))
        }

        let idempotencyKey = input.headers.Idempotency_hyphen_Key

        // Check idempotency — return cached result if already processed
        if let cached = await idempotencyStore.check(key: idempotencyKey, clientId: patientId) {
            if let data = cached.data(using: .utf8),
               let result = try? JSONDecoder.fhirDecoder.decode(Components.Schemas.SubmissionResult.self, from: data)
            {
                return .ok(.init(body: .json(result)))
            }
        }

        // Extract bundle from body
        let bundle: Components.Schemas.FHIRBundle
        switch input.body {
        case .application_fhir_plus_json(let b):
            bundle = b
        case .json(let b):
            bundle = b
        }

        guard let entries = bundle.entry, !entries.isEmpty else {
            return .badRequest(.init(body: .json(
                .init(error: "validation_error", message: "Bundle contains no entries")
            )))
        }

        // Patient demographics are embedded in the JWT claims by the IAM server,
        // so no additional REST call to IAM is needed (DP1: Simple integration).
        let patientFirstName = AuthContext.currentFirstName
        let patientLastName = AuthContext.currentLastName
        let patientDateOfBirth = AuthContext.currentDateOfBirth

        // Build clinical integration request payload
        // Decode each entry as a FHIR Observation, normalize HealthKit-specific
        // codes to standard systems (DR4), then re-encode for forwarding.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var observationObjects: [[String: Any]] = []
        for entry in entries {
            if let resource = entry.resource,
               let rawData = try? encoder.encode(resource)
            {
                // Attempt FHIR decode → normalize → re-encode
                let normalizedData = FHIRNormalizer.normalizeJSON(rawData) ?? rawData
                if let dict = try? JSONSerialization.jsonObject(with: normalizedData) as? [String: Any] {
                    observationObjects.append(dict)
                }
            }
        }

        let requestPayload: [String: Any] = [
            "patientId": patientId,
            "patientFirstName": patientFirstName as Any,
            "patientLastName": patientLastName as Any,
            "patientDateOfBirth": patientDateOfBirth as Any,
            "observations": observationObjects
        ]

        // Forward to clinical integration server
        let clinicalURL = URL(string: "\(clinicalBaseURL)/api/v1/process")!
        var clinicalRequest = URLRequest(url: clinicalURL)
        clinicalRequest.httpMethod = "POST"
        clinicalRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        clinicalRequest.httpBody = try JSONSerialization.data(withJSONObject: requestPayload)

        let status: Components.Schemas.SubmissionResult.statusPayload
        var totalProcessed = 0
        var successful = 0
        var failed = 0
        var observationResults: [Components.Schemas.ObservationResult] = []

        do {
            let (responseData, httpResponse) = try await URLSession.shared.data(for: clinicalRequest)
            if let httpResp = httpResponse as? HTTPURLResponse, httpResp.statusCode == 200 || httpResp.statusCode == 201,
               let clinicalResult = try? JSONDecoder().decode(ClinicalProcessingResponse.self, from: responseData)
            {
                totalProcessed = clinicalResult.totalProcessed
                successful = clinicalResult.successful
                failed = clinicalResult.failed
                status = failed == 0 ? .success : (successful > 0 ? .partial : .error)

                for result in clinicalResult.results ?? [] {
                    observationResults.append(Components.Schemas.ObservationResult(
                        observationId: nil,
                        status: result.error == nil ? .success : .error,
                        error: result.error,
                        warnings: result.warnings
                    ))
                }
            } else {
                status = .error
                totalProcessed = entries.count
                failed = entries.count
            }
        } catch {
            status = .error
            totalProcessed = entries.count
            failed = entries.count
        }

        let submissionResult = Components.Schemas.SubmissionResult(
            status: status,
            totalProcessed: totalProcessed,
            successful: successful,
            failed: failed,
            idempotencyKey: idempotencyKey,
            results: observationResults,
            processedAt: Date()
        )

        // Audit log — record submission with payload hash, no PGHD (DP4, §5.5.1)
        let payloadData = clinicalRequest.httpBody ?? Data()
        await auditLogger.logSubmission(
            idempotencyKey: idempotencyKey,
            patientId: patientId,
            payloadData: payloadData,
            outcome: "\(status)",
            observationCount: totalProcessed
        )

        // Cache result for idempotency
        let resultEncoder = JSONEncoder()
        resultEncoder.dateEncodingStrategy = .iso8601
        if let resultData = try? resultEncoder.encode(submissionResult),
           let resultJSON = String(data: resultData, encoding: .utf8)
        {
            await idempotencyStore.store(key: idempotencyKey, clientId: patientId, responseJSON: resultJSON)
        }

        return .created(.init(body: .json(submissionResult)))
    }

    // MARK: - GET /status

    func getTransferStatus(
        _ input: Operations.getTransferStatus.Input
    ) async throws -> Operations.getTransferStatus.Output {
        guard let patientId = AuthContext.currentSubject else {
            return .unauthorized(.init(body: .json(
                .init(error: "authentication_error", message: "Not authenticated")
            )))
        }

        // Fetch status from clinical integration server
        await auditLogger.logStatusQuery(patientId: patientId)
        let statusURL = URL(string: "\(clinicalBaseURL)/api/v1/status/\(patientId)")!
        do {
            let (data, response) = try await URLSession.shared.data(from: statusURL)
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200,
               let clinicalStatus = try? JSONDecoder().decode(ClinicalPatientStatus.self, from: data)
            {
                let lastTransfer: Date?
                if let timestamp = clinicalStatus.lastTransferTimestamp {
                    let formatter = ISO8601DateFormatter()
                    lastTransfer = formatter.date(from: timestamp)
                } else {
                    lastTransfer = nil
                }

                let transferStatus = Components.Schemas.TransferStatus(
                    hasSuccessfulTransfer: clinicalStatus.totalTransfers > 0,
                    lastSuccessfulTransfer: lastTransfer,
                    lastAttempt: lastTransfer,
                    lastError: nil,
                    pendingCount: 0
                )
                return .ok(.init(body: .json(transferStatus)))
            }
        } catch {
            // Clinical server not reachable — return empty status
        }

        // No records yet or clinical server unavailable
        let transferStatus = Components.Schemas.TransferStatus(
            hasSuccessfulTransfer: false,
            lastSuccessfulTransfer: nil,
            lastAttempt: nil,
            lastError: nil,
            pendingCount: 0
        )
        return .ok(.init(body: .json(transferStatus)))
    }
}

// MARK: - Auth Context (task-local for passing subject from middleware to handler)

enum AuthContext {
    @TaskLocal static var currentSubject: String?
    @TaskLocal static var currentScope: String?
    @TaskLocal static var currentFirstName: String?
    @TaskLocal static var currentLastName: String?
    @TaskLocal static var currentDateOfBirth: String?
}

// MARK: - JSON Decoder with ISO8601 date support

extension JSONDecoder {
    static let fhirDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

// MARK: - Clinical Integration DTOs

struct ClinicalProcessingResponse: Codable, Sendable {
    let status: String
    let totalProcessed: Int
    let successful: Int
    let failed: Int
    let results: [ClinicalGDTResult]?
}

struct ClinicalGDTResult: Codable, Sendable {
    let gdtFileName: String?
    let warnings: [String]?
    let error: String?
}

struct ClinicalPatientStatus: Codable, Sendable {
    let patientId: String
    let lastTransferTimestamp: String?
    let totalTransfers: Int
}
