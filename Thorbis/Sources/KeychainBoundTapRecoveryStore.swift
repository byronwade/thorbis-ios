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
        guard status == errSecSuccess else { throw BoundTapRecoveryError.unavailable }
    }
    func create(_ recovery: BoundTapRecovery) throws -> Bool {
        let data = try JSONEncoder().encode(recovery)
        var q = query
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        if status == errSecDuplicateItem { return false }
        guard status == errSecSuccess else { throw BoundTapRecoveryError.unavailable }
        return true
    }
    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw BoundTapRecoveryError.unavailable }
    }
}

enum BoundTapRecoveryError: Error { case unavailable }
