import Testing
import Vapor
import VaporTesting
import OpenAPIVapor
@testable import ClinicalIntegrationServer
@testable import FHIRToGDT
@testable import GDTKit
import Foundation

/// Clinical Integration Server test suite
/// Maps to: DP2 (Standards compliance), DR3 (Interoperability with PMS)
@Suite("Clinical Integration Server Tests")
struct ClinicalIntegrationServerTests {

    // MARK: - Test Configuration

    static func testConfigure(_ app: Application) throws {
        let tempDir = NSTemporaryDirectory() + "clinical-test-\(UUID().uuidString)"
        let gdtDir = tempDir + "/gdt"
        try FileManager.default.createDirectory(atPath: gdtDir, withIntermediateDirectories: true)

        let converterConfig = FHIRToGDTConfiguration(
            gdtVersion: "02.10",
            encoding: .latin1,
            senderID: "TEST_SENDER",
            receiverID: "TEST_PVS",
            outputDirectory: URL(fileURLWithPath: gdtDir),
            fileNamePrefix: "test"
        )

        let statusStore = StatusStore(directory: tempDir)
        app.storage[ConverterConfigKey.self] = converterConfig
        app.storage[StatusStoreKey.self] = statusStore

        let handler = ClinicalIntegrationHandler(
            converterConfig: converterConfig,
            statusStore: statusStore
        )
        let transport = VaporTransport(routesBuilder: app)
        try handler.registerHandlers(on: transport, serverURL: URL(string: "/api/v1")!)

        app.get("health") { _ in "OK" }
    }

    // MARK: - Health Check

    @Test("Health endpoint returns 200")
    func healthCheck() async throws {
        try await withApp(configure: Self.testConfigure) { app in
            try await app.testing().test(.GET, "health") { res async in
                #expect(res.status == .ok)
            }
        }
    }

    // MARK: - Status Endpoint

    @Suite("Patient Status Endpoint")
    struct StatusTests {

        @Test("GET /status for unknown patient returns 404")
        func unknownPatientStatus() async throws {
            try await withApp(configure: ClinicalIntegrationServerTests.testConfigure) { app in
                try await app.testing().test(.GET, "api/v1/status/unknown-patient-xyz") { res async throws in
                    #expect(res.status == .notFound)
                    let body = try res.content.decode(ErrorResponseBody.self)
                    #expect(body.error == "not_found")
                    #expect(body.message.contains("unknown-patient-xyz"))
                }
            }
        }
    }

    // MARK: - Status Store

    @Suite("Status Store")
    struct StatusStoreTests {

        @Test("Status store tracks transfers per patient")
        func trackTransfers() async throws {
            let dir = NSTemporaryDirectory() + "status-test-\(UUID().uuidString)"
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let store = StatusStore(directory: dir)

            // Initially no status
            let initial = await store.getStatus(patientId: "p1")
            #expect(initial == nil)

            // Record a transfer
            await store.recordTransfer(patientId: "p1")

            let status = await store.getStatus(patientId: "p1")
            #expect(status != nil)
            #expect(status?.patientId == "p1")
            #expect(status?.totalTransfers == 1)
        }

        @Test("Multiple transfers increment count")
        func multipleTransfers() async throws {
            let dir = NSTemporaryDirectory() + "status-test-\(UUID().uuidString)"
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let store = StatusStore(directory: dir)

            await store.recordTransfer(patientId: "p2")
            await store.recordTransfer(patientId: "p2")
            await store.recordTransfer(patientId: "p2")

            let status = await store.getStatus(patientId: "p2")
            #expect(status?.totalTransfers == 3)
        }

        @Test("Different patients are tracked independently")
        func independentPatients() async throws {
            let dir = NSTemporaryDirectory() + "status-test-\(UUID().uuidString)"
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let store = StatusStore(directory: dir)

            await store.recordTransfer(patientId: "patient-A")
            await store.recordTransfer(patientId: "patient-A")
            await store.recordTransfer(patientId: "patient-B")

            let statusA = await store.getStatus(patientId: "patient-A")
            let statusB = await store.getStatus(patientId: "patient-B")

            #expect(statusA?.totalTransfers == 2)
            #expect(statusB?.totalTransfers == 1)
        }
    }

    // MARK: - GDT Output Validation

    @Suite("GDT Output")
    struct GDTOutputTests {

        @Test("GDT 2.1 version is always used")
        func gdt21Only() {
            let config = FHIRToGDTConfiguration(
                gdtVersion: "02.10",
                encoding: .latin1,
                outputDirectory: URL(fileURLWithPath: "/tmp/test")
            )
            let converter = FHIRToGDTConverter(configuration: config)
            #expect(converter.configuration.gdtVersion == "02.10")
        }

        @Test("Latin1 encoding is default")
        func latin1Default() {
            let config = FHIRToGDTConfiguration(
                outputDirectory: URL(fileURLWithPath: "/tmp/test")
            )
            #expect(config.encoding == .latin1)
        }

        @Test("GDT document uses 9106/9103 field IDs for sender/receiver")
        func gdt21FieldIdentifiers() {
            var doc = GDTDocument(recordType: .newExaminationData)
            doc.senderID = "SENDER"
            doc.receiverID = "RECEIVER"
            doc.addField(.patientID, content: "12345")
            let formatted = doc.format()

            #expect(formatted.contains("9106"))
            #expect(formatted.contains("SENDER"))
            #expect(formatted.contains("9103"))
            #expect(formatted.contains("RECEIVER"))
        }
    }
}

// MARK: - Test DTOs

struct PatientStatusResponse: Content {
    let patientId: String
    let hasRecords: Bool
    let totalTransfers: Int
}

struct ErrorResponseBody: Content {
    let error: String
    let message: String
}
