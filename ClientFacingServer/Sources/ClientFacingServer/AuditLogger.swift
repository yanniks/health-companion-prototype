import Crypto
import Foundation

/// Append-only audit logger for the client-facing integration component (DP4).
///
/// Records timestamps, message IDs, and payload hashes without storing
/// any personal health data. Supports tamper-evident traceability as
/// required by the reference architecture specification (§5.5.1).
///
/// Each audit entry is written as a single JSON line to an append-only log file.
/// The log never contains PGHD — only SHA-256 hashes of payloads are recorded.
actor AuditLogger {
    private let filePath: String
    private let fileHandle: FileHandle?

    init(directory: String) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)

        self.filePath = "\(directory)/audit.log"
        if !fileManager.fileExists(atPath: filePath) {
            fileManager.createFile(atPath: filePath, contents: nil)
        }
        self.fileHandle = FileHandle(forWritingAtPath: filePath)
        fileHandle?.seekToEndOfFile()
    }

    deinit {
        try? fileHandle?.close()
    }

    /// Logs a data submission event.
    ///
    /// - Parameters:
    ///   - idempotencyKey: The client-provided idempotency key (message ID)
    ///   - patientId: Pseudonymous patient reference (UUID, not a real name)
    ///   - payloadData: Raw request body — only its SHA-256 hash is stored
    ///   - outcome: Processing result (e.g., "success", "partial", "error")
    ///   - observationCount: Number of observations in the bundle
    func logSubmission(
        idempotencyKey: String,
        patientId: String,
        payloadData: Data,
        outcome: String,
        observationCount: Int
    ) {
        let payloadHash = SHA256.hash(data: payloadData)
            .compactMap { String(format: "%02x", $0) }
            .joined()

        let entry = AuditEntry(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            event: "observation_submission",
            idempotencyKey: idempotencyKey,
            patientRef: patientId,
            payloadHashSHA256: payloadHash,
            outcome: outcome,
            observationCount: observationCount
        )

        writeEntry(entry)
    }

    /// Logs a status query event.
    func logStatusQuery(patientId: String) {
        let entry = AuditEntry(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            event: "status_query",
            idempotencyKey: nil,
            patientRef: patientId,
            payloadHashSHA256: nil,
            outcome: "ok",
            observationCount: nil
        )

        writeEntry(entry)
    }

    /// Logs an authentication failure event.
    func logAuthFailure(reason: String) {
        let entry = AuditEntry(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            event: "auth_failure",
            idempotencyKey: nil,
            patientRef: nil,
            payloadHashSHA256: nil,
            outcome: reason,
            observationCount: nil
        )

        writeEntry(entry)
    }

    // MARK: - Private

    private func writeEntry(_ entry: AuditEntry) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(entry),
            var line = String(data: data, encoding: .utf8)
        else {
            return
        }
        line += "\n"
        if let lineData = line.data(using: .utf8) {
            fileHandle?.write(lineData)
        }
    }
}

// MARK: - Audit Entry

/// A single audit log record. Contains no personal health data —
/// only metadata required for traceability (DP4).
struct AuditEntry: Codable, Sendable {
    let timestamp: String
    let event: String
    let idempotencyKey: String?
    let patientRef: String?
    let payloadHashSHA256: String?
    let outcome: String
    let observationCount: Int?
}
