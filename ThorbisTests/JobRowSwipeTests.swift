import XCTest
@testable import Thorbis

/// What a job row's swipe offers: Call and Directions from the number and place the row has, and
/// the next move only when the server (or, offline, what it allowed before) permits it and the role
/// may move jobs. A full swipe only ever runs a forward, non-destructive step.
final class JobRowSwipeTests: XCTestCase {
    private let learned: [String: [String]] = ["en_route": ["arrived"], "dispatched": ["en_route"]]
    private func steps(_ status: String) -> [String] { learned[status] ?? [] }

    // MARK: Plan

    func testCallAndDirectionsNeedANumberAndAPlace() {
        let both = JobRowSwipePlan.make(phone: "(415) 555-0142", hasPlace: true, next: nil, canViewCustomer: true)
        XCTAssertEqual(both.leading, [.call, .directions])
        XCTAssertEqual(JobRowSwipePlan.make(phone: nil, hasPlace: true, next: nil, canViewCustomer: true).leading, [.directions])
        XCTAssertEqual(JobRowSwipePlan.make(phone: "(415) 555-0142", hasPlace: false, next: nil, canViewCustomer: true).leading, [.call])
        // Too short to dial is no number.
        XCTAssertEqual(JobRowSwipePlan.make(phone: "12", hasPlace: false, next: nil, canViewCustomer: true).leading, [])
    }

    func testARoleWithoutCustomerAccessGetsNoCallOrDirections() {
        let plan = JobRowSwipePlan.make(phone: "(415) 555-0142", hasPlace: true, next: "en_route", canViewCustomer: false)
        XCTAssertEqual(plan.leading, [])
        XCTAssertEqual(plan.trailing, [.move("en_route")])
    }

    func testTheNextMoveTrailsAndAFullSwipeRunsIt() {
        for step in ["en_route", "arrived", "in_progress"] {
            let plan = JobRowSwipePlan.make(phone: nil, hasPlace: false, next: step, canViewCustomer: true)
            XCTAssertEqual(plan.trailing, [.move(step)])
            XCTAssertEqual(plan.fullSwipe, .move(step))
        }
    }

    func testNoMoveShowsNothingOnTheTrailingSide() {
        let plan = JobRowSwipePlan.make(phone: "(415) 555-0142", hasPlace: true, next: nil, canViewCustomer: true)
        XCTAssertEqual(plan.trailing, [])
        XCTAssertNil(plan.fullSwipe)
    }

    func testAStopOrBackwardMoveIsNeverASwipe() {
        for step in ["paused", "completed", "canceled", "scheduled", "dispatched"] {
            let plan = JobRowSwipePlan.make(phone: nil, hasPlace: false, next: step, canViewCustomer: true)
            XCTAssertEqual(plan.trailing, [], step)
            XCTAssertNil(plan.fullSwipe, step)
        }
    }

    // MARK: Next move

    func testNextMoveFollowsWhatTheServerAllows() {
        func next(_ status: String, _ allowed: [String]) -> String? {
            JobMoves.next(listedStatus: status, served: (status, allowed), queued: nil, isOffline: false,
                          learned: steps, canEdit: true)
        }
        XCTAssertEqual(next("dispatched", ["en_route"]), "en_route")
        XCTAssertEqual(next("scheduled", ["arrived", "in_progress", "paused"]), "arrived")
        XCTAssertEqual(next("en_route", ["arrived"]), "arrived")
        XCTAssertEqual(next("arrived", ["in_progress", "paused"]), "in_progress")
        // Nothing forward allowed: nothing.
        XCTAssertNil(next("in_progress", ["arrived", "in_progress", "paused"]))
        XCTAssertNil(next("dispatched", []))
        XCTAssertNil(next("completed", []))
        // Resume needs the pause's own record, so a paused job offers no swipe.
        XCTAssertNil(next("paused", ["in_progress"]))
    }

    func testTheServersFreshStatusWinsOverTheListedOne() {
        // The list still says dispatched; the job as read is already en route.
        XCTAssertEqual(JobMoves.next(listedStatus: "dispatched", served: ("en_route", ["arrived"]), queued: nil,
                                     isOffline: false, learned: steps, canEdit: true), "arrived")
    }

    func testUnreadOnlineOffersNothingRatherThanGuessing() {
        XCTAssertNil(JobMoves.next(listedStatus: "dispatched", served: nil, queued: nil, isOffline: false,
                                   learned: steps, canEdit: true))
    }

    func testOfflineUsesOnlyWhatTheServerAllowedBefore() {
        XCTAssertEqual(JobMoves.next(listedStatus: "dispatched", served: nil, queued: nil, isOffline: true,
                                     learned: steps, canEdit: true), "en_route")
        XCTAssertNil(JobMoves.next(listedStatus: "arrived", served: nil, queued: nil, isOffline: true,
                                   learned: steps, canEdit: true), "Never learned from arrived: no move")
    }

    func testAQueuedStepChainsFromItself() {
        XCTAssertEqual(JobMoves.next(listedStatus: "dispatched", served: ("dispatched", ["en_route"]), queued: "en_route",
                                     isOffline: false, learned: steps, canEdit: true), "arrived")
    }

    func testARoleThatCannotEditJobsGetsNoMove() {
        XCTAssertNil(JobMoves.next(listedStatus: "dispatched", served: ("dispatched", ["en_route"]), queued: nil,
                                   isOffline: false, learned: steps, canEdit: false))
        let plan = JobRowSwipePlan.make(phone: "(415) 555-0142", hasPlace: true,
                                        next: JobMoves.next(listedStatus: "dispatched", served: ("dispatched", ["en_route"]),
                                                            queued: nil, isOffline: false, learned: steps, canEdit: false),
                                        canViewCustomer: true)
        XCTAssertEqual(plan.leading, [.call, .directions])
        XCTAssertEqual(plan.trailing, [])
        XCTAssertNil(plan.fullSwipe)
    }

    // MARK: The status popover's list (same source)

    func testAvailableMovesFilterByRole() {
        let served = ["en_route", "arrived", "in_progress", "paused", "scheduled", "completed", "canceled"]
        XCTAssertEqual(JobMoves.available(served: served, queued: nil, learned: steps, canEdit: true, canAssign: true),
                       ["en_route", "arrived", "in_progress", "paused", "scheduled"])
        XCTAssertEqual(JobMoves.available(served: served, queued: nil, learned: steps, canEdit: true, canAssign: false),
                       ["en_route", "arrived", "in_progress", "paused"])
        XCTAssertEqual(JobMoves.available(served: served, queued: nil, learned: steps, canEdit: false, canAssign: true),
                       ["scheduled"])
        // Queued: only forward steps the server allowed from the queued status before.
        XCTAssertEqual(JobMoves.available(served: served, queued: "en_route", learned: steps, canEdit: true, canAssign: true),
                       ["arrived"])
    }

    func testStepWordsMatchTheJobScreen() {
        XCTAssertEqual(JobMoves.title("en_route"), "On my way")
        XCTAssertEqual(JobMoves.title("arrived"), "Arrive")
        XCTAssertEqual(JobMoves.title("in_progress"), "Start work")
    }

    // MARK: Gesture thresholds

    func testSwipeSettling() {
        func settle(_ offset: CGFloat, _ velocity: CGFloat = 0, full: Bool = true) -> RowSwipeMotion.Settle {
            RowSwipeMotion.settle(offset: offset, velocity: velocity, leadingWidth: 168, trailingWidth: 84,
                                  rowWidth: 400, fullSwipe: full)
        }
        XCTAssertEqual(settle(30), .closed)
        XCTAssertEqual(settle(90), .leading)
        XCTAssertEqual(settle(30, 900), .leading, "A fling opens")
        XCTAssertEqual(settle(-30), .closed)
        XCTAssertEqual(settle(-50), .trailing)
        XCTAssertEqual(settle(-150), .trailing, "Past the cell but short of the full-swipe line")
        XCTAssertEqual(settle(-230), .fullSwipe)
        XCTAssertEqual(settle(-230, full: false), .trailing, "Without a full-swipe action it only opens")
        XCTAssertEqual(settle(-60, 900), .closed, "Flung back closes")
        XCTAssertEqual(RowSwipeMotion.settle(offset: -60, velocity: 0, leadingWidth: 0, trailingWidth: 0,
                                             rowWidth: 400, fullSwipe: false), .closed, "Nothing on that side")
    }
}
