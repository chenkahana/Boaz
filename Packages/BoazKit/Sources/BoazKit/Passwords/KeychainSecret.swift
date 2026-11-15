import Foundation
import Security

/// One secret Boaz keeps for itself (an account's token) as a generic password in this device's Keychain. Not
/// synced: each device signs in on its own.
public struct KeychainSecret: Sendable {
    public let service: String
    public let account: String

    public init(service: String, account: String) {
        self.service = service; self.account = account
    }

    public func read() -> String? {
        var query = query(dataProtection: true)
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = true
        var result: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecMissingEntitlement || status == errSecItemNotFound {
            // An unsigned build can't reach the data protection keychain, so it kept the secret in the login keychain.
            query = self.query(dataProtection: false)
            query[kSecMatchLimit] = kSecMatchLimitOne
            query[kSecReturnData] = true
            status = SecItemCopyMatching(query as CFDictionary, &result)
        }
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ value: String) throws {
        try? delete()
        var status = add(value, dataProtection: true)
        if status == errSecMissingEntitlement { status = add(value, dataProtection: false) }
        guard status == errSecSuccess else { throw SavedPasswords.KeychainError(status: status) }
    }

    public func delete() throws {
        for dataProtection in [true, false] {
            let status = SecItemDelete(query(dataProtection: dataProtection) as CFDictionary)
            guard [errSecSuccess, errSecItemNotFound, errSecMissingEntitlement].contains(status) else {
                throw SavedPasswords.KeychainError(status: status)
            }
        }
    }

    private func add(_ value: String, dataProtection: Bool) -> OSStatus {
        var attributes = query(dataProtection: dataProtection)
        attributes[kSecValueData] = Data(value.utf8)
        if dataProtection { attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly }
        attributes[kSecAttrLabel] = service
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    private func query(dataProtection: Bool) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseDataProtectionKeychain: dataProtection,
        ]
    }
}
