import XCTest
@testable import Thorbis

final class BillingScheduleTests: XCTestCase {
    func testScheduleProgressDecodesAndTotals() throws {
        let json = #"{"schedule":{"id":"00000000-0000-4000-8000-000000009501","organizationId":"o","customerId":"c","jobId":"j","createdByUserId":"u","retainageRateBps":1000,"status":"open","lines":[{"id":"l1","position":0,"description":"Rough-in","scheduledAmount":{"amount":4000,"currency":"USD"}},{"id":"l2","position":1,"description":"Trim","scheduledAmount":{"amount":6000,"currency":"USD"}}],"createdAt":"2026-10-01T12:00:00Z","updatedAt":"2026-10-01T12:00:00Z"},"lines":[{"lineId":"l1","billedToDate":4000,"remaining":0},{"lineId":"l2","billedToDate":1000,"remaining":5000}],"invoiceIds":[],"retainedToDate":500,"releasedToDate":0,"retainageOutstanding":500,"depositsBilled":0,"depositCredited":0,"depositOutstanding":0,"readyToBill":true}"#
        let progress = try JSONDecoder().decode(BillingScheduleProgress.self, from: Data(json.utf8))
        XCTAssertEqual(progress.schedule.total, 10_000)
        XCTAssertEqual(progress.billedToDate, 5_000)
        XCTAssertEqual(progress.remaining, 5_000)
    }
}
