//
//  KeychainStore.swift
//  Health Companion
//
//  Provides secure storage for OAuth tokens using the iOS Keychain.
//  Maps to: DP4 (Security and privacy by design)
//

import Foundation
import OSLog
import Security

/// Thread-safe Keychain wrapper for storing and retrieving OAuth credentials.
///
/// Uses `kSecClassGenericPassword` with a service identifier to scope
/// entries to this application. All operations are synchronous and
/// safe to call from any actor context.
struct KeychainStore: Sendable {
    private let service: String
    private let logger = Logger(subsystem: "HealthCompanion", category: "KeychainStore")

    init(service: String = "com.healthcompanion.auth") {
        self.service = service
    }

    // MARK: - Public API

    /// Saves a string value to the Keychain under the given key.
    @discardableResult
    func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return save(key: key, data: data)
    }

    /// Retrieves a string value from the Keychain for the given key.
    func load(key: String) -> String? {
        guard let data = loadData(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Deletes the entry for the given key from the Keychain.
    @discardableResult
    func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.warning("Keychain delete failed for key '\(key)': \(status)")
        }
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Removes all entries stored under this service.
    func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Internal

    private func save(key: String, data: Data) -> Bool {
        // Delete existing entry first
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Keychain save failed for key '\(key)': \(status)")
        }
        return status == errSecSuccess
    }

    private func loadData(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }
}

// MARK: - Key Constants

extension KeychainStore {
    /// Keys used for storing OAuth credentials in the Keychain.
    enum Keys {
        static let accessToken = "oauth.accessToken"
        static let refreshToken = "oauth.refreshToken"
        static let tokenExpiry = "oauth.tokenExpiry"
        static let patientId = "oauth.patientId"
        static let scope = "oauth.scope"
    }
}
