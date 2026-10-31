import XCTest
@testable import Thorbis

final class PrimaryNavigationTests: XCTestCase {
    func testPrimaryRootsAreScheduleJobsAndCustomersInOrder() {
        XCTAssertEqual(PrimaryTab.allCases, [.schedule, .jobs, .customers])
        XCTAssertEqual(PrimaryTab.allCases.map(\.title), ["Schedule", "Jobs", "Customers"])
    }

    func testScheduleIsTheInitialPrimaryDestination() {
        XCTAssertEqual(PrimaryTab.initial, .schedule)
        XCTAssertEqual(MenuItem.schedule.drawerTitle, "Today")
        XCTAssertEqual(MenuItem.inbox.drawerTitle, "Inbox")
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
        XCTAssertEqual(DrawerMotion.width(screen: 402, accessibilitySize: false), 318)
        XCTAssertEqual(DrawerMotion.width(screen: 402, accessibilitySize: true), 402)
    }
}
