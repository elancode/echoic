import Foundation
import Security

/// Stores and retrieves secrets via the macOS Keychain (Critical Rule #3).
enum KeychainService {
    private static let service = "com.echoic.app"

    enum KeychainError: Error {
        case encodingFailed
        case unexpectedStatus(OSStatus)
        case itemNotFound
    }

    /// Stores a value in the Keychain for the given account.
    static func save(account: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add the new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Retrieves a value from the Keychain for the given account.
    static func retrieve(account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data, let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.encodingFailed
        }

        return string
    }

    /// Deletes a value from the Keychain for the given account.
    static func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

// MARK: - Convenience for API Key

extension KeychainService {
    private static let apiKeyAccount = "anthropic-api-key"

    static func saveAPIKey(_ key: String) throws {
        try save(account: apiKeyAccount, value: key)
    }

    static func retrieveAPIKey() throws -> String {
        try retrieve(account: apiKeyAccount)
    }

    static func deleteAPIKey() throws {
        try delete(account: apiKeyAccount)
    }
}
