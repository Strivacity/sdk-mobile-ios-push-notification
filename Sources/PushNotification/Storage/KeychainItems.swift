import Foundation
import Security

/// The Keychain operations `DefaultPushNotificationStorage` needs: generic-password items under one
/// service, each identified by its account attribute.
protocol KeychainItems: Sendable {
    /// Adds an item, replacing any item already stored under the same account.
    func add(_ data: Data, account: String) throws

    /// The data of the item stored under this account, or `nil` if there is none.
    func data(account: String) throws -> Data?

    /// Every stored item's data, keyed by account.
    func all() throws -> [String: Data]

    /// Removes the item stored under this account. Does nothing if there is none.
    func delete(account: String) throws
}

/// `KeychainItems` backed by the system Keychain, under the SDK's own service name.
///
/// Items are accessible after the device's first unlock and are never migrated to another device.
struct SystemKeychainItems: KeychainItems {
    private static let service = "com.strivacity.pushnotification.enrollmentkeys"

    func add(_ data: Data, account: String) throws {
        // A failure here surfaces from SecItemAdd below as a duplicate item instead.
        try? delete(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw PushNotificationError.storageFailure(
                message: "Keychain item could not be saved",
                cause: keychainError(status)
            )
        }
    }

    func data(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw PushNotificationError.storageFailure(message: "Keychain lookup failed", cause: keychainError(status))
        }

        return data
    }

    func all() throws -> [String: Data] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return [:]
        }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            throw PushNotificationError.storageFailure(message: "Keychain lookup failed", cause: keychainError(status))
        }

        var dataByAccount: [String: Data] = [:]
        for item in items {
            if let account = item[kSecAttrAccount as String] as? String,
               let data = item[kSecValueData as String] as? Data {
                dataByAccount[account] = data
            }
        }
        return dataByAccount
    }

    func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PushNotificationError.storageFailure(
                message: "Keychain item could not be removed",
                cause: keychainError(status)
            )
        }
    }

    private func keychainError(_ status: OSStatus) -> Error {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: message])
    }
}
