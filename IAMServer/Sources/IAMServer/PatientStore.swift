import Foundation

/// Text-file-based patient store (DR1: No manual data entry tasks)
/// Stores patient records as JSON lines in a text file
actor PatientStore {
    private let filePath: String
    private var patients: [String: PatientRecord] = [:]
    private var nextId: Int = 1

    init(directory: String) {
        self.filePath = "\(directory)/patients.txt"
        let fileManager = FileManager.default

        try? fileManager.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )

        // Load existing records
        if let data = fileManager.contents(atPath: filePath),
            let content = String(data: data, encoding: .utf8)
        {
            for line in content.components(separatedBy: .newlines) where !line.isEmpty {
                if let lineData = line.data(using: .utf8),
                    let record = try? JSONDecoder().decode(PatientRecord.self, from: lineData)
                {
                    patients[record.id] = record
                    // Track highest numeric ID to continue incrementing
                    if let numericId = Int(record.id) {
                        nextId = max(nextId, numericId + 1)
                    }
                }
            }
        }
    }

    /// Registers a new patient and returns the created record
    func register(firstName: String, lastName: String, dateOfBirth: String) -> PatientRecord {
        let id = String(nextId)
        nextId += 1
        let record = PatientRecord(
            id: id,
            firstName: firstName,
            lastName: lastName,
            dateOfBirth: dateOfBirth,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        patients[id] = record
        persistAll()
        return record
    }

    /// Checks if a patient exists
    func exists(patientId: String) -> Bool {
        patients[patientId] != nil
    }

    /// Gets a patient by ID
    func get(patientId: String) -> PatientRecord? {
        patients[patientId]
    }

    /// Deletes a patient by ID
    func delete(patientId: String) -> Bool {
        guard patients.removeValue(forKey: patientId) != nil else {
            return false
        }
        persistAll()
        return true
    }

    /// Lists all registered patients
    func listAll() -> [PatientRecord] {
        Array(patients.values).sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Persistence

    private func persistAll() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let lines = patients.values.compactMap { record -> String? in
            guard let data = try? encoder.encode(record) else { return nil }
            return String(data: data, encoding: .utf8)
        }

        let content = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        try? content.write(toFile: filePath, atomically: true, encoding: .utf8)
    }
}
