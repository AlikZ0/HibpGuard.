import Foundation
import Security

protocol APIKeyStoring: Sendable {
    func readAPIKey() throws -> String?
    func saveAPIKey(_ key: String) throws
    func deleteAPIKey() throws
}

struct KeychainAPIKeyStore: APIKeyStoring {
    private let service: String
    private let account = "hibp-api-key"

    init(service: String = (Bundle.main.bundleIdentifier ?? "HibpGuard") + ".hibp") {
        self.service = service
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    func readAPIKey() throws -> String? {
        var attributes = query
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AppError.keychain(status) }
        guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            throw AppError.keychain(errSecDecode)
        }
        return key
    }

    func saveAPIKey(_ key: String) throws {
        let updates: [String: Any] = [
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        // Update first: a failed replacement must not delete an existing key.
        let status = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        if status == errSecItemNotFound {
            let attributes = query.merging(updates) { _, new in new }
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw AppError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw AppError.keychain(status)
        }
    }

    func deleteAPIKey() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.keychain(status)
        }
    }
}
