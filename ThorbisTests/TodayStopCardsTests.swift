import XCTest
@testable import Thorbis

final class TodayStopCardsTests: XCTestCase {
    private func job(_ id: String, _ status: String, _ time: String?) -> Job {
        Job(id: id, customerId: "c", title: id, status: status,
            createdAt: nil, updatedAt: nil, allowedTransitions: nil, scheduledFor: time)
    }
    private let plain: (Job) -> String = { $0.status }

    func testAllBookedOpensOnTheFirstStopInTimeOrder() {
        let stops = TodayStopOrder.ordered([job("b", "scheduled", "2026-10-31T14:00:00Z"),
                                            job("a", "dispatched", "2026-10-31T09:00:00Z")], status: plain)
        XCTAssertEqual(stops.map(\.id), ["a", "b"])
        XCTAssertEqual(TodayStopOrder.startIndex(stops, status: plain), 0)
    }

    func testDoneStopsSitLeftAndTheStopUnderWayLeads() {
        let stops = TodayStopOrder.ordered([
            job("noon", "scheduled", "2026-10-31T12:00:00Z"),
            job("early", "completed", "2026-10-31T08:00:00Z"),
            job("ten", "dispatched", "2026-10-31T10:00:00Z"),
            job("one", "in_progress", "2026-10-31T13:00:00Z"),
            job("gone", "canceled", "2026-10-31T11:00:00Z")
        ], status: plain)
        XCTAssertEqual(stops.map(\.id), ["early", "ten", "noon", "one"])
        // On a job now: that stop, even though an earlier booked slot is still open.
        XCTAssertEqual(TodayStopOrder.startIndex(stops, status: plain), 3)
    }

    func testAStopFinishedOutOfOrderMovesLeft() {
        let stops = TodayStopOrder.ordered([
            job("nine", "scheduled", "2026-10-31T09:00:00Z"),
            job("two", "completed", "2026-10-31T14:00:00Z"),
            job("noon", "completed", "2026-10-31T12:00:00Z")
        ], status: plain)
        XCTAssertEqual(stops.map(\.id), ["noon", "two", "nine"])
        XCTAssertEqual(TodayStopOrder.startIndex(stops, status: plain), 2)
    }

    func testEveryStopDoneOpensOnTheLastAndEmptyHasNoStart() {
        let stops = TodayStopOrder.ordered([job("a", "completed", "2026-10-31T09:00:00Z"),
                                            job("b", "completed", "2026-10-31T11:00:00Z")], status: plain)
        XCTAssertEqual(TodayStopOrder.startIndex(stops, status: plain), 1)
        XCTAssertNil(TodayStopOrder.startIndex([], status: plain))
    }

    func testUntimedStopsGoLastAndKeepTheirOrder() {
        let stops = TodayStopOrder.ordered([job("x", "scheduled", nil), job("y", "scheduled", nil),
                                            job("a", "scheduled", "2026-10-31T09:00:00Z")], status: plain)
        XCTAssertEqual(stops.map(\.id), ["a", "x", "y"])
    }

    func testAQueuedStepCountsAsTheStatusShown() {
        let jobs = [job("a", "dispatched", "2026-10-31T09:00:00Z"), job("b", "dispatched", "2026-10-31T10:00:00Z")]
        // Offline, "On my way" was queued for b: it is the stop under way.
        let queued: (Job) -> String = { $0.id == "b" ? "en_route" : $0.status }
        let stops = TodayStopOrder.ordered(jobs, status: queued)
        XCTAssertEqual(TodayStopOrder.startIndex(stops, status: queued), 1)
        // A queued finish moves the stop to the done side.
        let finished: (Job) -> String = { $0.id == "a" ? "completed" : $0.status }
        XCTAssertEqual(TodayStopOrder.ordered(jobs, status: finished).map(\.id), ["a", "b"])
        XCTAssertEqual(TodayStopOrder.startIndex(TodayStopOrder.ordered(jobs, status: finished), status: finished), 1)
    }

    func testWordsForTheCardAndVoiceOver() {
        XCTAssertEqual(TodayStopOrder.position(index: 1, total: 6, time: "10:30"), "Stop 2 of 6 · 10:30")
        XCTAssertEqual(TodayStopOrder.position(index: 0, total: 1, time: nil), "Stop 1 of 1")
        XCTAssertEqual(TodayStopOrder.spoken(index: 1, total: 6, place: "412 Birchwood Ln", status: "Dispatched", time: "10:30"),
                       "Stop 2 of 6, 412 Birchwood Ln, Dispatched, 10:30")
    }

    func testDotsOnlyForShortDays() {
        XCTAssertFalse(TodayStopOrder.showsDots(total: 1))
        XCTAssertTrue(TodayStopOrder.showsDots(total: 2))
        XCTAssertTrue(TodayStopOrder.showsDots(total: 8))
        XCTAssertFalse(TodayStopOrder.showsDots(total: 9))
    }

    func testLayoutDefaultsByRoleAndKeepsTheChoice() {
        XCTAssertEqual(TodayLayoutMode.resolve(stored: "", schedulesOwnDay: true), .cards)
        XCTAssertEqual(TodayLayoutMode.resolve(stored: "", schedulesOwnDay: false), .list)
        XCTAssertEqual(TodayLayoutMode.resolve(stored: "list", schedulesOwnDay: true), .list)
        XCTAssertEqual(TodayLayoutMode.resolve(stored: "cards", schedulesOwnDay: false), .cards)
        XCTAssertEqual(TodayLayoutMode.resolve(stored: "junk", schedulesOwnDay: true), .cards)
        XCTAssertEqual(TodayLayoutMode.cards.toggled, .list)
    }

    func testAccessLineShowsArrivalFactsButNeverTheAlarmCode() {
        func place(gate: String?, alarm: String?, dog: String?, parking: String?) -> ServiceLocationRecord {
            ServiceLocationRecord(id: "l", organizationId: "o", customerId: "c", label: "Home", kind: "service",
                                  address: "412 Birchwood Ln", notes: "Side door", coordinates: nil, gateCode: gate,
                                  alarmCode: alarm, dogOnSite: dog, parking: parking, createdAt: "", updatedAt: "")
        }
        XCTAssertEqual(TodayStopAccess.line(place(gate: "4417", alarm: "7350", dog: "In backyard", parking: nil)),
                       "Gate 4417 · Dog: In backyard")
        XCTAssertNil(TodayStopAccess.line(place(gate: " ", alarm: "7350", dog: nil, parking: nil)))
        XCTAssertEqual(TodayStopAccess.line(place(gate: nil, alarm: nil, dog: nil, parking: "Driveway")), "Parking: Driveway")
    }
}
