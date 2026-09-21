import Foundation
import Security

/// Injected so a harness can hold `password` preferences without touching the real Keychain.
protocol ExtensionPreferenceSecretStore: Sendable {
    func get(account: String) -> String?
    func set(_ value: String, account: String)
    func remove(account: String)
    func removeAll(prefix: String)
}

/// `password`-kind preferences: an extension's API keys, kept out of its plaintext JSON store.
struct KeychainPreferenceSecretStore: ExtensionPreferenceSecretStore {
    private let serviceName = "com.tinycast.extensions.preferences"

    func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func set(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var addition = query
            addition[kSecValueData as String] = data
            addition[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            SecItemAdd(addition as CFDictionary, nil)
        }
    }

    func remove(account: String) {
        SecItemDelete(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: account
            ] as CFDictionary)
    }

    func removeAll(prefix: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let items = item as? [[String: Any]]
        else { return }

        for attributes in items {
            guard let account = attributes[kSecAttrAccount as String] as? String,
                account.hasPrefix(prefix)
            else { continue }
            remove(account: account)
        }
    }
}

extension ExtensionPreferenceSecretStore {
    /// An extension name cannot contain a colon, so the two halves stay unambiguous.
    func account(extension name: String, key: String) -> String { "\(name):\(key)" }
}
