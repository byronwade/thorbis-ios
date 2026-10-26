import XCTest
@testable import Thorbis

final class JobFilteringTests: XCTestCase {
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

    private func makeJob(_ id: String, time: String?) -> Job {
        var job = Job(id: id, customerId: nil, title: id, status: "scheduled", createdAt: nil, updatedAt: nil, allowedTransitions: nil)
        job.scheduledFor = time
        return job
    }
}
