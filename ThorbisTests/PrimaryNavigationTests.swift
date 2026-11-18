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
        XCTAssertEqual(DrawerPlaces.title(.schedule, role: .technician), "Schedule")
        XCTAssertEqual(DrawerPlaces.title(.home, role: .owner), "Dashboard")
        XCTAssertEqual(DrawerPlaces.title(.schedule, role: .office), "Schedule", "The same screen reads as the schedule the office runs")
        XCTAssertEqual(DrawerPlaces.title(.inbox, role: .technician), "Messages")
        XCTAssertEqual(DrawerPlaces.title(.team, role: .owner), "Team")
    }

    // MARK: Paper v2 drawer (Navigation 29N, 57N, 58N)

    func testPaperDrawerFollowsEachRolesOrder() {
        let records = LocalWorkspaceSection.allCases
        func make(_ role: WorkRole) -> DrawerSections {
            DrawerSections.make(local: records, role: role, opens: permitted(role))
        }
        let tech = make(.technician)
        XCTAssertEqual(tech.sections.first?.kind, .primary)
        XCTAssertEqual(tech.sections[0].places, [.schedule, .jobs, .customers, .inbox])
        XCTAssertEqual(tech.sections[1].kind, .tools)
        XCTAssertEqual(tech.sections[1].rows, [.place(.priceBook), .local(.equipment)])

        let office = make(.office)
        XCTAssertEqual(office.sections[0].places, [.schedule, .jobs, .money, .customers, .pipeline, .inbox],
                       "This office test role cannot open the Dashboard")
        XCTAssertEqual(office.sections[1].kind, .manage)
        XCTAssertEqual(office.sections[1].rows, [.place(.vendors), .place(.properties), .local(.equipment), .local(.agreements),
                                                 .place(.reports)])

        let owner = make(.owner)
        XCTAssertEqual(owner.sections[0].places, [.home, .money, .reports, .schedule, .jobs, .inbox],
                       "Paper 58N draws no Jobs row; it stays with the first group until the owner decides")
        XCTAssertEqual(owner.sections[1].kind, .business)
        XCTAssertEqual(owner.sections[1].rows, [.place(.customers), .place(.pipeline), .place(.marketing), .local(.agreements),
                                                .place(.properties), .local(.equipment), .local(.fleet), .place(.vendors),
                                                .place(.businessSettings)])
        XCTAssertFalse(PlaceSection.primary.hasHeading, "The main places carry no heading")
        XCTAssertEqual(PlaceSection.business.rawValue, "Business")
    }

    /// The new rule: the menu lists exactly Paper's rows for the role (29N: 10, 57N: 13, 58N: 14 and
    /// Jobs), each once, with no More, Records, On this phone or Favorites group after them.
    func testPaperDrawerListsExactlyPapersRowsForEachRole() {
        let everything: (MenuItem) -> Bool = { _ in true }
        func rows(_ role: WorkRole) -> [DrawerSections.Entry] {
            DrawerSections.make(local: LocalWorkspaceSection.allCases, role: role, opens: everything).sections.flatMap(\.rows)
        }
        XCTAssertEqual(rows(.technician), [.place(.schedule), .place(.jobs), .place(.customers), .place(.inbox), .place(.timeClock),
                                           .place(.priceBook), .place(.receipts), .place(.truckStock), .local(.equipment), .place(.training)])
        XCTAssertEqual(rows(.office), [.place(.home), .place(.schedule), .place(.jobs), .place(.money), .place(.customers),
                                       .place(.pipeline), .place(.inbox),
                                       .place(.team), .place(.vendors), .place(.properties), .local(.equipment), .local(.agreements),
                                       .place(.reports)])
        XCTAssertEqual(rows(.owner), [.place(.home), .place(.money), .place(.reports), .place(.schedule), .place(.jobs), .place(.inbox),
                                      .place(.customers), .place(.pipeline), .place(.marketing), .local(.agreements), .place(.properties),
                                      .local(.equipment), .local(.fleet), .place(.vendors), .place(.businessSettings)])
        XCTAssertEqual(rows(.technician).count, 10)
        XCTAssertEqual(rows(.office).count, 13)
        XCTAssertEqual(rows(.owner).count, 15, "Paper's 14 and Jobs")
        for role in [WorkRole.technician, .office, .owner] {
            let result = DrawerSections.make(local: LocalWorkspaceSection.allCases, role: role, opens: everything)
            XCTAssertEqual(result.sections.count, 2, "\(role): the main places, then one headed group")
            XCTAssertFalse(result.sections.contains { [.more, .phone, .pinned, .customized].contains($0.kind) })
            XCTAssertEqual(Set(result.sections.flatMap(\.rows)).count, result.sections.flatMap(\.rows).count, "\(role): no row twice")
            // Pins and hidden places saved by an older build change nothing but what a company hides.
            let old = DrawerSections.make(pins: [.estimates, .invoices], explicitPins: true, local: LocalWorkspaceSection.allCases,
                                          role: role, opens: everything)
            XCTAssertEqual(old, result, "\(role): pins from an older build add no rows")
        }
        // A role sees only the rows it may open; nothing else takes their place.
        let limited = DrawerSections.make(local: [], role: .technician, opens: permitted(.technician))
        XCTAssertEqual(limited.sections.flatMap(\.rows), [.place(.schedule), .place(.jobs), .place(.customers), .place(.inbox), .place(.priceBook)])
    }

    /// The order dragged in Menu and start screen moves the main rows only; ids that are not main
    /// rows (an older build saved every place) are ignored.
    func testSavedOrderArrangesTheMainRowsOnly() {
        let ordered = DrawerSections.make(order: [.estimates, .inbox, .invoices, .schedule, .priceBook], local: LocalWorkspaceSection.allCases,
                                          role: .technician, opens: { _ in true })
        XCTAssertEqual(ordered.sections[0].places, [.inbox, .schedule, .jobs, .customers, .timeClock])
        XCTAssertEqual(ordered.sections[1].rows, [.place(.priceBook), .place(.receipts), .place(.truckStock), .local(.equipment), .place(.training)])
        XCTAssertEqual(MenuArrangement.rows(role: .technician, order: [.inbox], opens: { $0 != .timeClock }), [.inbox, .schedule, .jobs, .customers])
        XCTAssertEqual(MenuArrangement.startChoices(rows: [.schedule, .jobs], chosen: .automatic), [.automatic, .schedule, .jobs])
        XCTAssertEqual(MenuArrangement.startChoices(rows: [.schedule, .jobs], chosen: .invoices), [.automatic, .schedule, .jobs, .invoices],
                       "A start screen chosen in an older build stays listed")
    }

    /// Nothing is unreachable: every place and record a role may open is in its menu or behind a
    /// screen that lists it, and Search lists them all.
    func testEveryPlaceKeepsADoorAndIsInSearch() {
        for role in [WorkRole.technician, .office, .owner] {
            let doors = PlaceDoors(role: role, businessPriceBook: role == .owner, businessTeam: role == .owner, opens: { _ in true })
            for entry in PlaceDoors.everything {
                XCTAssertNotNil(doors.door(entry), "\(role): \(entry.id) has no door")
            }
            XCTAssertEqual(Set(PlaceDoor.allCases.flatMap { doors.places(behind: $0) }.map(\.id)).count,
                           MenuItem.allCases.count + LocalWorkspaceSection.allCases.count, "\(role): each place has exactly one door")
        }
        let owner = PlaceDoors(role: .owner, businessPriceBook: true, businessTeam: true, opens: { _ in true })
        XCTAssertEqual(owner.door(.place(.estimates)), .money)
        XCTAssertEqual(owner.door(.place(.invoices)), .money)
        XCTAssertEqual(owner.door(.place(.billing)), .money)
        XCTAssertEqual(owner.door(.place(.attention)), .money)
        XCTAssertEqual(owner.door(.place(.scorecard)), .reports)
        XCTAssertEqual(owner.door(.place(.drafts)), .messages, "Message drafts is the Messages folder, not a menu place")
        XCTAssertEqual(owner.door(.place(.team)), .businessSettings)
        XCTAssertEqual(owner.door(.place(.notices)), .businessSettings)
        XCTAssertEqual(owner.door(.place(.priceBook)), .businessSettings)
        XCTAssertEqual(owner.door(.local(.team)), .team, "Team additions folds into Team")
        XCTAssertEqual(owner.door(.place(.jobs)), .menu)
        XCTAssertEqual(owner.places(behind: .settings).map(\.id), ["timeClock", "receipts", "truckStock", "training"])
        let office = PlaceDoors(role: .office, opens: { _ in true })
        XCTAssertEqual(office.door(.place(.team)), .menu)
        XCTAssertEqual(office.door(.local(.team)), .team)
        XCTAssertEqual(office.door(.place(.priceBook)), .settings)
        let tech = PlaceDoors(role: .technician, opens: permitted(.technician))
        XCTAssertNil(tech.door(.place(.money)), "A place a role may not open gets no door")
        XCTAssertEqual(tech.door(.place(.estimates)), .settings, "Without Money in the menu, Estimates is one row away in Settings")
        XCTAssertEqual(tech.door(.place(.drafts)), .messages)
        // Search: every permitted place and every record, the ones no menu lists included.
        let actions = SearchAction.standard(creates: [], settings: nil, places: SearchAction.everyPlace(permitted: { _ in true }),
                                            openPlace: { _ in }, records: LocalWorkspaceSection.allCases, openRecord: { _ in })
        XCTAssertEqual(Set(actions.map(\.id)),
                       Set(MenuItem.allCases.map { "place-\($0.rawValue)" } + LocalWorkspaceSection.allCases.map { "place-local-\($0.rawValue)" }))
        XCTAssertEqual(SearchAction.everyPlace(permitted: permitted(.technician)).count, 9)
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
        XCTAssertEqual(DrawerMotion.panelWidth(screen: 390, accessibilitySize: false), 306, "Paper 29N: the floating panel")
        XCTAssertEqual(DrawerMotion.panelWidth(screen: 402, accessibilitySize: true), 402)
        XCTAssertEqual(DrawerMotion.cornerRadius(topInset: 62), 55)
        XCTAssertEqual(DrawerMotion.cornerRadius(topInset: 47), 44)
    }

    func testMenuPanelFitsInsideAShortLandscapeWindow() {
        XCTAssertEqual(ThorbisMenuMetrics.fittedHeight(estimated: 260, window: 874), 260)
        XCTAssertEqual(ThorbisMenuMetrics.fittedHeight(estimated: 500, window: 874), 460)
        let landscape = ThorbisMenuMetrics.fittedHeight(estimated: 320, window: 402)
        XCTAssertEqual(landscape, 262)
        XCTAssertLessThan(landscape, 402)
        XCTAssertEqual(ThorbisMenuMetrics.fittedHeight(estimated: 80, window: 402), 80)
        XCTAssertEqual(ThorbisMenuMetrics.fittedHeight(estimated: 200, window: 0), 200)
        let compact = ThorbisMenuMetrics.maxHeight(window: 402, compactHeight: true)
        XCTAssertEqual(compact, 212)
        XCTAssertEqual(ThorbisMenuMetrics.maxHeight(window: 874, compactHeight: true), 240,
                       "A stale portrait window height after rotate still caps to the short side")
        XCTAssertEqual(ThorbisMenuMetrics.fittedHeight(estimated: 320, window: 402, compactHeight: true), 212)
    }

    // MARK: Sidebar places (Cream sheet: every place a role can reach, grouped)

    func testWebSidebarUsesActiveWorkspacesAndSingleDestinationRows() {
        let projection = WebSidebarProjection.make(places: [.home, .inbox, .schedule, .jobs, .estimates, .invoices, .customers, .priceBook], current: .estimates)
        XCTAssertEqual(projection.personal, [.home, .inbox, .schedule])
        XCTAssertEqual(projection.groups.first { $0.section == .work }?.items, [.jobs, .estimates, .invoices])
        XCTAssertEqual(projection.groups.first { $0.section == .work }?.expanded, true)
        XCTAssertEqual(projection.groups.first { $0.section == .customers }?.items, [.customers])
        XCTAssertEqual(projection.groups.first { $0.section == .customers }?.expanded, false)
        XCTAssertEqual(projection.groups.first { $0.section == .operations }?.items, [.priceBook])
        XCTAssertFalse(projection.groups.contains { $0.section == .money }, "Unauthorized workspaces do not appear")
        XCTAssertFalse(projection.groups.contains { $0.items.contains(.team) }, "Unauthorized children do not appear")
        let inactive = WebSidebarProjection.make(places: [.jobs, .estimates, .customers, .properties], current: .schedule)
        XCTAssertTrue(inactive.groups.allSatisfy { !$0.expanded })
        let limited = WebSidebarProjection.make(places: [.estimates], current: .estimates)
        XCTAssertEqual(limited.groups.first?.items, [.estimates])
        XCTAssertFalse(limited.groups.first?.expanded ?? true, "A lone child is rendered directly")
    }

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
        // Notification rules and Reports remain reachable places of their own.
        XCTAssertTrue(sections(.owner).places.contains(.notices))
        XCTAssertTrue(sections(.owner).places.contains(.reports))
    }

    func testSidebarGroupsAndOrderFollowTheDesign() {
        let owner = sections(.owner)
        XCTAssertEqual(owner.sections.map { $0.kind.rawValue }, ["Personal", "Work", "Customers", "Money", "Reports", "Operations", "Other"])
        XCTAssertEqual(owner.sections[0].places, [.home, .inbox, .schedule])
        XCTAssertEqual(owner.sections[1].places, [.jobs, .estimates, .invoices, .team])
        XCTAssertEqual(owner.sections[2].places, [.customers, .properties])
        XCTAssertEqual(owner.sections[3].places, [.money])
        XCTAssertEqual(owner.sections[4].places, [.reports])
        XCTAssertEqual(owner.sections[5].places, [.priceBook])
        XCTAssertEqual(owner.sections[6].places, [.billing, .scorecard, .attention, .notices, .drafts, .businessSettings,
                                                  .timeClock, .receipts, .truckStock, .training, .pipeline, .vendors, .marketing])
        let technician = sections(.technician)
        XCTAssertEqual(technician.sections.flatMap(\.places).filter { $0 == .schedule }.count, 1)
        XCTAssertTrue(technician.places.contains(.jobs))
    }

    func testSidebarFollowsAccessAndHiddenPlaces() {
        XCTAssertEqual(MenuItem.drafts.sidebarTitle("Message drafts", localHeading: "On this phone"), "Message drafts · On this phone")
        XCTAssertEqual(MenuItem.drafts.sidebarTitle("Message drafts", localHeading: "On this iPad"), "Message drafts · On this iPad")
        XCTAssertEqual(MenuItem.jobs.sidebarTitle("Jobs", localHeading: "On this iPad"), "Jobs")
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
        XCTAssertNotEqual(company.sections.first?.kind, .pinned, "A company layout made from the owner's defaults adds no Pinned section")
        let ordered = DrawerSections.make(order: [.customers, .jobs], opens: { _ in true })
        XCTAssertEqual(Array(ordered.places.prefix(2)), [.customers, .jobs], "Saved cross-group order is honored")
        XCTAssertEqual(ordered.sections.first?.kind.rawValue, "Your places")
        let reordered = DrawerSections.make(order: [.invoices, .jobs], opens: { _ in true })
        XCTAssertEqual(Array(reordered.places.prefix(2)), [.invoices, .jobs])
        let filtered = DrawerSections.make(pins: [.estimates], explicitPins: true, hidden: [.customers],
                                           order: [.customers, .jobs, .estimates, .invoices],
                                           opens: { $0 != .invoices })
        XCTAssertEqual(filtered.sections.first?.places, [.estimates])
        XCTAssertEqual(filtered.sections.dropFirst().first?.places.first, .jobs)
        XCTAssertFalse(filtered.places.contains(.customers))
        XCTAssertFalse(filtered.places.contains(.invoices))
    }

    func testTodayNumbersCountLeftAndLate() {
        assertTodayNumbers(now: Date(), calendar: .current)
    }

    /// The night the clocks go back (America/New_York, 2026-11-01) has 25 hours: 23:30 is 24.5
    /// hours after midnight, and 01:30 happens twice. Today's numbers still count the right day.
    func testTodayNumbersOnTheNightTheClocksGoBack() throws {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let iso = ISO8601DateFormatter()
        let lateEvening = try XCTUnwrap(iso.date(from: "2026-11-02T04:30:00Z"))  // 23:30 EST, Nov 1
        let firstOneThirty = try XCTUnwrap(iso.date(from: "2026-11-01T05:30:00Z"))  // 01:30 EDT
        let secondOneThirty = try XCTUnwrap(iso.date(from: "2026-11-01T06:30:00Z"))  // 01:30 EST
        let start = eastern.startOfDay(for: lateEvening)
        XCTAssertEqual(eastern.dateInterval(of: .day, for: lateEvening)?.duration, 25 * 3600, "The test needs the 25-hour day")
        for now in [lateEvening, firstOneThirty, secondOneThirty] {
            XCTAssertEqual(eastern.startOfDay(for: now), start)
            assertTodayNumbers(now: now, calendar: eastern)
        }
    }

    /// Two visits shortly before `now` (one done, one late), one shortly after, one canceled and one
    /// for someone else, all inside `now`'s calendar day however long that day is.
    private func assertTodayNumbers(now: Date, calendar: Calendar, line: UInt = #line) {
        let iso = ISO8601DateFormatter()
        func job(_ id: String, _ status: String, hoursFromNow: Double, who: String? = "me") -> Job {
            Job(id: id, customerId: nil, title: id, status: status, createdAt: nil, updatedAt: nil, allowedTransitions: nil,
                scheduledFor: iso.string(from: now.addingTimeInterval(hoursFromNow * 3600)), assignedToUserId: who)
        }
        // Times stay inside today wherever the test runs. The day's end is the next calendar day,
        // not 24 hours on: the day the clocks go back is 25 hours long, the day they go forward 23.
        guard let day = calendar.dateInterval(of: .day, for: now) else { return XCTFail("No day for \(now)", line: line) }
        let before = now.timeIntervalSince(day.start) / 3600
        let after = day.end.timeIntervalSince(now) / 3600
        let jobs = [job("a", "completed", hoursFromNow: -min(before, 1) * 0.5), job("b", "scheduled", hoursFromNow: -min(before, 1) * 0.25),
                    job("c", "dispatched", hoursFromNow: min(after, 1) * 0.5), job("d", "canceled", hoursFromNow: 0),
                    job("e", "scheduled", hoursFromNow: min(after, 1) * 0.5, who: "other")]
        let mine = TodayNumbers.visits(jobs, assignee: "me", now: now, calendar: calendar)
        XCTAssertEqual(mine.map(\.id), ["a", "b", "c"], line: line)
        XCTAssertEqual(TodayNumbers.left(mine), 2, line: line)
        XCTAssertEqual(TodayNumbers.late(mine, now: now), 1, line: line)
        XCTAssertEqual(TodayNumbers.open(jobs), 3, line: line)
        XCTAssertEqual(TodayNumbers.visits(jobs, assignee: nil, now: now, calendar: calendar).count, 4, line: line)
    }
}
