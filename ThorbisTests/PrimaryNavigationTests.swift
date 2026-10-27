import XCTest
@testable import Thorbis

final class PrimaryNavigationTests: XCTestCase {
    func testPrimaryTabsMatchPaperTechnicianDockInOrder() {
        XCTAssertEqual(PrimaryTab.allCases, [.schedule, .jobs, .customers, .more, .search])
        XCTAssertEqual(PrimaryTab.allCases.map(\.title), ["Schedule", "Jobs", "Customers", "More", "Search"])
    }

    func testScheduleIsTheInitialPrimaryDestination() {
        XCTAssertEqual(PrimaryTab.initial, .schedule)
    }

    func testPrimaryDestinationsRemainStableWhenRoleAccessIsLimited() {
        let access = PrimaryTabAccess(canViewJobs: false, canViewCustomers: true)

        XCTAssertEqual(PrimaryTab.allCases, [.schedule, .jobs, .customers, .more, .search])
        XCTAssertFalse(access.canOpen(.schedule))
        XCTAssertFalse(access.canOpen(.jobs))
        XCTAssertTrue(access.canOpen(.customers))
        XCTAssertTrue(access.canOpen(.more))
        XCTAssertTrue(access.canOpen(.search))
        XCTAssertEqual(access.unavailableMessage(for: .schedule), "Your role does not allow access to jobs.")
        XCTAssertEqual(PrimaryTabAccess(canViewJobs: true, canViewCustomers: false).unavailableMessage(for: .customers),
                       "Your role does not allow access to customers.")
    }
}
