import XCTest
@testable import Thorbis

final class JobPrimaryActionTests: XCTestCase {
    func testInProgressOffersTheChecklistInsteadOfPauseOrAnEarlierStep() {
        XCTAssertEqual(
            JobPrimaryAction.resolve(status: "in_progress", allowedTransitions: ["paused", "arrived"], canEdit: true),
            .wrapUp
        )
    }

    func testForwardActionUsesLifecycleOrderRatherThanServerArrayOrder() {
        XCTAssertEqual(
            JobPrimaryAction.resolve(status: "dispatched", allowedTransitions: ["paused", "in_progress", "arrived", "en_route"], canEdit: true),
            .progress("en_route")
        )
    }

    func testAnEarlierOrRepeatedStepIsNeverThePrimaryAction() {
        XCTAssertEqual(
            JobPrimaryAction.resolve(status: "arrived", allowedTransitions: ["en_route", "arrived", "in_progress"], canEdit: true),
            .progress("in_progress")
        )
        XCTAssertNil(JobPrimaryAction.resolve(status: "en_route", allowedTransitions: ["en_route", "scheduled"], canEdit: true))
    }

    func testNoAllowedForwardStepDoesNotInventAMutation() {
        XCTAssertNil(JobPrimaryAction.resolve(status: "dispatched", allowedTransitions: [], canEdit: true))
        XCTAssertNil(JobPrimaryAction.resolve(status: "dispatched", allowedTransitions: ["paused", "scheduled"], canEdit: true))
    }

    func testEditPermissionIsRequiredForFieldProgressAndWrapUp() {
        XCTAssertNil(JobPrimaryAction.resolve(status: "dispatched", allowedTransitions: ["en_route"], canEdit: false))
        XCTAssertNil(JobPrimaryAction.resolve(status: "in_progress", allowedTransitions: ["paused"], canEdit: false))
    }

    func testDispatchNeedsAssignmentPermissionAndServerAllowance() {
        XCTAssertEqual(
            JobPrimaryAction.resolve(status: "scheduled", allowedTransitions: ["en_route", "dispatched"], canEdit: true, canAssign: true),
            .progress("dispatched")
        )
        XCTAssertEqual(
            JobPrimaryAction.resolve(status: "scheduled", allowedTransitions: ["dispatched"], canEdit: false, canAssign: true),
            .progress("dispatched")
        )
        XCTAssertNil(JobPrimaryAction.resolve(status: "scheduled", allowedTransitions: ["dispatched"], canEdit: true))
        XCTAssertNil(JobPrimaryAction.resolve(status: "scheduled", allowedTransitions: [], canEdit: false, canAssign: true))
    }

    func testResumeNeedsServerAllowanceAndASurfaceThatHandlesPauseEvidence() {
        XCTAssertEqual(
            JobPrimaryAction.resolve(status: "paused", allowedTransitions: ["in_progress"], canEdit: true, canResume: true),
            .progress("in_progress")
        )
        XCTAssertNil(JobPrimaryAction.resolve(status: "paused", allowedTransitions: ["in_progress"], canEdit: true))
        XCTAssertNil(JobPrimaryAction.resolve(status: "paused", allowedTransitions: [], canEdit: true, canResume: true))
        XCTAssertNil(JobPrimaryAction.resolve(status: "paused", allowedTransitions: ["in_progress"], canEdit: false, canResume: true))
    }

    func testFinalAndUnknownStatusesOfferNoPrimaryMutation() {
        for status in ["completed", "canceled", "unknown"] {
            XCTAssertNil(JobPrimaryAction.resolve(status: status, allowedTransitions: ["en_route", "in_progress", "dispatched"], canEdit: true, canAssign: true, canResume: true))
        }
    }
}
