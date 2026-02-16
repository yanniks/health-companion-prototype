import Foundation

/// Text-file-based authorization code store
/// Codes expire after 10 minutes per OAuth 2.0 spec (RFC 6749 §4.1.2)
actor AuthorizationCodeStore {
    private let filePath: String
    private var codes: [String: AuthorizationCode] = [:]
    private let codeLifetime: TimeInterval = 600 // 10 minutes

    init(directory: String) {
        self.filePath = "\(directory)/auth_codes.txt"
        let fileManager = FileManager.default

        try? fileManager.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )

        // Load existing codes (if server restarts), filtering expired
        let now = Date().timeIntervalSince1970
        if let data = fileManager.contents(atPath: filePath),
           let content = String(data: data, encoding: .utf8)
        {
            let decoder = JSONDecoder()
            for line in content.components(separatedBy: .newlines) where !line.isEmpty {
                if let lineData = line.data(using: .utf8),
                   let code = try? decoder.decode(AuthorizationCode.self, from: lineData),
                   now - code.createdAt < codeLifetime
                {
                    codes[code.code] = code
                }
            }
        }
    }

    /// Generates a new authorization code
    func generate(
        clientId: String,
        patientId: String,
        redirectURI: String,
        codeChallenge: String,
        codeChallengeMethod: String,
        scope: String,
        state: String
    ) -> String {
        cleanupExpired()

        let codeValue = generateSecureCode()
        let authCode = AuthorizationCode(
            code: codeValue,
            clientId: clientId,
            patientId: patientId,
            redirectURI: redirectURI,
            codeChallenge: codeChallenge,
            codeChallengeMethod: codeChallengeMethod,
            scope: scope,
            state: state,
            createdAt: Date().timeIntervalSince1970
        )

        codes[codeValue] = authCode
        persistAll()
        return codeValue
    }

    /// Consumes (validates and removes) an authorization code
    /// Returns nil if code is invalid or expired
    func consume(code: String) -> AuthorizationCode? {
        cleanupExpired()

        guard let authCode = codes.removeValue(forKey: code) else {
            return nil
        }

        // Check expiration
        let now = Date().timeIntervalSince1970
        guard now - authCode.createdAt < codeLifetime else {
            persistAll()
            return nil
        }

        persistAll()
        return authCode
    }

    // MARK: - Private

    private func cleanupExpired() {
        let now = Date().timeIntervalSince1970
        codes = codes.filter { now - $0.value.createdAt < codeLifetime }
    }

    private func generateSecureCode() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).map { String(format: "%02x", $0) }.joined()
    }

    private func persistAll() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let lines = codes.values.compactMap { code -> String? in
            guard let data = try? encoder.encode(code) else { return nil }
            return String(data: data, encoding: .utf8)
        }

        let content = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        try? content.write(toFile: filePath, atomically: true, encoding: .utf8)
    }
}
