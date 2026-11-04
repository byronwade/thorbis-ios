import XCTest
@testable import Thorbis

@MainActor private final class FakeBoundRecoveryStore: BoundTapRecoveryStoring {
    var value: BoundTapRecovery?
    var saves = 0
    var failOnSave: Int?
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
    func remove() throws { value = nil }
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
}
