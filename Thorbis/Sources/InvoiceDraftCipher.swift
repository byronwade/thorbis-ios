import Foundation
import CryptoKit

struct InvoiceProtectedDraft: Sendable {
    let ciphertext: Data
    let identity: InvoiceIdleCaptureIdentity
    let owner: UUID
    let sequence: Int64

    fileprivate init(ciphertext: Data, identity: InvoiceIdleCaptureIdentity, owner: UUID, sequence: Int64) {
        self.ciphertext = ciphertext; self.identity = identity; self.owner = owner; self.sequence = sequence
    }
}

/// Held primitive only: the caller must obtain and protect the key and reauthorize before disclosure.
enum InvoiceDraftCipher {
    private struct Binding: Encodable {
        let origin: String, organizationID: String, invoiceID: String
        let actorID: String, customerID: String, jobID: String?
        let owner: String
        let sequence: Int64
    }

    private static func associatedData(identity: InvoiceIdleCaptureIdentity, owner: UUID, sequence: Int64, key: SymmetricKey) throws -> Data {
        guard identity.valid, sequence > 0, key.bitCount == 256 else { throw InvoiceFenceError.invalid }
        let binding = Binding(origin: identity.domain.origin, organizationID: identity.domain.organizationID,
                              invoiceID: identity.domain.invoiceID, actorID: identity.actorID,
                              customerID: identity.customerID, jobID: identity.jobID,
                              owner: owner.uuidString.lowercased(), sequence: sequence)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(binding)
    }

    static func seal(_ raw: Data, identity: InvoiceIdleCaptureIdentity, owner: UUID, sequence: Int64, key: SymmetricKey) throws -> InvoiceProtectedDraft {
        guard !raw.isEmpty else { throw InvoiceFenceError.invalid }
        let aad = try associatedData(identity: identity, owner: owner, sequence: sequence, key: key)
        guard let result = try AES.GCM.seal(raw, using: key, authenticating: aad).combined else { throw InvoiceFenceError.invalid }
        return InvoiceProtectedDraft(ciphertext: result, identity: identity, owner: owner, sequence: sequence)
    }

    static func open(_ ciphertext: Data, identity: InvoiceIdleCaptureIdentity, owner: UUID, sequence: Int64, key: SymmetricKey) throws -> Data {
        let aad = try associatedData(identity: identity, owner: owner, sequence: sequence, key: key)
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: key, authenticating: aad)
    }
}
