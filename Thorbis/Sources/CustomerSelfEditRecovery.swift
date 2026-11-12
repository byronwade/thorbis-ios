import Foundation
import Security

struct CustomerSelfEditRecoveryScope: Codable, Equatable {
    let actorID: String
    let organizationID: String
    let customerID: String
    let origin: String
}

enum CustomerSelfEditPendingWrite: Codable, Equatable {
    case reviewDraft
    case customer
    case contact(String)
    case createContact
    case location(String)
    case consent
}

struct CustomerSelfEditRecovery: Codable, Equatable {
    var draft: CustomerSelfEditDraft
    var pending: CustomerSelfEditPendingWrite?
    var consentKey: String
    var completed: Bool = false
}

@MainActor
protocol CustomerSelfEditRecoveryStoring {
    func load(scope: CustomerSelfEditRecoveryScope) throws -> CustomerSelfEditRecovery?
    func save(_ recovery: CustomerSelfEditRecovery, scope: CustomerSelfEditRecoveryScope) throws
    func remove(scope: CustomerSelfEditRecoveryScope) throws
}

@MainActor
final class KeychainCustomerSelfEditRecoveryStore: CustomerSelfEditRecoveryStoring {
    static let shared = KeychainCustomerSelfEditRecoveryStore()
    private let service = "com.thorbis.field.customer-self-edit-recovery"

    private func query(_ scope: CustomerSelfEditRecoveryScope) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let account = try encoder.encode(scope).base64EncodedString()
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    func load(scope: CustomerSelfEditRecoveryScope) throws -> CustomerSelfEditRecovery? {
        var lookup = try query(scope)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw RecoveryError.keychain(status) }
        return try JSONDecoder().decode(CustomerSelfEditRecovery.self, from: data)
    }

    func save(_ recovery: CustomerSelfEditRecovery, scope: CustomerSelfEditRecoveryScope) throws {
        let identity = try query(scope)
        let data = try JSONEncoder().encode(recovery)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = identity
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(insert as CFDictionary, nil)
            guard added == errSecSuccess else { throw RecoveryError.keychain(added) }
        } else if status != errSecSuccess { throw RecoveryError.keychain(status) }
    }

    func remove(scope: CustomerSelfEditRecoveryScope) throws {
        let status = SecItemDelete(try query(scope) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw RecoveryError.keychain(status) }
    }

    private enum RecoveryError: Error { case keychain(OSStatus) }
}
