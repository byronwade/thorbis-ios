import XCTest
@testable import Thorbis

final class NeedsAttentionTests: XCTestCase {
    func testDraftsAreNotOwedButIssuedBalancesAre() throws {
        let draft = PaperPreview.invoice
        XCTAssertEqual(draft.status, "draft")
        XCTAssertTrue(NeedsAttention.unpaid([draft]).isEmpty)
        let issued = PaperPreview.issuedInvoice
        XCTAssertEqual(issued.status, "issued")
        XCTAssertEqual(NeedsAttention.unpaid([issued]).first?.1, 34_000)
    }

    func testEstimatesWaitAWeekBeforeTheyNeedAttention() {
        let sent = PaperPreview.estimate  // sent 2026-07-20
        let sentAt = JobFiltering.date(sent.sentAt)!
        XCTAssertTrue(NeedsAttention.waiting([sent], now: sentAt.addingTimeInterval(6 * 86_400)).isEmpty)
        XCTAssertEqual(NeedsAttention.waiting([sent], now: sentAt.addingTimeInterval(8 * 86_400)).count, 1)
    }

    func testJobsWithoutATimeExcludeFinishedWork() {
        let open = Job(id: "a", customerId: nil, title: "A", status: "scheduled", createdAt: nil, updatedAt: nil, allowedTransitions: nil)
        let done = Job(id: "b", customerId: nil, title: "B", status: "completed", createdAt: nil, updatedAt: nil, allowedTransitions: nil)
        var timed = open
        timed.scheduledFor = "2026-10-27T15:00:00Z"
        XCTAssertEqual(NeedsAttention.unscheduled([open, done, timed]).map(\.id), ["a"])
    }
}
