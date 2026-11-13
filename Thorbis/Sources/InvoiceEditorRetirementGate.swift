import Foundation
import CryptoKit

/// Captured identity is bookkeeping, never proof of current authorization.
struct InvoiceEditorAuthorityIdentity: Equatable, Sendable {
    let actorID: String
    let organizationID: String
    let origin: String
    let sessionGeneration: UUID
    let authorityRevision: UUID
}

/// Created only after the store reports a successful commit of these exact bytes.
struct InvoiceDraftCaptureReceipt: Sendable {
    fileprivate let authority: InvoiceEditorAuthorityIdentity
    fileprivate let scope: InvoiceIdleCaptureIdentity
    fileprivate let owner: UUID
    fileprivate let sequence: Int64
    fileprivate let version: Int64
    fileprivate let digest: Data
}

struct InvoiceRecoveredProtectedDraft: Sendable {
    let protectedBytes: Data
    fileprivate let receipt: InvoiceDraftCaptureReceipt
}

/// Held prototype: callers must encrypt bytes, protect storage, and independently verify authority.
/// It neither submits an invoice nor proves that a server request has settled.
actor InvoiceSerialDraftWriter {
    private let fence: InvoiceTransactionFence
    private let identity: InvoiceIdleCaptureIdentity
    private let authority: InvoiceEditorAuthorityIdentity
    private let owner: UUID
    private var version: Int64?
    private var lastSequence: Int64 = 0
    private var held = false

    init(fence: InvoiceTransactionFence, identity: InvoiceIdleCaptureIdentity,
         authority: InvoiceEditorAuthorityIdentity, owner: UUID) {
        self.fence = fence; self.identity = identity; self.authority = authority; self.owner = owner
    }

    /// The caller must independently verify current authority and the server baseline before disclosure.
    func recover(authority current: InvoiceEditorAuthorityIdentity, authorized: Bool) throws -> InvoiceRecoveredProtectedDraft? {
        guard !held, version == nil, lastSequence == 0, authorized, current == authority,
              authority.actorID == identity.actorID, authority.organizationID == identity.domain.organizationID,
              authority.origin == identity.domain.origin else { throw InvoiceFenceError.invalid }
        do {
            guard let recovered = try fence.recoverIdle(identity: identity) else { return nil }
            guard recovered.owner == owner else { throw InvoiceFenceError.conflict }
            version = recovered.version; lastSequence = recovered.sequence
            let receipt = InvoiceDraftCaptureReceipt(authority: authority, scope: identity, owner: owner,
                                                     sequence: recovered.sequence, version: recovered.version,
                                                     digest: Data(SHA256.hash(data: recovered.bytes)))
            return InvoiceRecoveredProtectedDraft(protectedBytes: recovered.bytes, receipt: receipt)
        } catch {
            held = true
            throw error
        }
    }

    func capture(_ protected: InvoiceProtectedDraft, authority current: InvoiceEditorAuthorityIdentity) throws -> InvoiceDraftCaptureReceipt {
        let sequence = protected.sequence
        let protectedBytes = protected.ciphertext
        guard !held, current == authority, authority.actorID == identity.actorID,
              authority.organizationID == identity.domain.organizationID, authority.origin == identity.domain.origin,
              protected.owner == owner, protected.identity.actorID == identity.actorID,
              protected.identity.customerID == identity.customerID, protected.identity.jobID == identity.jobID,
              protected.identity.domain.origin == identity.domain.origin,
              protected.identity.domain.organizationID == identity.domain.organizationID,
              protected.identity.domain.invoiceID == identity.domain.invoiceID,
              sequence > lastSequence, !protectedBytes.isEmpty else { throw InvoiceFenceError.invalid }
        do {
            let committed = try fence.capture(identity: identity, owner: owner, expectedVersion: version,
                                               sequence: sequence, bytes: protectedBytes)
            version = committed; lastSequence = sequence
            return InvoiceDraftCaptureReceipt(authority: authority, scope: identity, owner: owner,
                                               sequence: sequence, version: committed,
                                               digest: Data(SHA256.hash(data: protectedBytes)))
        } catch {
            // A failed or ambiguous commit is never silently retried or acknowledged.
            held = true
            throw error
        }
    }
}

/// In-memory bookkeeping. A receipt is meaningful only when the store and caller are qualified.
struct InvoiceEditorRetirementGate {
    enum Retirement: Equatable { case pending, durable, failed }
    let identity: InvoiceEditorAuthorityIdentity
    let scope: InvoiceIdleCaptureIdentity
    let owner: UUID
    private(set) var latestEdit: Int64 = 0
    private(set) var acknowledgedEdit: Int64 = 0
    private var latestDigest: Data?
    private var failedEdit: Int64?
    private var sequenceExhausted = false

    init(identity: InvoiceEditorAuthorityIdentity, scope: InvoiceIdleCaptureIdentity, owner: UUID) {
        self.identity = identity; self.scope = scope; self.owner = owner
    }

    mutating func reserveEdit() -> Int64? {
        guard latestEdit < Int64.max else { sequenceExhausted = true; return nil }
        latestEdit += 1
        latestDigest = nil
        return latestEdit
    }

    mutating func bind(_ protected: InvoiceProtectedDraft) -> Bool {
        guard protected.sequence == latestEdit, protected.owner == owner,
              protected.identity.actorID == scope.actorID, protected.identity.customerID == scope.customerID,
              protected.identity.jobID == scope.jobID, protected.identity.domain.origin == scope.domain.origin,
              protected.identity.domain.organizationID == scope.domain.organizationID,
              protected.identity.domain.invoiceID == scope.domain.invoiceID else { return false }
        let digest = Data(SHA256.hash(data: protected.ciphertext))
        if let latestDigest {
            if latestDigest != digest { failedEdit = latestEdit }
            return false
        }
        guard failedEdit != latestEdit else { return false }
        latestDigest = digest
        return true
    }

    mutating func acknowledge(_ receipt: InvoiceDraftCaptureReceipt) {
        guard matches(receipt), receipt.sequence == latestEdit, failedEdit != latestEdit,
              receipt.digest == latestDigest else { return }
        acknowledgedEdit = receipt.sequence
        failedEdit = nil
    }

    private func matches(_ receipt: InvoiceDraftCaptureReceipt) -> Bool {
        receipt.authority == identity && receipt.owner == owner &&
        receipt.scope.domain.origin == scope.domain.origin &&
        receipt.scope.domain.organizationID == scope.domain.organizationID &&
        receipt.scope.domain.invoiceID == scope.domain.invoiceID &&
        receipt.scope.actorID == scope.actorID && receipt.scope.customerID == scope.customerID &&
        receipt.scope.jobID == scope.jobID && receipt.version > 0
    }

    /// Call only after live authority and the recovered server baseline have been verified.
    mutating func restore(_ recovered: InvoiceRecoveredProtectedDraft,
                          current: InvoiceEditorAuthorityIdentity?, authorized: Bool) -> Data? {
        guard latestEdit == 0, acknowledgedEdit == 0, !sequenceExhausted, failedEdit == nil,
              mayDisplay(identity: current, authorized: authorized),
              matches(recovered.receipt), recovered.receipt.sequence > 0,
              Data(SHA256.hash(data: recovered.protectedBytes)) == recovered.receipt.digest else { return nil }
        latestEdit = recovered.receipt.sequence
        latestDigest = recovered.receipt.digest
        acknowledge(recovered.receipt)
        return recovered.protectedBytes
    }

    mutating func fail(_ sequence: Int64) {
        guard sequence == latestEdit, sequence > acknowledgedEdit else { return }
        failedEdit = sequence
    }

    var retirement: Retirement {
        if sequenceExhausted { return .failed }
        if failedEdit == latestEdit { return .failed }
        if latestEdit == acknowledgedEdit { return .durable }
        return failedEdit == latestEdit ? .failed : .pending
    }

    func mayDisplay(identity current: InvoiceEditorAuthorityIdentity?, authorized: Bool) -> Bool {
        authorized && current == identity
    }
}
