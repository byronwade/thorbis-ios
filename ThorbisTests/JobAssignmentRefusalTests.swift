import XCTest
@testable import Thorbis

/// The assign sheet's words for a refused assignment (POST /v1/jobs/{id}/assign answering 409).
@MainActor
final class JobAssignmentRefusalTests: XCTestCase {
    private func conflict(detail: String?, code: String? = nil) -> Problem {
        Problem(title: "conflict", status: 409, detail: detail, code: code, category: "conflict")
    }

    func testChangedAssigneeSaysTheAssignmentChanged() {
        let problem = conflict(detail: "the job's assignment changed since it was loaded; refresh to see the latest",
                               code: "dispatch_changed")
        XCTAssertEqual(JobAssignmentRefusal.message(for: problem), JobAssignmentRefusal.assignmentChanged)
    }

    func testCompletedJobSaysItCanNoLongerBeAssigned() {
        let message = JobAssignmentRefusal.message(for: conflict(detail: "cannot assign job in status completed"))
        XCTAssertEqual(message, JobAssignmentRefusal.completed)
        XCTAssertNotEqual(message, JobAssignmentRefusal.assignmentChanged)
    }

    func testCanceledJobSaysItCanNoLongerBeAssigned() {
        let message = JobAssignmentRefusal.message(for: conflict(detail: "cannot assign job in status canceled"))
        XCTAssertEqual(message, JobAssignmentRefusal.canceled)
        XCTAssertNotEqual(message, JobAssignmentRefusal.assignmentChanged)
    }

    func testOtherConflictWithNoCodeShowsTheServersReason() {
        let message = JobAssignmentRefusal.message(for: conflict(detail: "the job is locked for billing"))
        XCTAssertEqual(message, "the job is locked for billing")
    }

    func testOtherCodeShowsTheServersReasonNotTheChangedText() {
        let problem = conflict(detail: "cannot assign job in status completed", code: "some_other_code")
        XCTAssertEqual(JobAssignmentRefusal.message(for: problem), "cannot assign job in status completed")
    }

    func testConflictWithNoDetailFallsBackToTheTitle() {
        XCTAssertEqual(JobAssignmentRefusal.message(for: conflict(detail: nil)), "conflict")
    }

    // The dispatch board moves a job through the same route.

    func testBoardKeepsItsWordsForATechSomeoneElseChanged() {
        let problem = conflict(detail: "the job's assignment changed since it was loaded; refresh to see the latest",
                               code: "dispatch_changed")
        XCTAssertEqual(JobAssignmentRefusal.boardMessage(for: problem), JobAssignmentRefusal.boardChanged)
    }

    func testBoardSaysAClosedJobCannotBeAssigned() {
        XCTAssertEqual(JobAssignmentRefusal.boardMessage(for: conflict(detail: "cannot assign job in status completed")),
                       JobAssignmentRefusal.completed)
        XCTAssertEqual(JobAssignmentRefusal.boardMessage(for: conflict(detail: "cannot assign job in status canceled")),
                       JobAssignmentRefusal.canceled)
    }

    func testBoardShowsTheServersReasonForAnyOtherConflict() {
        XCTAssertEqual(JobAssignmentRefusal.boardMessage(for: conflict(detail: "the job is locked for billing")),
                       "the job is locked for billing")
    }
}
