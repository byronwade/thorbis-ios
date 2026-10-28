import XCTest
@testable import Thorbis

final class JobHoursTests: XCTestCase {
    private let now = JobFiltering.date("2026-10-28T16:00:00Z")!

    private func job(_ status: String, enRoute: String? = nil, arrived: String? = nil, completed: String? = nil,
                     paused: String? = nil, resumed: String? = nil) -> JobRecord {
        JobRecord(id: "job", organizationId: "org", customerId: "cust", estimateId: nil, estimateRevisionNumber: nil,
                  locationId: nil, teamId: nil, title: "Water heater", notes: nil, status: status,
                  assignedToUserId: nil, scheduledFor: "2026-10-28T13:00:00Z", createdAt: "2026-10-27T10:00:00Z",
                  updatedAt: "2026-10-28T15:00:00Z", dispatchedAt: nil, enRouteAt: enRoute, arrivedAt: arrived,
                  arrivalMethod: nil, startedAt: nil, pausedAt: paused, pauseReason: nil, pauseNextAction: nil,
                  pauseOwnerUserId: nil, pauseCycleAuditId: nil, lastResumeAuditId: resumed,
                  scheduleCycleAuditId: nil, completedAt: completed, canceledAt: nil, allowedTransitions: nil)
    }

    func testAFinishedJobShowsDriveAndOnSiteRoundedDown() {
        let hours = JobHours.make(job("completed", enRoute: "2026-10-28T13:00:00Z", arrived: "2026-10-28T13:24:40Z",
                                      completed: "2026-10-28T14:37:10Z"), now: now)
        XCTAssertEqual(hours?.line, "Drive 0 h 24 min · On site 1 h 12 min")
        XCTAssertEqual(hours?.hasDuration, true)
        XCTAssertEqual(hours?.minutes, 96)
    }

    func testAScheduledJobHasNoTimeRow() {
        XCTAssertNil(JobHours.make(job("scheduled"), now: now))
    }

    func testWhileWorkingOnSiteCountsUpSoFar() {
        let hours = JobHours.make(job("in_progress", enRoute: "2026-10-28T14:30:00Z", arrived: "2026-10-28T15:00:00Z"), now: now)
        XCTAssertEqual(hours?.line, "Drive 0 h 30 min · On site 1 h 0 min so far")
    }

    func testOnTheWayCountsTheDriveSoFar() {
        let hours = JobHours.make(job("en_route", enRoute: "2026-10-28T15:45:00Z"), now: now)
        XCTAssertEqual(hours?.line, "Drive 0 h 15 min so far")
    }

    func testAMissingArrivalIsNamedNotGuessed() {
        let hours = JobHours.make(job("completed", enRoute: "2026-10-28T13:00:00Z", completed: "2026-10-28T14:00:00Z"), now: now)
        XCTAssertEqual(hours?.line, "Arrived not recorded")
        XCTAssertEqual(hours?.hasDuration, false)
        XCTAssertEqual(hours?.minutes, 0)
    }

    func testAMissingOnMyWayIsNamed() {
        let hours = JobHours.make(job("completed", arrived: "2026-10-28T13:00:00Z", completed: "2026-10-28T14:05:00Z"), now: now)
        XCTAssertEqual(hours?.line, "On my way not recorded · On site 1 h 5 min")
    }

    func testARedispatchAfterArrivalDropsTheDriveInsteadOfGoingNegative() {
        let hours = JobHours.make(job("completed", enRoute: "2026-10-28T14:00:00Z", arrived: "2026-10-28T13:00:00Z",
                                      completed: "2026-10-28T15:00:00Z"), now: now)
        XCTAssertEqual(hours?.line, "On site 2 h 0 min")
    }

    func testAPausedJobSaysItsTimeIncludesThePause() {
        let hours = JobHours.make(job("paused", arrived: "2026-10-28T15:00:00Z", paused: "2026-10-28T15:30:00Z"), now: now)
        XCTAssertEqual(hours?.line, "On my way not recorded · On site 1 h 0 min so far · includes paused time")
    }

    func testDurationsAreHoursAndMinutes() {
        XCTAssertEqual(JobHours.duration(59), "0 h 0 min")
        XCTAssertEqual(JobHours.duration(3_660), "1 h 1 min")
        XCTAssertEqual(JobHours.duration(-30), "0 h 0 min")
    }

    // MARK: JH-05 My week

    private func listJob(_ id: String, assignee: String?, enRoute: String?, arrived: String?, completed: String?,
                         status: String = "completed") -> Job {
        Job(id: id, customerId: "cust", title: "Job \(id)", status: status, createdAt: nil, updatedAt: nil,
            allowedTransitions: nil, scheduledFor: nil, assignedToUserId: assignee, locationId: nil,
            enRouteAt: enRoute, arrivedAt: arrived, pausedAt: nil, completedAt: completed)
    }

    func testMyWeekListsOnlyMyJobsByTheDayIStartedThem() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        let jobs = [
            listJob("a001", assignee: "me", enRoute: "2026-10-26T13:00:00Z", arrived: "2026-10-26T13:30:00Z", completed: "2026-10-26T15:00:00Z"),
            listJob("a002", assignee: "me", enRoute: "2026-10-28T13:00:00Z", arrived: "2026-10-28T13:20:00Z", completed: "2026-10-28T14:00:00Z"),
            listJob("a003", assignee: "someone", enRoute: "2026-10-28T13:00:00Z", arrived: "2026-10-28T13:20:00Z", completed: "2026-10-28T14:00:00Z"),
            listJob("a004", assignee: "me", enRoute: "2026-10-19T13:00:00Z", arrived: "2026-10-19T13:20:00Z", completed: "2026-10-19T14:00:00Z"),
        ]
        let week = JobWeek.make(jobs, userID: "me", now: now, calendar: calendar)
        XCTAssertEqual(week.days.count, 3) // Mon, Tue, Wed (today).
        XCTAssertEqual(week.days[0].rows.map(\.id), ["a001"])
        XCTAssertEqual(week.days[0].minutes, 120)
        XCTAssertTrue(week.days[1].rows.isEmpty)
        XCTAssertEqual(week.days[2].rows.map(\.id), ["a002"])
        XCTAssertEqual(week.minutes, 180)
        XCTAssertEqual(JobHours.minutes(week.minutes), "3 h 0 min")
    }

    func testMyWeekIsEmptyWithoutASignedInTech() {
        let jobs = [listJob("a001", assignee: nil, enRoute: "2026-10-28T13:00:00Z", arrived: nil, completed: nil, status: "en_route")]
        XCTAssertEqual(JobWeek.make(jobs, userID: nil, now: now).minutes, 0)
    }
}
