import XCTest
@testable import Thorbis

final class BoundTapReconciliationTests: XCTestCase {
    private func receipt() -> BoundTapRecovery {
        .init(origin: "https://example.test", actorID: "actor", organizationID: "org", invoiceID: "invoice", attemptID: "00000000-0000-4000-8000-000000000001", paymentIntentID: "pi_test", amount: 100, currency: "USD")
    }
    private func snapshot() -> BoundTapReconciliationSnapshot {
        .init(origin: "https://example.test", actorID: "actor", organizationID: "org", invoiceID: "invoice", invoiceAmountPaid: 100, currency: "USD", authorized: true, freshAndComplete: true, records: [.init(id: "payment", invoiceID: "invoice", organizationID: "org", idempotencyKey: "tap:invoice:00000000-0000-4000-8000-000000000001", amount: 100, net: 100, currency: "USD", method: "card", status: "recorded")])
    }
    func testExactFreshAttemptCanReconcile() {
        XCTAssertTrue(BoundTapReconciliation.matches(receipt: receipt(), snapshot: snapshot()))
    }
    func testStaleOrUnauthorizedCannotReconcile() {
        var s = snapshot(); s.freshAndComplete = false
        XCTAssertFalse(BoundTapReconciliation.matches(receipt: receipt(), snapshot: s))
        s = snapshot(); s.authorized = false
        XCTAssertFalse(BoundTapReconciliation.matches(receipt: receipt(), snapshot: s))
    }
    func testWrongAttemptOrReceiptCannotReconcile() {
        var s = snapshot(); s.records[0].idempotencyKey = "tap:invoice:other"
        XCTAssertFalse(BoundTapReconciliation.matches(receipt: receipt(), snapshot: s))
        var r = receipt(); r.attemptID = nil
        XCTAssertFalse(BoundTapReconciliation.matches(receipt: r, snapshot: snapshot()))
    }
    func testDifferentActorOrMismatchedTotalCannotReconcile() {
        var s = snapshot(); s.actorID = "other"
        XCTAssertFalse(BoundTapReconciliation.matches(receipt: receipt(), snapshot: s))
        s = snapshot(); s.invoiceAmountPaid = 0
        XCTAssertFalse(BoundTapReconciliation.matches(receipt: receipt(), snapshot: s))
    }
    func testDuplicateReceiptOrWrongWorkspaceCannotReconcile() {
        var s = snapshot(); s.records.append(s.records[0])
        XCTAssertFalse(BoundTapReconciliation.matches(receipt: receipt(), snapshot: s))
        var r = receipt()
        r = .init(origin: r.origin, actorID: r.actorID, organizationID: "other", invoiceID: r.invoiceID,
                  attemptID: r.attemptID, paymentIntentID: r.paymentIntentID, amount: r.amount, currency: r.currency)
        XCTAssertFalse(BoundTapReconciliation.matches(receipt: r, snapshot: snapshot()))
    }
}
