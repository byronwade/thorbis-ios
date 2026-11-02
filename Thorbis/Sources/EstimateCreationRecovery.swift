import Foundation

/// Controls the two-step create and attach flow once the server has returned an estimate ID.
/// This does not resolve an interrupted create whose outcome is unknown.
struct EstimateCreationRecovery {
    let isSaving: Bool
    let savedEstimateID: String?
    let createOutcomeUncertain: Bool

    init(isSaving: Bool, savedEstimateID: String?, createOutcomeUncertain: Bool = false) {
        self.isSaving = isSaving
        self.savedEstimateID = savedEstimateID
        self.createOutcomeUncertain = createOutcomeUncertain
    }

    /// These client/server input or authorization rejections are definitive; other responses
    /// can follow a commit and must not enable another creation in this editor.
    static func isDefinitiveRejection(_ error: Error) -> Bool {
        guard let status = (error as? Problem)?.status else { return false }
        return [400, 403, 404, 409, 413, 422].contains(status)
    }

    var canEdit: Bool { !isSaving && savedEstimateID == nil }

    /// Verify the create response against the submitted scope and money, allowing the server
    /// to add line IDs, capture timestamps and original price-book snapshot metadata.
    static func matchesSubmittedTerms(_ request: FieldEstimateCreate, created: EstimateRecord) -> Bool {
        guard created.customerId == request.customerId, created.title == request.title,
              created.status == "draft", (created.options ?? []).isEmpty,
              created.lines.count == request.lines.count else { return false }
        return zip(request.lines, created.lines).allSatisfy { requested, saved in
            guard requested.description == saved.description, requested.quantity == saved.quantity,
                  requested.unitPrice == saved.unitPrice else { return false }
            if let group = requested.group, saved.group != group { return false }
            if let visible = requested.showToCustomer, (saved.showToCustomer ?? true) != visible { return false }
            switch requested.source ?? .manual {
            case .manual: return saved.source == nil || saved.source?.kind == "manual"
            case let .priceBookSelection(id, revision):
                return saved.source?.kind == "price_book" &&
                    saved.source?.priceBookItemId?.lowercased() == id.lowercased() &&
                    saved.source?.priceBookRevision == revision
            case .unsupported: return false
            }
        }
    }

    /// A fresh read must preserve the saved terms and identity. Storage can normalize record
    /// timestamps without changing what was saved, so those two metadata fields are excluded.
    static func matchesSavedEstimate(_ saved: EstimateRecord, latest: EstimateRecord) -> Bool {
        saved.id == latest.id && saved.organizationId == latest.organizationId &&
        saved.customerId == latest.customerId && saved.createdByUserId == latest.createdByUserId &&
        saved.locationId == latest.locationId && saved.status == latest.status &&
        saved.currentRevisionNumber == latest.currentRevisionNumber && saved.title == latest.title &&
        saved.lines == latest.lines && saved.options == latest.options && saved.sentAt == latest.sentAt &&
        saved.approvedAt == latest.approvedAt && saved.declinedAt == latest.declinedAt &&
        saved.approvalSignature == latest.approvalSignature
    }

    static func isExpectedLink(_ link: JobEstimateLink, jobID: String, estimateID: String) -> Bool {
        link.jobId == jobID && link.estimateId == estimateID
    }

    func mayProceed(validDraft: Bool) -> Bool {
        !isSaving && (savedEstimateID != nil || (!createOutcomeUncertain && validDraft))
    }
}

/// Identity and transport generation at submission; a saved result belongs only to this scope.
struct EstimateCreationScope: Equatable {
    let actorID: String
    let organizationID: String
    let sessionGeneration: UUID
    let authorityRevision: UUID
    let requestGeneration: UUID
    let origin: String

    /// Ordinary authority refresh may be rechecked, but never rebind to another session or tenant.
    func sameIdentityAndTransport(as other: Self) -> Bool {
        actorID == other.actorID && organizationID == other.organizationID &&
        sessionGeneration == other.sessionGeneration && requestGeneration == other.requestGeneration && origin == other.origin
    }
}
