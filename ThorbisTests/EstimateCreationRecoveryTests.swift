import XCTest
@testable import Thorbis

final class EstimateCreationRecoveryTests: XCTestCase {
    func testSubmittingLocksEditingUntilTheResultIsKnown() {
        let pending = EstimateCreationRecovery(isSaving: true, savedEstimateID: nil)
        XCTAssertFalse(pending.canEdit)
        XCTAssertFalse(pending.mayProceed(validDraft: true))
    }

    func testSavedEstimateIsLockedAndLinkCanRetryWithoutRevalidatingDraft() {
        let saved = EstimateCreationRecovery(isSaving: false, savedEstimateID: "saved-estimate")
        XCTAssertFalse(saved.canEdit)
        XCTAssertTrue(saved.mayProceed(validDraft: false))
    }

    func testUnsavedEstimateRemainsEditableAndRequiresAValidDraft() {
        let draft = EstimateCreationRecovery(isSaving: false, savedEstimateID: nil)
        XCTAssertTrue(draft.canEdit)
        XCTAssertFalse(draft.mayProceed(validDraft: false))
        XCTAssertTrue(draft.mayProceed(validDraft: true))
    }
}

extension EstimateCreationRecoveryTests {
    func testUncertainCreateKeepsTextEditableButBlocksAnotherCreate() {
        let uncertain = EstimateCreationRecovery(isSaving: false, savedEstimateID: nil, createOutcomeUncertain: true)
        XCTAssertTrue(uncertain.canEdit)
        XCTAssertFalse(uncertain.mayProceed(validDraft: true))
    }

    func testOnlyExplicitInputRejectionsAllowAnotherAttempt() {
        XCTAssertTrue(EstimateCreationRecovery.isDefinitiveRejection(Problem(title: "Invalid", status: 422, detail: nil)))
        XCTAssertFalse(EstimateCreationRecovery.isDefinitiveRejection(Problem(title: "Network error", status: nil, detail: nil)))
        XCTAssertFalse(EstimateCreationRecovery.isDefinitiveRejection(Problem(title: "Invalid API response", status: 201, detail: nil)))
        XCTAssertFalse(EstimateCreationRecovery.isDefinitiveRejection(Problem(title: "Server error", status: 500, detail: nil)))
    }

    func testOnlyTheRequestedJobAndEstimateConfirmTheLink() {
        let correct = JobEstimateLink(id: "link", jobId: "job", estimateId: "estimate", linkedAt: nil)
        let wrongJob = JobEstimateLink(id: "link", jobId: "other-job", estimateId: "estimate", linkedAt: nil)
        let wrongEstimate = JobEstimateLink(id: "link", jobId: "job", estimateId: "other-estimate", linkedAt: nil)
        XCTAssertTrue(EstimateCreationRecovery.isExpectedLink(correct, jobID: "job", estimateID: "estimate"))
        XCTAssertFalse(EstimateCreationRecovery.isExpectedLink(wrongJob, jobID: "job", estimateID: "estimate"))
        XCTAssertFalse(EstimateCreationRecovery.isExpectedLink(wrongEstimate, jobID: "job", estimateID: "estimate"))
    }

    func testScopeRejectsChangedIdentitySessionTransportOrOrigin() {
        let session = UUID(), authority = UUID(), request = UUID()
        let original = EstimateCreationScope(actorID: "actor", organizationID: "org", sessionGeneration: session, authorityRevision: authority,
                                             requestGeneration: request, origin: "https://app.thorbis.com")
        XCTAssertNotEqual(original, .init(actorID: "other", organizationID: "org", sessionGeneration: session, authorityRevision: authority, requestGeneration: request, origin: original.origin))
        XCTAssertNotEqual(original, .init(actorID: "actor", organizationID: "other", sessionGeneration: session, authorityRevision: authority, requestGeneration: request, origin: original.origin))
        XCTAssertNotEqual(original, .init(actorID: "actor", organizationID: "org", sessionGeneration: UUID(), authorityRevision: authority, requestGeneration: request, origin: original.origin))
        let refreshed = EstimateCreationScope(actorID: "actor", organizationID: "org", sessionGeneration: session, authorityRevision: UUID(), requestGeneration: request, origin: original.origin)
        XCTAssertNotEqual(original, refreshed)
        XCTAssertTrue(original.sameIdentityAndTransport(as: refreshed))
        let otherOrganization = EstimateCreationScope(actorID: "actor", organizationID: "other", sessionGeneration: session, authorityRevision: authority, requestGeneration: request, origin: original.origin)
        XCTAssertFalse(original.sameIdentityAndTransport(as: otherOrganization))
        XCTAssertNotEqual(original, .init(actorID: "actor", organizationID: "org", sessionGeneration: session, authorityRevision: authority, requestGeneration: UUID(), origin: original.origin))
        XCTAssertNotEqual(original, .init(actorID: "actor", organizationID: "org", sessionGeneration: session, authorityRevision: authority, requestGeneration: request, origin: "https://other.example"))
    }
}
