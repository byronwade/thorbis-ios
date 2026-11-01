import XCTest
@testable import Thorbis

/// Role defaults for the bottom bar and the role-aware Schedule › Today.
@MainActor
final class NavigationByRoleTests: XCTestCase {
    private func store() -> UserDefaults {
        let name = "nav-by-role-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func role(_ capabilities: Set<String>) -> WorkRole {
        WorkRole(can: { capability, _ in capabilities.contains(capability) })
    }

    func testRoleComesFromExistingCapabilities() {
        XCTAssertEqual(role(["job.view"]), .technician)
        XCTAssertEqual(role(["job.view", "job.assign"]), .office)
        XCTAssertEqual(role(["job.view", "job.assign", "organization.settings.edit"]), .owner)
        XCTAssertTrue(WorkRole.technician.schedulesOwnDay)
        XCTAssertFalse(WorkRole.office.schedulesOwnDay)
        XCTAssertFalse(WorkRole.owner.schedulesOwnDay)
    }

    func testEachRoleStartsWithItsOwnBar() {
        let all: (MenuItem) -> Bool = { _ in true }
        XCTAssertEqual(MenuLayout.defaultTabs(for: .technician, permitted: all), [.schedule, .jobs, .customers])
        XCTAssertEqual(MenuLayout.defaultTabs(for: .office, permitted: all), [.schedule, .inbox, .customers, .jobs])
        XCTAssertEqual(MenuLayout.defaultTabs(for: .owner, permitted: all), [.home, .schedule, .money, .customers])
    }

    func testPlacesARoleCannotOpenAreReplacedFromTheStandardBar() {
        // An office account without booking notices, an owner without payments.
        let office = MenuLayout.defaultTabs(for: .office, permitted: { $0 != .inbox })
        XCTAssertEqual(office, [.schedule, .customers, .jobs])
        let owner = MenuLayout.defaultTabs(for: .owner, permitted: { $0 != .money })
        XCTAssertEqual(owner, [.home, .schedule, .customers, .jobs])
        XCTAssertLessThanOrEqual(owner.count, MenuLayout.maxTabs)
    }

    func testRoleDefaultsApplyOnlyWithoutASavedPhoneLayout() {
        let fresh = MenuLayout(defaults: store())
        fresh.applyRoleDefaults(.owner, permitted: { _ in true })
        XCTAssertEqual(fresh.tabs, [.home, .schedule, .money, .customers])
        XCTAssertTrue(fresh.isDefault)
        XCTAssertFalse(fresh.hasSavedPhoneLayout, "The role default is derived, not saved")

        let saved = store()
        let layout = MenuLayout(defaults: saved)
        layout.addTab(.invoices)
        XCTAssertTrue(layout.hasSavedPhoneLayout)
        let reloaded = MenuLayout(defaults: saved)
        reloaded.applyRoleDefaults(.owner, permitted: { _ in true })
        XCTAssertEqual(reloaded.tabs, [.schedule, .jobs, .customers, .invoices], "A saved layout is never replaced")
    }

    func testResetReturnsToTheRoleBar() {
        let layout = MenuLayout(defaults: store())
        layout.applyRoleDefaults(.office, permitted: { _ in true })
        layout.removeTab(.inbox)
        XCTAssertFalse(layout.isDefault)
        layout.reset()
        XCTAssertEqual(layout.tabs, [.schedule, .inbox, .customers, .jobs])
    }

    func testNotificationRulesLiveInSettingsAndReportsInsideMoney() {
        XCTAssertEqual(MenuItem.notices.title, "Notification rules")
        XCTAssertFalse(MenuItem.listed(.notices, permitted: { _ in true }))
        XCTAssertFalse(MenuItem.listed(.reports, permitted: { _ in true }), "Reports is a tab of Money")
        XCTAssertTrue(MenuItem.listed(.reports, permitted: { $0 != .money }), "Without Money, Reports stays its own place")
        let menu = AppMenuContent.menu(tabs: [.schedule], hidden: [], order: [], permitted: { _ in true })
        XCTAssertFalse(menu.contains(.notices))
        XCTAssertFalse(menu.contains(.reports))
        XCTAssertTrue(menu.contains(.money))
        XCTAssertTrue(menu.contains(.inbox))
    }

    func testTodayShowsATechniciansOwnJobsAndEveryoneOnRequest() {
        let now = ISO8601DateFormatter().date(from: "2026-10-30T15:00:00Z")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func job(_ id: String, _ who: String?, _ time: String?, status: String = "scheduled") -> Job {
            var job = Job(id: id, customerId: nil, title: id, status: status, createdAt: nil, updatedAt: nil,
                          allowedTransitions: nil, scheduledFor: time)
            job.assignedToUserId = who
            return job
        }
        let jobs = [
            job("mine", "me", "2026-10-30T16:00:00Z"),
            job("theirs", "them", "2026-10-30T14:00:00Z"),
            job("open", nil, "2026-10-30T17:00:00Z"),
            job("done", "me", "2026-10-30T09:00:00Z", status: "completed"),
            job("tomorrow", "me", "2026-10-31T09:00:00Z"),
            job("queue", nil, nil),
        ]
        let tech = ScheduleScope.initial(schedulesOwnDay: true, actorID: "me")
        XCTAssertEqual(tech, .mine)
        XCTAssertEqual(ScheduleScope.initial(schedulesOwnDay: false, actorID: "me"), .everyone)
        XCTAssertEqual(ScheduleScope.initial(schedulesOwnDay: true, actorID: nil), .everyone,
                       "Without a known person there is no 'mine' to show")

        let today = JobFiltering.schedule(jobs, range: .today, assignedTo: tech.assignee("me", range: .today),
                                          now: now, calendar: calendar)
        XCTAssertEqual(today.map(\.id), ["mine"])
        let everyone = JobFiltering.schedule(jobs, range: .today,
                                             assignedTo: ScheduleScope.everyone.assignee("me", range: .today),
                                             now: now, calendar: calendar)
        XCTAssertEqual(everyone.map(\.id), ["theirs", "mine", "open"])
        // Unscheduled is everyone's queue, whichever scope is picked.
        XCTAssertNil(tech.assignee("me", range: .unscheduled))
        XCTAssertEqual(JobFiltering.schedule(jobs, range: .unscheduled, assignedTo: tech.assignee("me", range: .unscheduled),
                                             now: now, calendar: calendar).map(\.id), ["queue"])
    }
}
