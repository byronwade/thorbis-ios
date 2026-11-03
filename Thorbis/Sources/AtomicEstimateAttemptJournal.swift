import Foundation

/// Held, disconnected write-ahead journal. Preparation never sends or removes
/// a draft. An attempted operation must remain pending until authoritative
/// reconciliation and a separately qualified cleanup protocol exist.
@MainActor final class AtomicEstimateAttemptJournal {
    struct Record: Codable, Equatable {
        let operation: AtomicEstimateCommand
        /// The exact saved editor draft, retained for reconciliation.
        let editorDraft: Data
        let storesLineGroups: Bool
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
                 actorID: String, organizationID: String, origin: String, jobID: String,
                 storesLineGroups: Bool) throws -> Record {
        let key = try scope(operation: operation, actorID: actorID, organizationID: organizationID,
                            origin: origin, jobID: jobID)
        return try store.withAttemptLock(scope: key) {
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
            guard try matches(draft: draft, operation: operation, storesLineGroups: storesLineGroups) else { throw Failure.invalidDraft }
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            let editorDraft = try encoder.encode(draft)
            let owner = UUID()
            guard store.acquire(scope: key, owner: owner) else { throw Failure.occupied }
            defer { store.release(scope: key, owner: owner) }
            let proposed = Record(operation: operation, editorDraft: editorDraft, storesLineGroups: storesLineGroups)
            if let existing = try store.load(Record.self, scope: key) {
                guard existing == proposed else { throw Failure.occupied }
                return existing
            }
            try store.createAttempt(proposed, scope: key)
            guard let saved = try store.load(Record.self, scope: key), saved == proposed else { throw Failure.unavailable }
            return saved
        }
    }

    private func matches(draft: CommercialNewEstimateDraft, operation: AtomicEstimateCommand, storesLineGroups: Bool) throws -> Bool {
        let lines = try draft.lines()
        // New-estimate UI uses MoneyInput (which disallows negative prices),
        // whereas the revision parser also accepts credits. Match the new path.
        guard lines.allSatisfy({ MoneyInput.cents($0.unitPrice) != nil }),
              storesLineGroups || lines.allSatisfy({ $0.group == .work && $0.showToCustomer }) else { return false }
        let inputs = try EstimateRevisionEditorState.makeLines(lines, storesGroups: storesLineGroups, extendedTextVerified: false)
        let request = FieldEstimateCreate(customerId: draft.customerID, title: draft.title,
                                          lines: inputs, locationId: operation.draftTarget?.locationID)
        let rebuilt = try AtomicEstimateCommand.fromBuilder(jobID: operation.payload.jobId, request: request,
            actorID: operation.actorID, organizationID: operation.organizationID, deviceID: operation.deviceID,
            policyVersion: operation.policyVersion, origin: operation.origin, createdAt: operation.createdAt,
            commandID: operation.commandID)
        return rebuilt == operation
    }

    /// Reopening requires the original actor, tenant, origin and exact job.
    /// A missing, malformed or differently scoped record cannot be treated as
    /// proof that a previous submission did not happen.
    func recover(actorID: String, organizationID: String, origin: String, jobID: String) throws -> Record? {
        guard [actorID, organizationID, jobID].allSatisfy({ UUID(uuidString: $0) != nil }) else { throw Failure.invalidScope }
        let key = CommercialDraftScope(actor: actorID.lowercased(), organization: organizationID.lowercased(),
                                       origin: origin, kind: "atomic-estimate-attempt", document: jobID.lowercased())
        return try store.withAttemptLock(scope: key) {
            let owner = UUID()
            guard store.acquire(scope: key, owner: owner) else { throw Failure.occupied }
            defer { store.release(scope: key, owner: owner) }
            guard let saved = try store.load(Record.self, scope: key) else { return nil }
            guard saved.operation.maySend(actorID: actorID, organizationID: organizationID, jobID: jobID,
                                          origin: origin, authorized: true), !saved.editorDraft.isEmpty else { throw Failure.unavailable }
            let draft = try JSONDecoder().decode(CommercialNewEstimateDraft.self, from: saved.editorDraft)
            guard try matches(draft: draft, operation: saved.operation, storesLineGroups: saved.storesLineGroups) else { throw Failure.unavailable }
            return saved
        }
    }
}
