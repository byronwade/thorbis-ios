import Foundation
import XCTest
@testable import ThorbisCore

final class WorkflowTests: XCTestCase {
    func testPrimaryActionFollowsTheServicePath() {
        func primary(_ status: JobStatus) -> JobAction? {
            JobWorkflow.primaryAction(status: status, allowed: JobWorkflow.fallbackTransitions(from: status))
        }
        XCTAssertEqual(primary(.scheduled), .progress(.enRoute))
        XCTAssertEqual(primary(.dispatched), .progress(.enRoute))
        XCTAssertEqual(primary(.enRoute), .progress(.arrived))
        XCTAssertEqual(primary(.arrived), .progress(.inProgress))
        XCTAssertEqual(primary(.inProgress), .complete)
        XCTAssertEqual(primary(.paused), .resume)
        XCTAssertNil(primary(.completed))
        XCTAssertNil(primary(.canceled))
    }

    func testActionsNeverExceedWhatTheServerAllows() {
        XCTAssertNil(JobWorkflow.primaryAction(status: .enRoute, allowed: []))
        XCTAssertEqual(JobWorkflow.secondaryActions(status: .enRoute, allowed: []), [])
        // Server says only cancel: the client must not invent Arrive.
        XCTAssertNil(JobWorkflow.primaryAction(status: .enRoute, allowed: [.canceled]))
        XCTAssertEqual(JobWorkflow.secondaryActions(status: .enRoute, allowed: [.canceled]), [.cancel])
    }

    func testSecondaryActionsOrderAndCancelLast() {
        let inProgress = JobWorkflow.secondaryActions(status: .inProgress, allowed: [.paused, .completed, .canceled])
        XCTAssertEqual(inProgress, [.pause, .cancel])
        let scheduled = JobWorkflow.secondaryActions(status: .scheduled, allowed: JobWorkflow.fallbackTransitions(from: .scheduled))
        XCTAssertEqual(scheduled.first, .progress(.dispatched))
        XCTAssertEqual(scheduled.last, .cancel)
        XCTAssertFalse(scheduled.contains(.progress(.enRoute)), "the primary action is not repeated")
        XCTAssertTrue(scheduled.contains(.complete))
        let paused = JobWorkflow.secondaryActions(status: .paused, allowed: [.inProgress, .completed, .canceled])
        XCTAssertEqual(paused, [.complete, .cancel])
    }

    func testCommitWordsAndDestructiveness() {
        XCTAssertEqual(JobAction.progress(.arrived).title, "Arrive")
        XCTAssertEqual(JobAction.cancel.title, "Cancel job")
        XCTAssertTrue(JobAction.cancel.isDestructive)
        XCTAssertFalse(JobAction.complete.isDestructive)
    }

    func testMilestonesAreChronological() throws {
        let job = Job(id: "j", customerId: "c", title: "T", status: .inProgress,
                      createdAt: "2026-10-27T10:00:00Z", updatedAt: "2026-10-27T12:00:00Z",
                      enRouteAt: "2026-10-27T11:00:00Z", arrivedAt: "2026-10-27T11:30:00Z",
                      startedAt: "2026-10-27T11:35:00Z")
        XCTAssertEqual(JobWorkflow.milestones(job).map(\.title), ["Created", "En route", "Arrived", "Started"])
    }
}

final class AgendaTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    private func job(_ id: String, _ status: JobStatus, at: String?, assignee: String? = "me", updated: String = "2026-10-27T00:00:00Z") -> Job {
        Job(id: id, customerId: "c", title: id, status: status, assignedToUserId: assignee, scheduledFor: at, createdAt: updated, updatedAt: updated)
    }

    func testAgendaGroupsByLocalDayAndDropsFinishedWork() {
        let jobs = [
            job("late", .scheduled, at: "2026-10-27T22:00:00Z"),   // 5pm Chicago, Oct 27
            job("early", .scheduled, at: "2026-10-27T14:00:00Z"),  // 9am Chicago, Oct 27
            job("tomorrow", .scheduled, at: "2026-10-28T04:30:00Z"), // 11:30pm Chicago, Oct 27 (still the 27th)
            job("next", .dispatched, at: "2026-10-28T15:00:00Z"),
            job("done", .completed, at: "2026-10-27T15:00:00Z"),
            job("floating", .scheduled, at: nil),
            job("theirs", .scheduled, at: "2026-10-27T15:00:00Z", assignee: "someone"),
        ]
        let agenda = Agenda.build(jobs, assignedTo: "me", calendar: calendar)
        XCTAssertEqual(agenda.days.count, 2)
        XCTAssertEqual(agenda.days[0].jobs.map(\.id), ["early", "late", "tomorrow"])
        XCTAssertEqual(agenda.days[1].jobs.map(\.id), ["next"])
        XCTAssertEqual(agenda.unscheduled.map(\.id), ["floating"])
    }

    func testNextUpPrefersWorkUnderway() {
        let now = Timestamp.parse("2026-10-27T15:00:00Z")!
        let jobs = [
            job("soon", .scheduled, at: "2026-10-27T16:00:00Z"),
            job("driving", .enRoute, at: "2026-10-27T18:00:00Z"),
        ]
        XCTAssertEqual(Agenda.nextUp(jobs, now: now)?.id, "driving")
        XCTAssertEqual(Agenda.nextUp([jobs[0], job("past", .scheduled, at: "2026-10-27T09:00:00Z")], now: now)?.id, "soon")
        XCTAssertEqual(Agenda.nextUp([job("past", .scheduled, at: "2026-10-27T09:00:00Z")], now: now)?.id, "past")
        XCTAssertNil(Agenda.nextUp([job("done", .completed, at: nil)], now: now))
    }

    func testBucketsAndDirectory() {
        let groups = JobBucket.group([job("a", .inProgress, at: nil), job("b", .scheduled, at: nil), job("c", .completed, at: nil)])
        XCTAssertEqual(groups.map(\.bucket), [.active, .scheduled, .completed])
        let sections = Directory.sections([
            Customer(id: "1", name: "zeta"), Customer(id: "2", name: "Alpha"), Customer(id: "3", name: "42 Club"),
            Customer(id: "4", name: "archived", archived: true), Customer(id: "5", name: "alpine"),
        ])
        XCTAssertEqual(sections.map(\.letter), ["A", "Z", "#"])
        XCTAssertEqual(sections[0].customers.map(\.name), ["Alpha", "alpine"])
    }
}

final class FormattingTests: XCTestCase {
    func testMoneyIsCentsAndLocalized() {
        XCTAssertEqual(Format.money(185_050, locale: Locale(identifier: "en_US")), "$1,850.50")
        XCTAssertEqual(Format.money(0, locale: Locale(identifier: "en_US")), "$0.00")
    }

    func testInitialsAndWords() {
        XCTAssertEqual(Format.initials("Mike Reyes"), "MR")
        XCTAssertEqual(Format.initials("  "), "?")
        XCTAssertEqual(Format.initials("Jean-Luc Picard"), "JL")
        XCTAssertEqual(Format.status(JobStatus.enRoute), "En route")
        XCTAssertEqual(Format.billingTerms("net_30"), "Net 30")
        XCTAssertNil(Format.billingTerms("weird"))
    }

    func testDayTitles() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Timestamp.parse("2026-10-27T12:00:00Z")!
        XCTAssertEqual(Format.dayTitle(now, now: now, calendar: calendar), "Today")
        XCTAssertEqual(Format.dayTitle(now.addingTimeInterval(86_400), now: now, calendar: calendar), "Tomorrow")
        XCTAssertEqual(Format.dayTitle(now.addingTimeInterval(-86_400), now: now, calendar: calendar), "Yesterday")
    }

    func testEnvironmentValidation() {
        XCTAssertEqual(APIEnvironment.custom("https://thorbis.com/app/")?.baseURL.absoluteString, "https://thorbis.com/app")
        XCTAssertNotNil(APIEnvironment.custom("http://127.0.0.1:8788"))
        XCTAssertNil(APIEnvironment.custom("http://example.com"), "plain HTTP is loopback only")
        XCTAssertNil(APIEnvironment.custom("not a url"))
        XCTAssertEqual(APIEnvironment.production.origin, "https://app.thorbis.com")
        XCTAssertEqual(APIEnvironment.local.origin, "http://127.0.0.1:8788")
    }
}
