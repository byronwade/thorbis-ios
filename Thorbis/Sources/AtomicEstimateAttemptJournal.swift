import Foundation

/// Held, disconnected write-ahead journal. Preparation never sends or removes
/// a draft. An attempted operation must remain pending until authoritative
/// reconciliation and a separately qualified cleanup protocol exist.
@MainActor final class AtomicEstimateAttemptJournal {
    struct Record: Codable, Equatable {
        let operation: AtomicEstimateCommand
        /// The exact saved editor draft, retained as opaque bytes. The caller
        /// must independently prove this draft maps to the command's terms.
        let editorDraft: Data
    }
    enum Failure: Error { case invalidScope, invalidDraft, occupied, unavailable }
    private let store: CommercialDraftStore
    init(store: CommercialDraftStore) { self.store = store }

    private func scope(operation: AtomicEstimateCommand, actorID: String, organizationID: String,
                       origin: String, jobID: String) throws -> CommercialDraftScope {
        guard operation.maySend(actorID: actorID, organizationID: organizationID, jobID: jobID,
                                origin: origin, authorized: true) else { throw Failure.invalidScope }
        return .init(actor: operation.actorID, organization: operation.organizationID, origin: operation.origin,
                     kind: "atomic-estimate-attempt", document: operation.payload.jobId)
    }

    /// This writes and re-reads the immutable record before returning it. It
    /// never authorizes an upload: the caller still needs a current session,
    /// exact job permission and a verified mapping of the saved draft's terms.
    func prepare(operation: AtomicEstimateCommand, draftScope: CommercialDraftScope, draftOwner: UUID,
                 actorID: String, organizationID: String, origin: String, jobID: String) throws -> Record {
        let key = try scope(operation: operation, actorID: actorID, organizationID: organizationID,
                            origin: origin, jobID: jobID)
        guard let target = operation.draftTarget, store.isOwned(scope: draftScope, owner: draftOwner),
              draftScope.kind == "new-estimate", draftScope.actor.lowercased() == operation.actorID,
              draftScope.organization.lowercased() == operation.organizationID, draftScope.origin == operation.origin,
              draftScope.document.lowercased() == "job:\(operation.payload.jobId)|customer:\(target.customerID)|location:\(target.locationID ?? "")",
              let draft = try store.load(CommercialNewEstimateDraft.self, scope: draftScope),
              draft.customerID.lowercased() == target.customerID,
              draft.title.trimmingCharacters(in: .whitespacesAndNewlines) == operation.payload.title,
              draft.created == nil, !draft.uncertain, draft.atomicOperation == nil,
              !draft.requiresManualReview, !draft.requiresLocationVerification,
              !draft.requiresGroupDisclosure else { throw Failure.invalidDraft }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let editorDraft = try encoder.encode(draft)
        let owner = UUID()
        guard store.acquire(scope: key, owner: owner) else { throw Failure.occupied }
        defer { store.release(scope: key, owner: owner) }
        let proposed = Record(operation: operation, editorDraft: editorDraft)
        if let existing = try store.load(Record.self, scope: key) {
            guard existing == proposed else { throw Failure.occupied }
            return existing
        }
        try store.save(proposed, scope: key)
        guard let saved = try store.load(Record.self, scope: key), saved == proposed else { throw Failure.unavailable }
        return saved
    }

    /// Reopening requires the original actor, tenant, origin and exact job.
    /// A missing, malformed or differently scoped record cannot be treated as
    /// proof that a previous submission did not happen.
    func recover(actorID: String, organizationID: String, origin: String, jobID: String) throws -> Record? {
        guard [actorID, organizationID, jobID].allSatisfy({ UUID(uuidString: $0) != nil }) else { throw Failure.invalidScope }
        let key = CommercialDraftScope(actor: actorID.lowercased(), organization: organizationID.lowercased(),
                                       origin: origin, kind: "atomic-estimate-attempt", document: jobID.lowercased())
        let owner = UUID()
        guard store.acquire(scope: key, owner: owner) else { throw Failure.occupied }
        defer { store.release(scope: key, owner: owner) }
        guard let saved = try store.load(Record.self, scope: key) else { return nil }
        guard saved.operation.maySend(actorID: actorID, organizationID: organizationID, jobID: jobID,
                                      origin: origin, authorized: true), !saved.editorDraft.isEmpty else { throw Failure.unavailable }
        return saved
    }
}
