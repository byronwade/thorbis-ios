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

    func testLegacyHandoffChangesRevisionEvenAfterItCloses() {
        let arbiter = CustomerHandoffArbiter()
        let photoPreparationRevision = arbiter.revision
        let legacy = UUID()
        XCTAssertTrue(arbiter.claim(.legacy(legacy)))
        XCTAssertFalse(arbiter.claim(.photos))
        arbiter.release(.legacy(UUID()))
        XCTAssertNotNil(arbiter.owner)
        arbiter.release(.legacy(legacy))
        XCTAssertNil(arbiter.owner)
        XCTAssertNotEqual(photoPreparationRevision, arbiter.revision)
    }

    func testDocumentsOwnerBlocksPhotosUntilAuthenticatedExit() {
        let arbiter = CustomerHandoffArbiter()
        XCTAssertTrue(arbiter.claim(.documents))
        XCTAssertFalse(arbiter.claim(.photos))
        arbiter.release(.documents)
        XCTAssertTrue(arbiter.claim(.photos))
    }
}
