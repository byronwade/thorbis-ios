import Foundation
import Security

/// Single device-wide receipt blocks any second attempt until reconciliation.
@MainActor final class KeychainBoundTapRecoveryStore: BoundTapRecoveryStoring {
    static let shared = KeychainBoundTapRecoveryStore()
    private let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.thorbis.field.tap-recovery",
        kSecAttrAccount as String: "pending"
    ]
    func load() throws -> BoundTapRecovery? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw BoundTapRecoveryError.unavailable }
        do { return try JSONDecoder().decode(BoundTapRecovery.self, from: data) }
        catch { throw BoundTapRecoveryError.unavailable }
    }
    func save(_ recovery: BoundTapRecovery) throws {
        let data = try JSONEncoder().encode(recovery)
        let attributes: [String: Any] = [kSecValueData as String: data,
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw BoundTapRecoveryError.unavailable }
        var q = query
        q.merge(attributes) { _, new in new }
        guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw BoundTapRecoveryError.unavailable }
    }
    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw BoundTapRecoveryError.unavailable }
    }
}

enum BoundTapRecoveryError: Error { case unavailable }
