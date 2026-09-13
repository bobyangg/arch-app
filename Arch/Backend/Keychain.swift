import Foundation
import Security

/// The smallest useful wrapper over the keychain.
///
/// The refresh token lives here rather than in `UserDefaults` because it is a
/// long-lived credential: anybody holding it can mint access tokens until it is
/// revoked. `UserDefaults` is a plist in the app container, readable from a backup.
///
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` is deliberate on both halves:
/// *afterFirstUnlock* so a notification arriving before the reader has opened their
/// phone can still be handled, and *thisDeviceOnly* so the token is not carried to
/// a new phone by an encrypted backup — a session should not outlive the device it
/// was granted to.
enum Keychain {

    enum Failure: Error {
        case status(OSStatus)
    }

    static func set(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { current, _ in current }
            let added = SecItemAdd(insert as CFDictionary, nil)
            guard added == errSecSuccess else { throw Failure.status(added) }
            return
        }
        guard status == errSecSuccess else { throw Failure.status(status) }
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static let service = "com.arch.session"
}
