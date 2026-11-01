import XCTest
@testable import Thorbis

@MainActor
final class PrimaryNavigationTests: XCTestCase {
    func testPrimaryRootsAreScheduleJobsAndCustomersInOrder() {
        XCTAssertEqual(PrimaryTab.allCases, [.schedule, .jobs, .customers])
        XCTAssertEqual(PrimaryTab.allCases.map(\.title), ["Schedule", "Jobs", "Customers"])
    }

    func testScheduleIsTheInitialPrimaryDestination() {
        XCTAssertEqual(PrimaryTab.initial, .schedule)
        XCTAssertEqual(DrawerPlaces.title(.schedule, role: .technician), "Today")
        XCTAssertEqual(DrawerPlaces.title(.schedule, role: .office), "Schedule", "The same screen reads as the schedule the office runs")
        XCTAssertEqual(DrawerPlaces.title(.inbox, role: .technician), "Inbox")
    }

    func testPrimaryDestinationsRemainStableWhenRoleAccessIsLimited() {
        let access = PrimaryTabAccess(canViewJobs: false, canViewCustomers: true)

        XCTAssertEqual(PrimaryTab.allCases, [.schedule, .jobs, .customers])
        XCTAssertFalse(access.canOpen(.schedule))
        XCTAssertFalse(access.canOpen(.jobs))
        XCTAssertTrue(access.canOpen(.customers))
        XCTAssertEqual(access.unavailableMessage(for: .schedule), "Your role does not allow access to jobs.")
        XCTAssertEqual(PrimaryTabAccess(canViewJobs: true, canViewCustomers: false).unavailableMessage(for: .customers),
                       "Your role does not allow access to customers.")
    }

    func testDrawerSettlesOpenPastAThirdOrOnAFlick() {
        XCTAssertTrue(DrawerMotion.settlesOpen(wasOpen: false, translation: 120, predicted: 120, width: 300))
        XCTAssertFalse(DrawerMotion.settlesOpen(wasOpen: false, translation: 40, predicted: 60, width: 300))
        XCTAssertTrue(DrawerMotion.settlesOpen(wasOpen: false, translation: 40, predicted: 200, width: 300))
        XCTAssertFalse(DrawerMotion.settlesOpen(wasOpen: true, translation: -120, predicted: -120, width: 300))
        XCTAssertTrue(DrawerMotion.settlesOpen(wasOpen: true, translation: -20, predicted: -40, width: 300))
    }

    func testDrawerProgressAndWidth() {
        XCTAssertEqual(DrawerMotion.progress(open: false, drag: 0, width: 300), 0)
        XCTAssertEqual(DrawerMotion.progress(open: true, drag: 0, width: 300), 1)
        XCTAssertEqual(DrawerMotion.progress(open: false, drag: 150, width: 300), 0.5)
        XCTAssertEqual(DrawerMotion.progress(open: true, drag: -150, width: 300), 0.5)
        XCTAssertEqual(DrawerMotion.width(screen: 402, accessibilitySize: false), 322, "About 80% of the screen")
        XCTAssertEqual(DrawerMotion.width(screen: 375, accessibilitySize: false), 300)
        XCTAssertEqual(DrawerMotion.width(screen: 402, accessibilitySize: true), 402)
        XCTAssertEqual(DrawerMotion.cornerRadius(topInset: 62), 55)
        XCTAssertEqual(DrawerMotion.cornerRadius(topInset: 47), 44)
    }

    // MARK: Sidebar places (Cream sheet: every place a role can reach, grouped)

    /// A role's permissions, as the server grants them, by place.
    private func permitted(_ role: WorkRole) -> (MenuItem) -> Bool {
        switch role {
        case .technician: { [.schedule, .jobs, .customers, .inbox, .estimates, .invoices, .priceBook, .drafts, .attention].contains($0) }
        case .office: { $0 != .home && $0 != .notices && $0 != .team }
        case .owner: { _ in true }
        }
    }

    private func sections(_ role: WorkRole, pins: [MenuItem]? = nil, explicit: Bool = false, hidden: Set<MenuItem> = [],
                          local: [LocalWorkspaceSection] = [], opens: ((MenuItem) -> Bool)? = nil) -> DrawerSections {
        let allowed = opens ?? permitted(role)
        return DrawerSections.make(pins: pins ?? MenuLayout.defaultTabs(for: role, permitted: allowed), explicitPins: explicit,
                                   roleDefaults: MenuLayout.defaultTabs(for: role, permitted: allowed),
                                   hidden: hidden, local: local, opens: allowed)
    }

    func testSidebarListsEveryReachablePlaceExactlyOnceForEachRole() {
        for role in [WorkRole.technician, .office, .owner] {
            let result = sections(role, local: LocalWorkspaceSection.allCases)
            let expected = Set(MenuItem.allCases.filter(permitted(role)))
            XCTAssertEqual(Set(result.places), expected, "\(role) sees every place it may open, and only those")
            XCTAssertEqual(result.places.count, expected.count, "\(role): no place is listed twice")
            XCTAssertEqual(result.sections.last?.local, LocalWorkspaceSection.allCases, "On this phone lists the local places")
            XCTAssertFalse(result.sections.contains { $0.kind == .pinned }, "Role defaults never add a Pinned section")
        }
        // Notification rules and Reports are places of their own now (Shop, Money).
        XCTAssertTrue(sections(.owner).places.contains(.notices))
        XCTAssertTrue(sections(.owner).places.contains(.reports))
    }

    func testSidebarGroupsAndOrderFollowTheDesign() {
        let owner = sections(.owner)
        XCTAssertEqual(owner.sections.map(\.kind), [.work, .money, .shop])
        XCTAssertEqual(owner.sections[0].places, [.home, .schedule, .jobs, .customers, .properties, .inbox, .attention])
        XCTAssertEqual(owner.sections[1].places, [.money, .estimates, .invoices, .billing, .reports, .scorecard, .priceBook])
        XCTAssertEqual(owner.sections[2].places, [.team, .notices, .drafts])
        XCTAssertEqual(sections(.technician).sections.map(\.kind), [.work, .money, .shop])
    }

    func testSidebarFollowsAccessAndHiddenPlaces() {
        let noJobs = sections(.technician, opens: { ![.schedule, .jobs, .inbox].contains($0) && self.permitted(.technician)($0) })
        XCTAssertFalse(noJobs.places.contains(.jobs))
        XCTAssertTrue(noJobs.places.contains(.customers))
        XCTAssertFalse(sections(.office, hidden: [.inbox]).places.contains(.inbox), "A place turned off in Customize menu stays off")
        XCTAssertTrue(sections(.office, local: []).sections.allSatisfy { $0.kind != .phone })
    }

    func testExplicitPinsLeadInTheirOwnSectionOnce() {
        let office = sections(.office, pins: [.estimates, .invoices], explicit: true)
        XCTAssertEqual(office.sections.first?.kind, .pinned)
        XCTAssertEqual(office.sections.first?.places, [.estimates, .invoices])
        XCTAssertEqual(office.places.filter { $0 == .estimates }.count, 1, "A pinned place leaves its group")
        let company = DrawerSections.make(pins: [.schedule, .money, .customers], explicitPins: true,
                                          roleDefaults: MenuLayout.defaultTabs(for: .owner, permitted: { _ in true }),
                                          opens: { _ in true })
        XCTAssertEqual(company.sections.first?.kind, .work, "A company layout made from the owner's defaults adds no Pinned section")
        let ordered = DrawerSections.make(order: [.customers, .jobs], opens: { _ in true })
        XCTAssertEqual(Array(ordered.sections[0].places.prefix(2)), [.customers, .jobs], "Edit menu's order leads inside a section")
    }

    func testTodayNumbersCountLeftAndLate() {
        let now = Date()
        let iso = ISO8601DateFormatter()
        func job(_ id: String, _ status: String, hoursFromNow: Double, who: String? = "me") -> Job {
            Job(id: id, customerId: nil, title: id, status: status, createdAt: nil, updatedAt: nil, allowedTransitions: nil,
                scheduledFor: iso.string(from: now.addingTimeInterval(hoursFromNow * 3600)), assignedToUserId: who)
        }
        // Times stay inside today wherever the test runs.
        let start = Calendar.current.startOfDay(for: now)
        let base = now.timeIntervalSince(start) / 3600
        let jobs = [job("a", "completed", hoursFromNow: -min(base, 1) * 0.5), job("b", "scheduled", hoursFromNow: -min(base, 1) * 0.25),
                    job("c", "dispatched", hoursFromNow: min(24 - base, 1) * 0.5), job("d", "canceled", hoursFromNow: 0),
                    job("e", "scheduled", hoursFromNow: min(24 - base, 1) * 0.5, who: "other")]
        let mine = TodayNumbers.visits(jobs, assignee: "me", now: now)
        XCTAssertEqual(mine.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(TodayNumbers.left(mine), 2)
        XCTAssertEqual(TodayNumbers.late(mine, now: now), 1)
        XCTAssertEqual(TodayNumbers.open(jobs), 3)
        XCTAssertEqual(TodayNumbers.visits(jobs, assignee: nil, now: now).count, 4)
    }
}
