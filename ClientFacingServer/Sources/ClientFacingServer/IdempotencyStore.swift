import Foundation

/// Text-file-based idempotency key store to prevent duplicate submissions
/// (DR5: Security requirements)
actor IdempotencyStore {
    private let filePath: String
    private var keys: [String: IdempotencyRecord] = [:]
    private let keyLifetime: TimeInterval = 24 * 3600 // 24 hours

    struct IdempotencyRecord: Codable, Sendable {
        let key: String
        let clientId: String
        let responseJSON: String
        let createdAt: Double
    }

    init(directory: String) {
        self.filePath = "\(directory)/idempotency.txt"
        let fileManager = FileManager.default

        try? fileManager.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )

        let now = Date().timeIntervalSince1970
        if let data = fileManager.contents(atPath: filePath),
           let content = String(data: data, encoding: .utf8)
        {
            let decoder = JSONDecoder()
            for line in content.components(separatedBy: .newlines) where !line.isEmpty {
                if let lineData = line.data(using: .utf8),
                   let record = try? decoder.decode(IdempotencyRecord.self, from: lineData),
                   now - record.createdAt < keyLifetime
                {
                    keys[record.key] = record
                }
            }
        }
    }

    /// Check if an idempotency key exists, and return the cached response if so
    func check(key: String, clientId: String) -> String? {
        guard let record = keys[key], record.clientId == clientId else {
            return nil
        }
        return record.responseJSON
    }

    /// Store an idempotency key with its response
    func store(key: String, clientId: String, responseJSON: String) {
        let record = IdempotencyRecord(
            key: key,
            clientId: clientId,
            responseJSON: responseJSON,
            createdAt: Date().timeIntervalSince1970
        )
        keys[key] = record
        persistAll()
    }

    private func persistAll() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let lines = keys.values.compactMap { record -> String? in
            guard let data = try? encoder.encode(record) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        let content = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        try? content.write(toFile: filePath, atomically: true, encoding: .utf8)
    }
}
