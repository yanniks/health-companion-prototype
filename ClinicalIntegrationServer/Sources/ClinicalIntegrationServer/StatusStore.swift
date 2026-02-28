import Foundation

/// Tracks processing status per patient (text-file-based)
actor StatusStore {
    private let filePath: String
    private var statuses: [String: PatientStatusRecord] = [:]

    struct PatientStatusRecord: Codable, Sendable {
        let patientId: String
        var lastTransferTimestamp: String
        var totalTransfers: Int
    }

    init(directory: String) {
        self.filePath = "\(directory)/clinical_status.txt"
        let fileManager = FileManager.default

        try? fileManager.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )

        if let data = fileManager.contents(atPath: filePath),
            let content = String(data: data, encoding: .utf8)
        {
            let decoder = JSONDecoder()
            for line in content.components(separatedBy: .newlines) where !line.isEmpty {
                if let lineData = line.data(using: .utf8),
                    let record = try? decoder.decode(PatientStatusRecord.self, from: lineData)
                {
                    statuses[record.patientId] = record
                }
            }
        }
    }

    func recordTransfer(patientId: String) {
        let now = ISO8601DateFormatter().string(from: Date())
        if var existing = statuses[patientId] {
            existing.totalTransfers += 1
            existing.lastTransferTimestamp = now
            statuses[patientId] = existing
        } else {
            statuses[patientId] = PatientStatusRecord(
                patientId: patientId,
                lastTransferTimestamp: now,
                totalTransfers: 1
            )
        }
        persistAll()
    }

    func getStatus(patientId: String) -> PatientStatusRecord? {
        statuses[patientId]
    }

    private func persistAll() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let lines = statuses.values.compactMap { record -> String? in
            guard let data = try? encoder.encode(record) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        let content = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        try? content.write(toFile: filePath, atomically: true, encoding: .utf8)
    }
}
