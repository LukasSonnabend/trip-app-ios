import Foundation
import Security

enum KeychainKey: String {
    case accessToken = "ch.gograb.trip-planner.access-token"
    case refreshToken = "ch.gograb.trip-planner.refresh-token"
}

final class KeychainManager {
    static let shared = KeychainManager()

    private init() {}

    func store(_ value: String, for key: KeychainKey) {
        guard let data = value.data(using: .utf8) else { return }

        delete(key)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        #if !targetEnvironment(simulator)
        query[kSecAttrAccessGroup as String] = Environment.keychainAccessGroup
        #endif

        SecItemAdd(query as CFDictionary, nil)
    }

    func read(_ key: KeychainKey) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]

        #if !targetEnvironment(simulator)
        query[kSecAttrAccessGroup as String] = Environment.keychainAccessGroup
        #endif

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(_ key: KeychainKey) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
        ]

        #if !targetEnvironment(simulator)
        query[kSecAttrAccessGroup as String] = Environment.keychainAccessGroup
        #endif

        SecItemDelete(query as CFDictionary)
    }

    func deleteAll() {
        delete(.accessToken)
        delete(.refreshToken)
    }

    var accessToken: String? {
        get { read(.accessToken) }
        set { if let v = newValue { store(v, for: .accessToken) } else { delete(.accessToken) } }
    }

    var refreshToken: String? {
        get { read(.refreshToken) }
        set { if let v = newValue { store(v, for: .refreshToken) } else { delete(.refreshToken) } }
    }
}
