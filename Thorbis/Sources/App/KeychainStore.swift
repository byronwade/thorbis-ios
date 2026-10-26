import Foundation
import Security
import ThorbisCore

/// Session credentials live in the Keychain, one item per API environment, so a
/// session for one server is never sent to another. Accessible after first unlock
/// so a background refresh can read it; never synced to other devices.
struct KeychainStore: Sendable {
    private let service = "com.thorbis.field.session"

    func load(for environment: APIEnvironment) -> Credentials {
        var query = baseQuery(environment)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let credentials = try? JSONDecoder().decode(Credentials.self, from: data)
        else { return .none }
        return credentials
    }

    func save(_ credentials: Credentials, for environment: APIEnvironment) {
        let query = baseQuery(environment)
        guard credentials.isSignedIn, let data = try? JSONEncoder().encode(credentials) else {
            SecItemDelete(query as CFDictionary)
            return
        }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { _, new in new }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    func clearAll() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }

    private func baseQuery(_ environment: APIEnvironment) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: environment.baseURL.absoluteString,
        ]
    }
}
