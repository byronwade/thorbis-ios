import XCTest
@testable import Thorbis

@MainActor
final class CustomerHandoffArbitrationTests: XCTestCase {
    func testPhotoOwnerBlocksDelayedEstimateAndOnlyOwnerCanRelease() {
        let arbiter = CustomerHandoffArbiter()
        XCTAssertTrue(arbiter.claim(.photos))
        XCTAssertFalse(arbiter.claim(.documents))
        arbiter.release(.documents)
        XCTAssertFalse(arbiter.claim(.documents))
        arbiter.release(.photos)
        XCTAssertTrue(arbiter.claim(.documents))
    }

    func testDocumentsOwnerBlocksPhotosUntilAuthenticatedExit() {
        let arbiter = CustomerHandoffArbiter()
        XCTAssertTrue(arbiter.claim(.documents))
        XCTAssertFalse(arbiter.claim(.photos))
        arbiter.release(.documents)
        XCTAssertTrue(arbiter.claim(.photos))
    }
}
