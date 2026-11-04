import XCTest
@testable import Thorbis

@MainActor private final class FakeBoundRecoveryStore: BoundTapRecoveryStoring {
    var value: BoundTapRecovery?
    var saves = 0
    var failOnSave: Int?
    var failRemove = false
    func load() throws -> BoundTapRecovery? { value }
    func create(_ recovery: BoundTapRecovery) throws -> Bool {
        if value != nil { return false }
        try save(recovery)
        return true
    }
    func save(_ recovery: BoundTapRecovery) throws {
        saves += 1
        if saves == failOnSave { throw CancellationError() }
        value = recovery
    }
    func remove() throws { if failRemove { throw CancellationError() }; value = nil }
}

@MainActor final class BoundTapRecoveryTests: XCTestCase {
    private func marker() -> BoundTapRecovery {
        .init(origin: "https://example.test", actorID: "actor", organizationID: "org", invoiceID: "invoice", attemptID: nil, paymentIntentID: nil, amount: nil, currency: nil)
    }
    private func identify(_ marker: BoundTapRecovery) -> BoundTapRecovery {
        var receipt = marker
        receipt.attemptID = "00000000-0000-4000-8000-000000000001"
        receipt.paymentIntentID = "pi_test"
        receipt.amount = 100
        receipt.currency = "USD"
        return receipt
    }
    func testMarkerPrecedesNetworkAndSurvivesLostResponse() async throws {
        let store = FakeBoundRecoveryStore()
        do {
            let _: Int = try await BoundTapRecoveryManager.prepare(store: store, marker: marker(), create: {
                XCTAssertEqual(store.value, self.marker())
                throw CancellationError()
            }, identify: { _, marker in self.identify(marker) })
            XCTFail("Expected missing response")
        } catch {}
        XCTAssertEqual(store.value, marker())
    }
    func testReceiptSavedBeforeReturningAttempt() async throws {
        let store = FakeBoundRecoveryStore()
        let result = try await BoundTapRecoveryManager.prepare(store: store, marker: marker(), create: { 42 }, identify: { _, marker in self.identify(marker) })
        XCTAssertEqual(result, 42)
        XCTAssertEqual(store.value, identify(marker()))
    }
    func testReceiptWriteFailurePreservesInitialMarker() async throws {
        let store = FakeBoundRecoveryStore()
        store.failOnSave = 2
        do {
            _ = try await BoundTapRecoveryManager.prepare(store: store, marker: marker(), create: { 42 }, identify: { _, marker in self.identify(marker) })
            XCTFail("Expected persistence failure")
        } catch {}
        XCTAssertEqual(store.value, marker())
    }
    func testExistingReceiptPreventsCreatingAnotherAttempt() async throws {
        let store = FakeBoundRecoveryStore()
        store.value = identify(marker())
        var created = false
        do {
            _ = try await BoundTapRecoveryManager.prepare(store: store, marker: marker(), create: { created = true; return 42 }, identify: { _, marker in self.identify(marker) })
            XCTFail("Expected outstanding receipt")
        } catch {}
        XCTAssertFalse(created)
    }

    func testReleaseRequiresEvidenceCurrentAuthorityNoSDKAndMatchingReceipt() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        let lease = try BoundTapProcessLease.acquire(path: dir.path)
        defer { lease.close() }
        let store = FakeBoundRecoveryStore(), expected = identify(marker())
        store.value = expected
        XCTAssertEqual(try BoundTapGuardedRelease.apply(enabled: false, verified: true, sdkInitialized: false, current: { true }, lease: lease, store: store, expected: expected), .settledNeedsReview)
        XCTAssertEqual(try BoundTapGuardedRelease.apply(enabled: true, verified: true, sdkInitialized: true, current: { true }, lease: lease, store: store, expected: expected), .restartRequired)
        XCTAssertEqual(try BoundTapGuardedRelease.apply(enabled: true, verified: false, sdkInitialized: false, current: { true }, lease: lease, store: store, expected: expected), .pending)
        XCTAssertEqual(try BoundTapGuardedRelease.apply(enabled: true, verified: true, sdkInitialized: false, current: { false }, lease: lease, store: store, expected: expected), .pending)
        XCTAssertEqual(store.value, expected)
        store.value = marker()
        XCTAssertEqual(try BoundTapGuardedRelease.apply(enabled: true, verified: true, sdkInitialized: false, current: { true }, lease: lease, store: store, expected: expected), .restartRequired)
        store.value = expected
        store.failRemove = true
        XCTAssertThrowsError(try BoundTapGuardedRelease.apply(enabled: true, verified: true, sdkInitialized: false, current: { true }, lease: lease, store: store, expected: expected))
        XCTAssertEqual(store.value, expected)
        store.failRemove = false
        XCTAssertEqual(try BoundTapGuardedRelease.apply(enabled: true, verified: true, sdkInitialized: false, current: { true }, lease: lease, store: store, expected: expected), .confirmed)
        XCTAssertNil(store.value)
    }
}
