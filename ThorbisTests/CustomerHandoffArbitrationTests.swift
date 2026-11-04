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

    func testLegacyLeaseLivesUntilLastOwnerReleasesIt() async throws {
        let arbiter = CustomerHandoffArbiter()
        let presenter = JobEstimateHandoffPresenter(arbiter: arbiter)
        var detailLease: LegacyCustomerHandoffLease? = try XCTUnwrap(presenter.claimLegacy())
        var coverLease = detailLease
        detailLease = nil
        XCTAssertNotNil(arbiter.owner, "The visible cover still holds the lease")
        XCTAssertFalse(arbiter.claim(.photos))
        coverLease = nil
        for _ in 0..<50 where arbiter.owner != nil { await Task.yield() }
        XCTAssertNil(arbiter.owner, "The last owner releases a destroyed cover's lease")
        XCTAssertTrue(arbiter.claim(.photos))
        _ = coverLease
    }

    func testOldLegacyLeaseCleanupCannotReleaseNewOwner() async throws {
        let arbiter = CustomerHandoffArbiter()
        let presenter = JobEstimateHandoffPresenter(arbiter: arbiter)
        var oldLease: LegacyCustomerHandoffLease? = try XCTUnwrap(presenter.claimLegacy())
        oldLease?.release()
        let newLease = try XCTUnwrap(presenter.claimLegacy())
        oldLease = nil
        await Task.yield()
        XCTAssertNotNil(arbiter.owner)
        XCTAssertFalse(arbiter.claim(.photos))
        newLease.release()
        XCTAssertTrue(arbiter.claim(.photos))
    }

    func testDocumentsOwnerBlocksPhotosUntilAuthenticatedExit() {
        let arbiter = CustomerHandoffArbiter()
        XCTAssertTrue(arbiter.claim(.documents))
        XCTAssertFalse(arbiter.claim(.photos))
        arbiter.release(.documents)
        XCTAssertTrue(arbiter.claim(.photos))
    }
}
