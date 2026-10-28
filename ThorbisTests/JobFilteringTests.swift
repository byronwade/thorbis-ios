import XCTest
@testable import Thorbis

final class JobFilteringTests: XCTestCase {
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

    private func makeJob(_ id: String, time: String?, assignedTo: String? = nil, status: String = "scheduled", transitions: [String]? = nil) -> Job {
        var job = Job(id: id, customerId: nil, title: id, status: status, createdAt: nil, updatedAt: nil, allowedTransitions: transitions)
        job.scheduledFor = time
        job.assignedToUserId = assignedTo
        return job
    }
}
