import Foundation

/// Text-file-based refresh token store
/// Tokens expire after 30 days (DP4: Security and privacy by design)
actor RefreshTokenStore {
    private let filePath: String
    private var tokens: [String: RefreshToken] = [:]
    private let tokenLifetime: TimeInterval = 30 * 24 * 3600  // 30 days

    init(directory: String) {
        self.filePath = "\(directory)/refresh_tokens.txt"
        let fileManager = FileManager.default

        try? fileManager.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )

        // Load existing tokens, filtering expired
        let now = Date().timeIntervalSince1970
        if let data = fileManager.contents(atPath: filePath),
            let content = String(data: data, encoding: .utf8)
        {
            let decoder = JSONDecoder()
            for line in content.components(separatedBy: .newlines) where !line.isEmpty {
                if let lineData = line.data(using: .utf8),
                    let token = try? decoder.decode(RefreshToken.self, from: lineData),
                    now - token.createdAt < tokenLifetime
                {
                    tokens[token.token] = token
                }
            }
        }
    }

    /// Generates a new refresh token
    func generate(clientId: String, scope: String) -> String {
        cleanupExpired()

        let tokenValue = generateSecureToken()
        let refreshToken = RefreshToken(
            token: tokenValue,
            clientId: clientId,
            scope: scope,
            createdAt: Date().timeIntervalSince1970
        )

        tokens[tokenValue] = refreshToken
        persistAll()
        return tokenValue
    }

    /// Consumes (validates and removes) a refresh token — rotation scheme
    /// Returns nil if token is invalid or expired
    func consume(token: String) -> RefreshToken? {
        cleanupExpired()

        guard let refreshToken = tokens.removeValue(forKey: token) else {
            return nil
        }

        let now = Date().timeIntervalSince1970
        guard now - refreshToken.createdAt < tokenLifetime else {
            persistAll()
            return nil
        }

        persistAll()
        return refreshToken
    }

    /// Revokes a specific refresh token
    func revoke(token: String) {
        tokens.removeValue(forKey: token)
        persistAll()
    }

    /// Revokes all refresh tokens for a client
    func revokeAll(clientId: String) {
        tokens = tokens.filter { $0.value.clientId != clientId }
        persistAll()
    }

    // MARK: - Private

    private func cleanupExpired() {
        let now = Date().timeIntervalSince1970
        tokens = tokens.filter { now - $0.value.createdAt < tokenLifetime }
    }

    private func generateSecureToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        var rng = SystemRandomNumberGenerator()
        for i in bytes.indices { bytes[i] = rng.next() }
        return Data(bytes).map { String(format: "%02x", $0) }.joined()
    }

    private func persistAll() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let lines = tokens.values.compactMap { token -> String? in
            guard let data = try? encoder.encode(token) else { return nil }
            return String(data: data, encoding: .utf8)
        }

        let content = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        try? content.write(toFile: filePath, atomically: true, encoding: .utf8)
    }
}
