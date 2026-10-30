import XCTest
@testable import Thorbis

final class JobFilteringTests: XCTestCase {
    func testNextCustomerVisitUsesEarliestUpcomingScheduledJobForThatCustomer() {
        let now = ISO8601DateFormatter().date(from: "2026-10-29T12:00:00Z")!
        func customerJob(_ id: String, customer: String, time: String?, status: String = "scheduled") -> Job {
            var job = Job(id: id, customerId: customer, title: id, status: status,
                          createdAt: nil, updatedAt: nil, allowedTransitions: nil)
            job.scheduledFor = time
            return job
        }
        let jobs = [
            customerJob("later", customer: "c1", time: "2026-10-31T12:00:00Z"),
            customerJob("other", customer: "c2", time: "2026-10-29T12:30:00Z"),
            customerJob("past", customer: "c1", time: "2026-10-29T11:00:00Z"),
            customerJob("canceled", customer: "c1", time: "2026-10-29T13:00:00Z", status: "canceled"),
            customerJob("completed", customer: "c1", time: "2026-10-29T13:00:00Z", status: "completed"),
            customerJob("unscheduled", customer: "c1", time: nil),
            customerJob("unknown", customer: "c1", time: "invalid"),
            customerJob("soonest", customer: "c1", time: "2026-10-30T12:00:00Z")
        ]
        XCTAssertEqual(JobFiltering.nextScheduledVisit(jobs, customerID: "c1", now: now)?.id, "soonest")
        XCTAssertNil(JobFiltering.nextScheduledVisit(jobs, customerID: "missing", now: now))
    }

    func testNextCustomerVisitUsesStableIDToBreakTimeTies() {
        let now = ISO8601DateFormatter().date(from: "2026-10-29T12:00:00Z")!
        var first = makeJob("b", time: "2026-10-30T12:00:00Z")
        first = Job(id: first.id, customerId: "c", title: first.title, status: first.status,
                    createdAt: nil, updatedAt: nil, allowedTransitions: nil, scheduledFor: first.scheduledFor)
        var second = first
        second = Job(id: "a", customerId: "c", title: "a", status: "dispatched",
                     createdAt: nil, updatedAt: nil, allowedTransitions: nil, scheduledFor: first.scheduledFor)
        XCTAssertEqual(JobFiltering.nextScheduledVisit([first, second], customerID: "c", now: now)?.id, "a")
    }

    func testActiveCustomerJobRemainsVisibleAlongsideFutureVisit() {
        let active = Job(id: "active", customerId: "c", title: "Repair", status: "in_progress",
                         createdAt: nil, updatedAt: nil, allowedTransitions: nil)
        let other = Job(id: "other", customerId: "another", title: "Other", status: "in_progress",
                        createdAt: nil, updatedAt: nil, allowedTransitions: nil)
        let scheduled = Job(id: "future", customerId: "c", title: "Future", status: "scheduled",
                            createdAt: nil, updatedAt: nil, allowedTransitions: nil,
                            scheduledFor: "2026-10-30T12:00:00Z")
        XCTAssertEqual(JobFiltering.activeCustomerJob([other, scheduled, active], customerID: "c")?.id, "active")
        XCTAssertNil(JobFiltering.activeCustomerJob([other, scheduled], customerID: "c"))
    }

    func testUnscheduledLaneShowsHowLongTheJobHasWaited() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(ScheduleCompactRow.age(since: now, now: now), "Today")
        XCTAssertEqual(ScheduleCompactRow.age(since: now.addingTimeInterval(-3 * 86400), now: now), "3d")
        XCTAssertEqual(ScheduleCompactRow.age(since: now.addingTimeInterval(-21 * 86400), now: now), "3w")
        XCTAssertEqual(ScheduleCompactRow.age(since: now.addingTimeInterval(-150 * 86400), now: now), "5mo")
    }

    func testVisitLabelSaysTodayTomorrowOrTheDate() {
        let now = Date()
        XCTAssertTrue(now.visitLabel(now: now).hasPrefix("Today "))
        XCTAssertTrue(now.addingTimeInterval(86400).visitLabel(now: now).hasPrefix("Tomorrow "))
        let later = now.addingTimeInterval(5 * 86400).visitLabel(now: now)
        XCTAssertFalse(later.hasPrefix("Today") || later.hasPrefix("Tomorrow"))
    }

    func testTodayUsesScheduledTimeAndKeepsUnscheduledSeparate() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = makeJob("today", time: ISO8601DateFormatter().string(from: now))
        let tomorrow = makeJob("tomorrow", time: ISO8601DateFormatter().string(from: now.addingTimeInterval(86400)))
        let unscheduled = makeJob("unscheduled", time: nil)
        XCTAssertEqual(JobFiltering.schedule([tomorrow, unscheduled, today], range: .today, now: now, calendar: calendar).map(\.id), ["today"])
        XCTAssertEqual(JobFiltering.schedule([today, unscheduled], range: .unscheduled, now: now, calendar: calendar).map(\.id), ["unscheduled"])
    }

    func testAssignedFiltersExactActorAndSearch() {
        var mine = makeJob("mine", time: nil)
        mine.assignedToUserId = "actor"
        var other = makeJob("other", time: nil)
        other.assignedToUserId = "different"
        XCTAssertEqual(JobFiltering.jobs([mine, other], assignedTo: "actor", search: "mine").map(\.id), ["mine"])
        XCTAssertTrue(JobFiltering.jobs([mine], assignedTo: "different", search: "").isEmpty)
    }

    func testMyDayUsesLocalDayCurrentActorAndScheduledOrder() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let now = formatter.date(from: "2026-10-27T00:30:00Z")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        let latePreviousUTCDate = makeJob("late", time: "2026-10-27T05:00:00Z", assignedTo: "actor")
        let earlyPreviousUTCDate = makeJob("early", time: "2026-10-27T00:10:00Z", assignedTo: "actor")
        let tieB = makeJob("tie-b", time: "2026-10-27T04:00:00Z", assignedTo: "actor")
        let tieA = makeJob("tie-a", time: "2026-10-27T04:00:00Z", assignedTo: "actor")
        let completed = makeJob("completed", time: "2026-10-27T03:00:00Z", assignedTo: "actor", status: "completed")
        let canceled = makeJob("canceled", time: "2026-10-27T03:30:00Z", assignedTo: "actor", status: "canceled")
        let otherActor = makeJob("other", time: "2026-10-27T01:00:00Z", assignedTo: "other")
        let tomorrow = makeJob("tomorrow", time: "2026-10-27T08:00:00Z", assignedTo: "actor")
        let unscheduled = makeJob("unscheduled", time: nil, assignedTo: "actor")

        XCTAssertEqual(
            JobFiltering.myDay([latePreviousUTCDate, otherActor, tomorrow, unscheduled, tieB, canceled, earlyPreviousUTCDate, completed, tieA], actorID: "actor", now: now, calendar: calendar).map(\.id),
            ["early", "completed", "canceled", "tie-a", "tie-b", "late"]
        )
    }

    func testMyDayWithoutActorHasNoJobs() {
        let job = makeJob("today", time: "2026-10-27T12:00:00Z", assignedTo: "actor")
        XCTAssertTrue(JobFiltering.myDay([job], actorID: nil).isEmpty)
    }

    func testEmptyStateRequiresSuccessfulFinishedFetch() {
        XCTAssertFalse(MyDayRules.shouldShowEmptyState(isEmpty: true, isLoading: false, hasError: true))
        XCTAssertFalse(MyDayRules.shouldShowEmptyState(isEmpty: true, isLoading: true, hasError: false))
        XCTAssertFalse(MyDayRules.shouldShowEmptyState(isEmpty: false, isLoading: false, hasError: false))
        XCTAssertTrue(MyDayRules.shouldShowEmptyState(isEmpty: true, isLoading: false, hasError: false))
    }

    func testStartDrivingRequiresEditPermissionAndServerAllowedTransition() {
        let dispatched = makeJob("ready", time: nil, assignedTo: "actor", status: "dispatched", transitions: ["en_route"])
        let forbidden = makeJob("forbidden", time: nil, assignedTo: "actor", status: "dispatched")
        let scheduled = makeJob("scheduled", time: nil, assignedTo: "actor", status: "scheduled", transitions: ["dispatched"])
        let completed = makeJob("completed", time: nil, assignedTo: "actor", status: "completed", transitions: ["en_route"])
        let canceled = makeJob("canceled", time: nil, assignedTo: "actor", status: "canceled", transitions: ["en_route"])

        XCTAssertTrue(MyDayRules.canStartDriving(dispatched, canEdit: true))
        XCTAssertFalse(MyDayRules.canStartDriving(dispatched, canEdit: false))
        XCTAssertFalse(MyDayRules.canStartDriving(forbidden, canEdit: true))
        XCTAssertFalse(MyDayRules.canStartDriving(scheduled, canEdit: true))
        XCTAssertFalse(MyDayRules.canStartDriving(completed, canEdit: true))
        XCTAssertFalse(MyDayRules.canStartDriving(canceled, canEdit: true))
    }

    // MARK: board (Display sheet)

    func testBoardHidesCompletedAndCanceledWhenAsked() {
        let open = makeJob("open", time: nil, status: "scheduled")
        let done = makeJob("done", time: nil, status: "completed")
        let canceled = makeJob("canceled", time: nil, status: "canceled")
        let hidden = JobFiltering.board([open, done, canceled], assignedTo: nil, search: "",
                                        showCompleted: false, statuses: [], ordering: .recent).map(\.id)
        XCTAssertEqual(Set(hidden), ["open"])
        let shown = JobFiltering.board([open, done, canceled], assignedTo: nil, search: "",
                                       showCompleted: true, statuses: [], ordering: .recent).map(\.id)
        XCTAssertEqual(Set(shown), ["open", "done", "canceled"])
    }

    func testBoardKeepsOnlyTickedStatuses() {
        let a = makeJob("a", time: nil, status: "scheduled")
        let b = makeJob("b", time: nil, status: "paused")
        let c = makeJob("c", time: nil, status: "en_route")
        let filtered = JobFiltering.board([a, b, c], assignedTo: nil, search: "",
                                          showCompleted: true, statuses: ["paused", "en_route"], ordering: .recent).map(\.id)
        XCTAssertEqual(Set(filtered), ["b", "c"])
        // An empty status set means every status, not none.
        let all = JobFiltering.board([a, b, c], assignedTo: nil, search: "",
                                     showCompleted: true, statuses: [], ordering: .recent).map(\.id)
        XCTAssertEqual(Set(all), ["a", "b", "c"])
    }

    func testBoardOrdersByNameThenByScheduledTime() {
        let zulu = makeJob("z", time: "2026-10-27T09:00:00Z")
        let alpha = makeJob("a", time: "2026-10-27T11:00:00Z")
        XCTAssertEqual(JobFiltering.board([zulu, alpha], assignedTo: nil, search: "",
                                          showCompleted: true, statuses: [], ordering: .name).map(\.id), ["a", "z"])
        XCTAssertEqual(JobFiltering.board([alpha, zulu], assignedTo: nil, search: "",
                                          showCompleted: true, statuses: [], ordering: .scheduled).map(\.id), ["z", "a"])
    }

    private func makeJob(_ id: String, time: String?, assignedTo: String? = nil, status: String = "scheduled", transitions: [String]? = nil) -> Job {
        var job = Job(id: id, customerId: nil, title: id, status: status, createdAt: nil, updatedAt: nil, allowedTransitions: transitions)
        job.scheduledFor = time
        job.assignedToUserId = assignedTo
        return job
    }
}
