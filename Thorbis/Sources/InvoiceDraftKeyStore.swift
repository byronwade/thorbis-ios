import Foundation
import CryptoKit
import Security

enum InvoiceDraftKeyError: Error { case invalidScope, invalidData, keychain(OSStatus) }

protocol InvoiceDraftKeychainTransport: Sendable {
    func add(_ attributes: [String: Any]) -> OSStatus
    func find(_ attributes: [String: Any]) -> (OSStatus, CFTypeRef?)
}

private struct SystemInvoiceDraftKeychain: InvoiceDraftKeychainTransport {
    func add(_ attributes: [String: Any]) -> OSStatus { SecItemAdd(attributes as CFDictionary, nil) }
    func find(_ attributes: [String: Any]) -> (OSStatus, CFTypeRef?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        return (status, result)
    }
}

/// Held primitive: callers must authenticate the scope and prove a journal is empty before creating a key.
/// Never replace a missing key for existing ciphertext; this type performs no journal check or automatic deletion.
actor InvoiceDraftKeyStore {
    private struct KeyScope: Encodable {
        let origin: String, organizationID: String, invoiceID: String, actorID: String, customerID: String
        let jobID: String?
    }
    private let transport: any InvoiceDraftKeychainTransport
    private let service = "com.thorbis.field.invoice-draft-key.v1"

    init() { transport = SystemInvoiceDraftKeychain() }
    init(transport: any InvoiceDraftKeychainTransport) { self.transport = transport }

    private func query(_ identity: InvoiceIdleCaptureIdentity) throws -> [String: Any] {
        guard identity.valid else { throw InvoiceDraftKeyError.invalidScope }
        let scope = KeyScope(origin: identity.domain.origin, organizationID: identity.domain.organizationID,
                             invoiceID: identity.domain.invoiceID, actorID: identity.actorID,
                             customerID: identity.customerID, jobID: identity.jobID)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let account = SHA256.hash(data: try encoder.encode(scope)).map { String(format: "%02x", $0) }.joined()
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: account]
    }

    func load(identity: InvoiceIdleCaptureIdentity) throws -> SymmetricKey? {
        var lookup = try query(identity)
        lookup[kSecReturnData as String] = true; lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, result) = transport.find(lookup)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw InvoiceDraftKeyError.keychain(status) }
        guard let data = result as? Data, data.count == 32 else { throw InvoiceDraftKeyError.invalidData }
        return SymmetricKey(data: data)
    }

    /// Insert-only. The caller must prove no existing ciphertext depends on a missing key.
    func createNew(identity: InvoiceIdleCaptureIdentity) throws -> SymmetricKey {
        var attributes = try query(identity)
        let key = SymmetricKey(size: .bits256)
        attributes[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = transport.add(attributes)
        guard status == errSecSuccess else { throw InvoiceDraftKeyError.keychain(status) }
        return key
    }
}
