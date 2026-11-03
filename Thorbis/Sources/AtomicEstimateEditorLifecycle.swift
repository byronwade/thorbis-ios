import Foundation

/// Disconnected editor lifecycle prototype. It is not a permission check or a
/// send implementation. The editor must still prove its live authority, guard
/// every exit and coordinate all other writers before this may be wired.
@MainActor final class AtomicEstimateEditorLifecycle {
    enum State: Equatable { case notOpen, editable, saveFailed, stageUncertain, attemptPending, closed }
    enum Failure: Error { case invalidState, unavailable }
    private(set) var state: State = .notOpen
    private let store: CommercialDraftStore
    private let journal: AtomicEstimateAttemptJournal
    private let draftScope: CommercialDraftScope
    private let owner: UUID
    private let actorID, organizationID, origin, jobID: String
    private let customerID: String
    private let locationID: String?

    init(store: CommercialDraftStore, draftScope: CommercialDraftScope, owner: UUID,
         actorID: String, organizationID: String, origin: String, jobID: String,
         customerID: String, locationID: String?) {
        self.store = store; self.journal = AtomicEstimateAttemptJournal(store: store)
        self.draftScope = draftScope; self.owner = owner
        self.actorID = actorID; self.organizationID = organizationID; self.origin = origin; self.jobID = jobID
        self.customerID = customerID; self.locationID = locationID
    }

    func open() throws {
        guard state == .notOpen, [actorID, organizationID, jobID, customerID].allSatisfy({ UUID(uuidString: $0) != nil }),
              locationID.map({ UUID(uuidString: $0) != nil }) ?? true, draftScope.kind == "new-estimate",
              draftScope.actor.lowercased() == actorID.lowercased(),
              draftScope.organization.lowercased() == organizationID.lowercased(), draftScope.origin == origin,
              draftScope.document.lowercased() == "job:\(jobID.lowercased())|customer:\(customerID.lowercased())|location:\(locationID?.lowercased() ?? "")" else { throw Failure.invalidState }
        guard try store.acquireCoordinatedDraft(scope: draftScope, owner: owner) else { throw Failure.unavailable }
        do {
            let existing = try store.load(CommercialNewEstimateDraft.self, scope: draftScope)
            if let existing {
                guard existing.customerID.lowercased() == customerID.lowercased() else { throw Failure.unavailable }
                if existing.uncertain || existing.created != nil || existing.atomicOperation != nil ||
                    existing.requiresManualReview || existing.requiresLocationVerification || existing.requiresGroupDisclosure {
                    state = .attemptPending
                    return
                }
            }
            switch try journal.status(actorID: actorID, organizationID: organizationID, origin: origin, jobID: jobID) {
            case .missing: state = .editable // local absence is not proof of no prior server write
            case .legacyPending, .atomicPending: state = .attemptPending
            }
        } catch {
            store.release(scope: draftScope, owner: owner)
            throw error
        }
    }

    func save(_ draft: CommercialNewEstimateDraft) throws {
        guard state == .editable || state == .saveFailed, draft.customerID.lowercased() == customerID.lowercased() else { throw Failure.invalidState }
        do {
            try store.saveCoordinatedDraft(draft, scope: draftScope, owner: owner)
            state = .editable
        } catch {
            state = .saveFailed
            throw error
        }
    }

    /// The caller must keep the editor visible and retain its in-memory draft
    /// on failure. Closing preserves the draft; this API does not discard it.
    func close(preserving draft: CommercialNewEstimateDraft) throws {
        guard state == .editable || state == .saveFailed || state == .attemptPending else { throw Failure.invalidState }
        if state != .attemptPending { try save(draft) }
        store.release(scope: draftScope, owner: owner)
        state = .closed
    }

    /// Reserving is not authorization to send. An error after staging may
    /// still have installed the marker, so this lifecycle remains held.
    func stageLegacy(draft: CommercialNewEstimateDraft, attemptID: UUID) throws {
        guard state == .editable else { throw Failure.invalidState }
        try save(draft)
        do {
            _ = try journal.stageLegacy(draftScope: draftScope, draftOwner: owner, actorID: actorID,
                organizationID: organizationID, origin: origin, jobID: jobID, customerID: customerID,
                locationID: locationID, attemptID: attemptID)
            state = .attemptPending
        } catch { state = .stageUncertain; throw error }
    }

    func stageAtomic(draft: CommercialNewEstimateDraft, operation: AtomicEstimateCommand, storesLineGroups: Bool) throws {
        guard state == .editable else { throw Failure.invalidState }
        try save(draft)
        do {
            _ = try journal.prepare(operation: operation, draftScope: draftScope, draftOwner: owner,
                actorID: actorID, organizationID: organizationID, origin: origin, jobID: jobID,
                storesLineGroups: storesLineGroups)
            state = .attemptPending
        } catch { state = .stageUncertain; throw error }
    }
}
