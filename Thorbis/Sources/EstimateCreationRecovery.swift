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
