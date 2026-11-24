import XCTest
@testable import Thorbis

/// One signature, several estimates (Paper 38C): the order, the stop, the retry and the ink's lifetime.
@MainActor
final class JobEstimateBatchApprovalTests: XCTestCase {
    private let capture = JobEstimateBatchApproval.Capture(signerName: "Sample Customer", png: Data([1, 2, 3]))

    func testAllSucceedInOrderWithTheSameCapturedSignature() async {
        let batch = JobEstimateBatchApproval(order: ["a", "b", "c"], capture: capture)
        var calls: [String] = []
        await batch.run(stillCurrent: { true }) { key, used in
            XCTAssertEqual(used, self.capture)
            calls.append(key); return .approved
        }
        XCTAssertEqual(calls, ["a", "b", "c"])
        XCTAssertEqual(batch.approvedKeys, ["a", "b", "c"])
        XCTAssertTrue(batch.isComplete)
        XCTAssertNil(batch.stopReason)
        XCTAssertFalse(batch.canRetry)
    }

    func testSecondFailureKeepsFirstApprovedAndNeverAttemptsThird() async {
        let batch = JobEstimateBatchApproval(order: ["a", "b", "c"], capture: capture)
        var calls: [String] = []
        await batch.run(stillCurrent: { true }) { key, _ in
            calls.append(key); return key == "b" ? .stopped("Connection lost") : .approved
        }
        XCTAssertEqual(calls, ["a", "b"])
        XCTAssertEqual(batch.states["a"], .approved)
        XCTAssertEqual(batch.states["b"], .stopped("Connection lost"))
        XCTAssertEqual(batch.states["c"], .notAttempted)
        XCTAssertEqual(batch.stopReason, "Connection lost")
        XCTAssertEqual(batch.remainingKeys, ["b", "c"])
        XCTAssertTrue(batch.canRetry)
    }

    func testRetryApprovesOnlyTheRemainingAndNeverTheApprovedOneAgain() async {
        let batch = JobEstimateBatchApproval(order: ["a", "b", "c"], capture: capture)
        var failSecond = true
        var calls: [String] = []
        let approveOne: @MainActor (String, JobEstimateBatchApproval.Capture) async -> JobEstimateBatchApproval.Step = { key, _ in
            calls.append(key)
            if key == "b", failSecond { failSecond = false; return .stopped("Interrupted") }
            return .approved
        }
        await batch.run(stillCurrent: { true }, approveOne: approveOne)
        await batch.run(stillCurrent: { true }, approveOne: approveOne)
        XCTAssertEqual(calls, ["a", "b", "b", "c"], "The retry starts at the failed estimate and never resends the approved one")
        XCTAssertEqual(calls.filter { $0 == "a" }.count, 1)
        XCTAssertTrue(batch.isComplete)
        // Once everything is approved, another run sends nothing.
        await batch.run(stillCurrent: { true }, approveOne: approveOne)
        XCTAssertEqual(calls.count, 4)
    }

    func testSessionOrAuthorityChangeMidwayStopsBeforeTheNextAndForgetsTheInk() async {
        let batch = JobEstimateBatchApproval(order: ["a", "b", "c"], capture: capture)
        var current = true
        var calls: [String] = []
        await batch.run(stillCurrent: { current }) { key, _ in
            calls.append(key); current = false; return .approved
        }
        XCTAssertEqual(calls, ["a"])
        XCTAssertEqual(batch.states["a"], .approved, "A server-confirmed approval stays shown as approved")
        XCTAssertEqual(batch.states["b"], .notAttempted)
        XCTAssertEqual(batch.states["c"], .notAttempted)
        XCTAssertNotNil(batch.stopReason)
        XCTAssertNil(batch.capture)
        XCTAssertFalse(batch.canRetry)
        await batch.run(stillCurrent: { true }) { key, _ in calls.append(key); return .approved }
        XCTAssertEqual(calls, ["a"], "Without the captured ink nothing more is approved")
    }

    func testNoAccessBeforeTheFirstSendsNothing() async {
        let batch = JobEstimateBatchApproval(order: ["a", "b"], capture: capture)
        var calls = 0
        await batch.run(stillCurrent: { false }) { _, _ in calls += 1; return .approved }
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(batch.states["a"], .notAttempted)
        XCTAssertEqual(batch.states["b"], .notAttempted)
    }

    func testDiscardOnLeaveOrHandBackPreventsAnyRetry() async {
        let batch = JobEstimateBatchApproval(order: ["a", "b"], capture: capture)
        var calls: [String] = []
        await batch.run(stillCurrent: { true }) { key, _ in calls.append(key); return key == "a" ? .approved : .stopped("Interrupted") }
        XCTAssertTrue(batch.canRetry)
        batch.discard()
        XCTAssertNil(batch.capture)
        XCTAssertFalse(batch.canRetry)
        await batch.run(stillCurrent: { true }) { key, _ in calls.append(key); return .approved }
        XCTAssertEqual(calls, ["a", "b"])
        XCTAssertEqual(batch.states["b"], .stopped("Interrupted"))
    }

    func testDiscardDuringARunStopsBeforeTheNextEstimate() async {
        let batch = JobEstimateBatchApproval(order: ["a", "b"], capture: capture)
        var calls: [String] = []
        await batch.run(stillCurrent: { true }) { key, _ in
            calls.append(key); batch.discard(); return .approved
        }
        XCTAssertEqual(calls, ["a"])
        XCTAssertEqual(batch.states["b"], .notAttempted)
    }
}
