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

    // MARK: Drawer places by role

    private let everyone = PrimaryTabAccess(canViewJobs: true, canViewCustomers: true)

    private func places(_ role: WorkRole, tabs: [MenuItem]? = nil, explicit: Bool = false, hidden: Set<MenuItem> = [],
                        access: PrimaryTabAccess? = nil, permitted: @escaping (MenuItem) -> Bool = { _ in true }) -> DrawerPlaces {
        DrawerPlaces.make(role: role, tabs: tabs ?? MenuLayout.defaultTabs(for: role, permitted: permitted), explicitPins: explicit,
                          hidden: hidden, order: [], access: access ?? everyone, permitted: permitted)
    }

    func testDrawerPrimaryRowsByRole() {
        XCTAssertEqual(places(.technician).primary, [.schedule, .jobs, .customers, .inbox])
        XCTAssertEqual(places(.office).primary, [.schedule, .jobs, .customers, .money, .inbox])
        XCTAssertEqual(places(.owner).primary, [.home, .jobs, .customers, .money, .inbox],
                       "Owners get Home, which carries the day, instead of a second today row")
        for role in [WorkRole.technician, .office, .owner] {
            let result = places(role)
            XCTAssertLessThanOrEqual(result.primary.count, DrawerPlaces.maxPrimary)
            XCTAssertTrue(result.pinned.isEmpty, "Role defaults never add a Pinned section")
            XCTAssertTrue(Set(result.primary).isDisjoint(with: result.more))
        }
        XCTAssertTrue(places(.owner).more.contains(.schedule), "The owner still reaches the schedule under All places")
        XCTAssertTrue(places(.technician).more.contains(.estimates))
    }

    func testDrawerRowsFollowAccessAndHiddenPlaces() {
        let noJobs = places(.technician, access: PrimaryTabAccess(canViewJobs: false, canViewCustomers: true),
                            permitted: { ![.schedule, .jobs, .inbox].contains($0) })
        XCTAssertEqual(noJobs.primary, [.customers])
        XCTAssertFalse(noJobs.more.contains(.jobs))
        XCTAssertEqual(places(.office, hidden: [.inbox]).primary, [.schedule, .jobs, .customers, .money])
        XCTAssertFalse(places(.office, permitted: { $0 != .money }).primary.contains(.money))
    }

    func testDrawerExplicitPinsJoinThePrimaryListThenOverflowToPinned() {
        let tech = places(.technician, tabs: [.estimates, .schedule], explicit: true)
        XCTAssertEqual(tech.primary, [.schedule, .jobs, .customers, .inbox, .estimates])
        XCTAssertTrue(tech.pinned.isEmpty)
        let office = places(.office, tabs: [.estimates, .invoices], explicit: true)
        XCTAssertEqual(office.primary.count, 5)
        XCTAssertEqual(office.pinned, [.estimates, .invoices])
        XCTAssertFalse(office.more.contains(.estimates))
        let company = DrawerPlaces.make(role: .owner, tabs: [.schedule, .money, .customers], explicitPins: true,
                                        roleDefaults: MenuLayout.defaultTabs(for: .owner, permitted: { _ in true }),
                                        hidden: [], order: [], access: everyone, permitted: { _ in true })
        XCTAssertTrue(company.pinned.isEmpty, "A company layout made from the owner's defaults adds no Pinned Schedule")
        XCTAssertTrue(company.more.contains(.schedule))
        let defaults = places(.owner, tabs: [.home, .schedule, .money, .customers], explicit: false)
        XCTAssertTrue(defaults.pinned.isEmpty)
        XCTAssertFalse(defaults.primary.contains(.schedule))
    }
}
