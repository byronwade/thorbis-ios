import XCTest
@testable import Thorbis

final class PrimaryNavigationTests: XCTestCase {
    func testPrimaryTabsMatchNativeThorbisDestinationsInOrder() {
        XCTAssertEqual(PrimaryTab.allCases, [.jobs, .arrive, .inbox])
        XCTAssertEqual(PrimaryTab.allCases.map(\.title), ["Jobs", "Arrive", "Inbox"])
    }

    func testJobsIsTheInitialPrimaryDestination() {
        XCTAssertEqual(PrimaryTab.initial, .jobs)
    }

    func testArriveStartsOnMyDayWhileJobsStartsOnTheFullJobList() {
        XCTAssertEqual(JobsViewMode.arrive.initialFilter, "My Day")
        XCTAssertEqual(JobsViewMode.jobs.initialFilter, "All jobs")
        XCTAssertFalse(JobsViewMode.arrive.showsFilters)
        XCTAssertTrue(JobsViewMode.jobs.showsFilters)
    }

    func testPrimaryDestinationsRemainStableWhenRoleAccessIsLimited() {
        let access = PrimaryTabAccess(canViewJobs: false, canViewStaffNotices: true)

        XCTAssertEqual(PrimaryTab.allCases, [.jobs, .arrive, .inbox])
        XCTAssertFalse(access.canOpen(.jobs))
        XCTAssertFalse(access.canOpen(.arrive))
        XCTAssertTrue(access.canOpen(.inbox))
        XCTAssertEqual(access.unavailableMessage(for: .arrive), "Your role does not allow access to jobs.")
    }
}
