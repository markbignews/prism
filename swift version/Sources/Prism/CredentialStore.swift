import Foundation
import Security

@MainActor protocol CredentialStore {
    func read(account: String) throws -> String?
    func write(_ value: String, account: String) throws
    func remove(account: String) throws
}

@MainActor final class KeychainCredentials: CredentialStore {
    private let service = "com.prism.chatclient.provider-key"
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false]
    }
    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw SQLiteStore.Failure(message: "Keychain: " + ((SecCopyErrorMessageString(status, nil) as String?) ?? String(status)))
        }
    }
    func read(account: String) throws -> String? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw SQLiteStore.Failure(message: "Keychain returned invalid credential data.")
        }
        return value
    }
    func write(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var request = query(account)
            request[kSecValueData as String] = data
            request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            try check(SecItemAdd(request as CFDictionary, nil))
        } else { try check(status) }
    }
    func remove(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
}
