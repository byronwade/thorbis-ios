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
    struct LegacyRecord: Codable, Equatable {
        let attemptID: UUID
        let draftScope: CommercialDraftScope
        let customerID: String
        let locationID: String?
        let editorDraft: Data
        private enum CodingKeys: String, CodingKey { case attemptID, draftScope, customerID, locationID, editorDraft }
        init(attemptID: UUID, draftScope: CommercialDraftScope, customerID: String, locationID: String?, editorDraft: Data) {
            self.attemptID = attemptID; self.draftScope = draftScope; self.customerID = customerID
            self.locationID = locationID; self.editorDraft = editorDraft
        }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            attemptID = try values.decode(UUID.self, forKey: .attemptID)
            draftScope = try values.decode(CommercialDraftScope.self, forKey: .draftScope)
            customerID = try values.decode(String.self, forKey: .customerID)
            guard values.contains(.locationID) else { throw Failure.unavailable }
            locationID = try values.decodeIfPresent(String.self, forKey: .locationID)
            editorDraft = try values.decode(Data.self, forKey: .editorDraft)
        }
        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(attemptID, forKey: .attemptID); try values.encode(draftScope, forKey: .draftScope)
            try values.encode(customerID, forKey: .customerID); try values.encode(editorDraft, forKey: .editorDraft)
            if let locationID { try values.encode(locationID, forKey: .locationID) }
            else { try values.encodeNil(forKey: .locationID) }
        }
    }
    /// Pending means the attempt may or may not have reached the server.
    enum Status: Equatable { case missing, atomicPending(Record), legacyPending(LegacyRecord) }
    private enum Marker: Codable {
        case atomic(Record), legacy(LegacyRecord)
        private enum CodingKeys: String, CodingKey { case markerType, legacy }
        init(from decoder: Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            if fields.contains(.markerType) {
                guard try fields.decode(String.self, forKey: .markerType) == "legacy-v1" else { throw Failure.unavailable }
                self = .legacy(try fields.decode(LegacyRecord.self, forKey: .legacy))
            } else {
                // Existing held V1 records were stored directly, not wrapped.
                self = .atomic(try Record(from: decoder))
            }
        }
        func encode(to encoder: Encoder) throws {
            switch self {
            case .atomic(let record): try record.encode(to: encoder)
            case .legacy(let record):
                var fields = encoder.container(keyedBy: CodingKeys.self)
                try fields.encode("legacy-v1", forKey: .markerType)
                try fields.encode(record, forKey: .legacy)
            }
        }
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
            guard let target = operation.draftTarget, store.isCoordinatedOwner(scope: draftScope, owner: draftOwner),
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
            if let marker = try store.load(Marker.self, scope: key) {
                guard case .atomic(let existing) = marker, existing == proposed else { throw Failure.occupied }
                return existing
            }
            try store.createAttempt(Marker.atomic(proposed), scope: key)
            guard case .atomic(let saved)? = try store.load(Marker.self, scope: key), saved == proposed else { throw Failure.unavailable }
            return saved
        }
    }

    private func key(actorID: String, organizationID: String, origin: String, jobID: String) throws -> CommercialDraftScope {
        guard [actorID, organizationID, jobID].allSatisfy({ UUID(uuidString: $0) != nil }),
              AtomicEstimateCommand.validOrigin(origin) else { throw Failure.invalidScope }
        return .init(actor: actorID.lowercased(), organization: organizationID.lowercased(), origin: origin,
                     kind: "atomic-estimate-attempt", document: jobID.lowercased())
    }

    /// Reserve the shared slot before any legacy create. No result is known;
    /// this record cannot be automatically cleared or treated as a success.
    func stageLegacy(draftScope: CommercialDraftScope, draftOwner: UUID, actorID: String,
                     organizationID: String, origin: String, jobID: String, customerID: String,
                     locationID: String?, attemptID: UUID) throws -> LegacyRecord {
        let key = try key(actorID: actorID, organizationID: organizationID, origin: origin, jobID: jobID)
        guard UUID(uuidString: customerID) != nil, locationID.map({ UUID(uuidString: $0) != nil }) ?? true else { throw Failure.invalidScope }
        return try store.withAttemptLock(scope: key) {
            guard store.isCoordinatedOwner(scope: draftScope, owner: draftOwner), draftScope.kind == "new-estimate",
                  draftScope.actor.lowercased() == key.actor, draftScope.organization.lowercased() == key.organization,
                  draftScope.origin == key.origin,
                  draftScope.document.lowercased() == "job:\(key.document)|customer:\(customerID.lowercased())|location:\(locationID?.lowercased() ?? "")",
                  let draft = try store.load(CommercialNewEstimateDraft.self, scope: draftScope),
                  draft.customerID.lowercased() == customerID.lowercased(), draft.created == nil,
                  !draft.uncertain, draft.atomicOperation == nil, !draft.requiresManualReview,
                  !draft.requiresLocationVerification, !draft.requiresGroupDisclosure else { throw Failure.invalidDraft }
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            let proposed = LegacyRecord(attemptID: attemptID, draftScope: draftScope, customerID: customerID.lowercased(),
                                        locationID: locationID?.lowercased(), editorDraft: try encoder.encode(draft))
            // Even the same local ID may already have been sent. Never return
            // a second send permit from an unresolved legacy marker.
            if let _ = try store.load(Marker.self, scope: key) { throw Failure.occupied }
            try store.createAttempt(Marker.legacy(proposed), scope: key)
            guard case .legacy(let saved)? = try store.load(Marker.self, scope: key), saved == proposed else { throw Failure.unavailable }
            return saved
        }
    }

    /// Missing is only a local observation, not proof of no prior server write.
    func status(actorID: String, organizationID: String, origin: String, jobID: String) throws -> Status {
        let key = try key(actorID: actorID, organizationID: organizationID, origin: origin, jobID: jobID)
        return try store.withAttemptLock(scope: key) {
            guard let marker = try store.load(Marker.self, scope: key) else { return .missing }
            switch marker {
            case .atomic(let record):
                guard record.operation.maySend(actorID: actorID, organizationID: organizationID, jobID: jobID, origin: origin, authorized: true),
                      !record.editorDraft.isEmpty else { throw Failure.unavailable }
                let draft = try JSONDecoder().decode(CommercialNewEstimateDraft.self, from: record.editorDraft)
                guard try matches(draft: draft, operation: record.operation, storesLineGroups: record.storesLineGroups) else { throw Failure.unavailable }
                return .atomicPending(record)
            case .legacy(let record):
                guard UUID(uuidString: record.customerID) != nil, record.customerID == record.customerID.lowercased(),
                      record.locationID.map({ UUID(uuidString: $0) != nil && $0 == $0.lowercased() }) ?? true,
                      record.draftScope.actor.lowercased() == key.actor, record.draftScope.organization.lowercased() == key.organization,
                      record.draftScope.origin == key.origin, record.draftScope.kind == "new-estimate",
                      record.draftScope.document.lowercased() == "job:\(key.document)|customer:\(record.customerID.lowercased())|location:\(record.locationID?.lowercased() ?? "")" else { throw Failure.unavailable }
                let draft = try JSONDecoder().decode(CommercialNewEstimateDraft.self, from: record.editorDraft)
                guard draft.customerID.lowercased() == record.customerID.lowercased(), draft.created == nil,
                      !draft.uncertain, draft.atomicOperation == nil, !draft.requiresManualReview,
                      !draft.requiresLocationVerification, !draft.requiresGroupDisclosure else { throw Failure.unavailable }
                return .legacyPending(record)
            }
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
        switch try status(actorID: actorID, organizationID: organizationID, origin: origin, jobID: jobID) {
        case .missing: return nil
        case .atomicPending(let record): return record
        case .legacyPending: throw Failure.occupied
        }
    }
}
