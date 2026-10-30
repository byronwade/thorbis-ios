import XCTest
@testable import Thorbis

/// The iPad Schedule detail pane keeps its state (chosen invoice, open screens) while the job
/// list refreshes, and starts fresh only when a different job is chosen.
final class TabletScheduleDetailTests: XCTestCase {
    private func job(_ id: String, status: String, updatedAt: String) -> Job {
        Job(id: id, customerId: "c", title: "AC not cooling", status: status,
            createdAt: "2026-10-30T12:00:00Z", updatedAt: updatedAt, allowedTransitions: ["en_route"])
    }

    func testRefreshedJobKeepsTheSameDetailIdentity() {
        let before = job("job-1", status: "dispatched", updatedAt: "2026-10-30T12:00:00Z")
        let after = job("job-1", status: "in_progress", updatedAt: "2026-10-30T12:05:00Z")

        // A refresh changes the Job value, which is why keying the pane on `Job` rebuilt it
        // and dropped the selected invoice.
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(PaperTabletSchedule.detailIdentity(before), PaperTabletSchedule.detailIdentity(after))
    }

    func testChoosingAnotherJobChangesTheDetailIdentity() {
        let first = job("job-1", status: "dispatched", updatedAt: "2026-10-30T12:00:00Z")
        let second = job("job-2", status: "dispatched", updatedAt: "2026-10-30T12:00:00Z")

        XCTAssertNotEqual(PaperTabletSchedule.detailIdentity(first), PaperTabletSchedule.detailIdentity(second))
    }
}
