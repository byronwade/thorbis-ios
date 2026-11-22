import XCTest
@testable import Thorbis

/// Money's one "Show to customer" row: where it sits and where Customer view opens from it.
final class JobMoneyCustomerDoorTests: XCTestCase {
    func testWhileTheEstimatesAreReadTheRowWaits() {
        let door = JobMoneyCustomerDoor(estimateCount: 0, estimatesPending: true)
        XCTAssertEqual(door, .hidden, "Its own card would open Customer view at home, then move once estimates arrive")
    }

    func testWithEstimatesTheRowHandsThemOver() {
        let door = JobMoneyCustomerDoor(estimateCount: 2, estimatesPending: false)
        XCTAssertEqual(door, .inEstimatesCard)
        XCTAssertEqual(door.start, .estimates)
    }

    func testWithNoEstimatesTheRowHasItsOwnCardAndOpensHome() {
        // Read and empty, failed, or estimates off for the role: the door stays on Money.
        let door = JobMoneyCustomerDoor(estimateCount: 0, estimatesPending: false)
        XCTAssertEqual(door, .ownCard)
        XCTAssertEqual(door.start, .home)
    }
}
