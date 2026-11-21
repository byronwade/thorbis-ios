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

    static let createRefused = "You can\u{2019}t create estimates yet. Your office needs to turn this on."

    /// What to show when saving fails for sure. A 403 on the create itself gets plain words
    /// instead of the server's; everything else keeps its own message.
    static func refusalMessage(_ error: Error, creating: Bool) -> String {
        if creating, let problem = error as? Problem, problem.status == 403 { return createRefused }
        return error.localizedDescription
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
                  requested.unitPrice == saved.unitPrice || isMemberPriced(requested, saved: saved) else { return false }
            if (requested.showToCustomer ?? true) != (saved.showToCustomer ?? true) { return false }
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

    /// The server charges a member the member price for a price-book line sent at list price:
    /// it stores the lower price, marks `unit_price` overridden and keeps the list price as the
    /// original. That is the submitted line, not a different one.
    private static func isMemberPriced(_ requested: FieldEstimateLineInput, saved: FieldLine) -> Bool {
        guard case .priceBookSelection = requested.source ?? .manual, let source = saved.source,
              source.kind == "price_book", source.overriddenFields?.contains("unit_price") == true,
              source.originalUnitPrice == requested.unitPrice else { return false }
        return saved.unitPrice.currency == requested.unitPrice.currency &&
            saved.unitPrice.amount >= 0 && saved.unitPrice.amount < requested.unitPrice.amount
    }

    enum GroupResult { case preserved, missing, conflicting }

    static func groupResult(_ request: FieldEstimateCreate, created: EstimateRecord) -> GroupResult {
        guard request.lines.count == created.lines.count else { return .conflicting }
        var missing = false
        for (requested, saved) in zip(request.lines, created.lines) {
            guard let group = requested.group else { continue }
            guard let actual = saved.group else { missing = true; continue }
            if actual != group { return .conflicting }
        }
        return missing ? .missing : .preserved
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
