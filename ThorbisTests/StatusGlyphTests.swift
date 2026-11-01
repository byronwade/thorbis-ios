import XCTest
@testable import Thorbis

final class StatusGlyphTests: XCTestCase {
    func testEveryJobStatusMapsToALinearRing() {
        XCTAssertEqual(StatusTone(jobStatus: "draft"), .unscheduled)
        XCTAssertEqual(StatusTone(jobStatus: "scheduled"), .scheduled)
        XCTAssertEqual(StatusTone(jobStatus: "scheduled", hasTime: false), .unscheduled)
        XCTAssertEqual(StatusTone(jobStatus: "dispatched"), .dispatched)
        XCTAssertEqual(StatusTone(jobStatus: "en_route"), .dispatched)
        XCTAssertEqual(StatusTone(jobStatus: "arrived"), .inProgress)
        XCTAssertEqual(StatusTone(jobStatus: "in_progress"), .inProgress)
        XCTAssertEqual(StatusTone(jobStatus: "paused"), .inProgress)
        XCTAssertEqual(StatusTone(jobStatus: "completed"), .done)
        XCTAssertEqual(StatusTone(jobStatus: "canceled"), .cancelled)
    }

    func testRingFillsInLinearOrder() {
        XCTAssertEqual(StatusTone.unscheduled.fill, 0)
        XCTAssertEqual(StatusTone.scheduled.fill, 0)
        XCTAssertEqual(StatusTone.dispatched.fill, 0.25)
        XCTAssertEqual(StatusTone.inProgress.fill, 0.5)
        XCTAssertEqual(StatusTone.done.fill, 1)
        XCTAssertEqual(StatusTone.done.mark, "checkmark")
        XCTAssertEqual(StatusTone.cancelled.mark, "xmark")
        XCTAssertEqual(StatusTone.attention.mark, "exclamationmark")
    }
}
