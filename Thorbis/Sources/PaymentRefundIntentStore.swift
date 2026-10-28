import Foundation
import Security

enum FieldPaymentRefundIntentState: String, Codable, Equatable {
    case draft
    case pending
    case reconciliationRequired = "reconciliation_required"
    case uncertain
}

struct FieldPaymentRefundIntent: Codable, Equatable {
    let reason: String
    let state: FieldPaymentRefundIntentState
}

@MainActor
protocol PaymentRefundIntentStoring {
    func load(actorID: String, organizationID: String, paymentID: String) throws -> FieldPaymentRefundIntent?
    func save(_ intent: FieldPaymentRefundIntent, actorID: String, organizationID: String, paymentID: String) throws
    func remove(actorID: String, organizationID: String, paymentID: String) throws
}

@MainActor
final class KeychainPaymentRefundIntentStore: PaymentRefundIntentStoring {
    static let shared = KeychainPaymentRefundIntentStore()

    private let service = "com.thorbis.field.payment-refund-intent"

    func load(actorID: String, organizationID: String, paymentID: String) throws -> FieldPaymentRefundIntent? {
        var query = baseQuery(actorID: actorID, organizationID: organizationID, paymentID: paymentID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainPaymentRefundIntentError.keychainStatus(status)
        }
        do { return try JSONDecoder().decode(FieldPaymentRefundIntent.self, from: data) }
        catch { throw KeychainPaymentRefundIntentError.invalidStoredIntent }
    }

    func save(_ intent: FieldPaymentRefundIntent, actorID: String, organizationID: String, paymentID: String) throws {
        let data: Data
        do { data = try JSONEncoder().encode(intent) }
        catch { throw KeychainPaymentRefundIntentError.encodingFailed }

        let query = baseQuery(actorID: actorID, organizationID: organizationID, paymentID: paymentID)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainPaymentRefundIntentError.keychainStatus(updateStatus)
        }

        var addQuery = query
        addQuery.merge(attributes) { _, newValue in newValue }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainPaymentRefundIntentError.keychainStatus(addStatus)
        }
    }

    func remove(actorID: String, organizationID: String, paymentID: String) throws {
        let status = SecItemDelete(
            baseQuery(actorID: actorID, organizationID: organizationID, paymentID: paymentID) as CFDictionary
        )
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainPaymentRefundIntentError.keychainStatus(status)
        }
    }

    private func baseQuery(actorID: String, organizationID: String, paymentID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: [actorID, organizationID, paymentID].joined(separator: ":")
        ]
    }
}

private enum KeychainPaymentRefundIntentError: LocalizedError {
    case keychainStatus(OSStatus)
    case encodingFailed
    case invalidStoredIntent

    var errorDescription: String? {
        switch self {
        case .keychainStatus:
            return "Secure refund recovery is unavailable. Try again before submitting the refund."
        case .encodingFailed:
            return "The refund reason could not be saved securely. Try again before submitting the refund."
        case .invalidStoredIntent:
            return "The saved refund request could not be read securely. Contact your workspace administrator before retrying."
        }
    }
}
