import XCTest
@testable import Thorbis

final class CloseoutInvoiceEvidenceTests: XCTestCase {
    private struct Record { let id: String; let version: Int }

    func testMissingInvoiceWithQueuedPaymentMakesEvidenceIncomplete() {
        let listed = [Record(id: "known", version: 1)]
        XCTAssertNil(CloseoutInvoiceEvidence.resolve(listed: listed, paidHere: ["missing"], id: \.id, cached: { _ in nil }))
    }

    func testMissingInvoiceListIsIncompleteEvenIfPaymentInvoiceIsCached() {
        XCTAssertNil(CloseoutInvoiceEvidence.resolve(listed: Optional<[Record]>.none, paidHere: ["known"], id: \.id, cached: { Record(id: $0, version: 1) }))
    }

    func testCompleteEvidenceRetainsNewerCopyAndQueuedInvoice() throws {
        let listed = [Record(id: "known", version: 1)]
        let resolved = try XCTUnwrap(CloseoutInvoiceEvidence.resolve(listed: listed, paidHere: ["extra", "extra"], id: \.id, cached: { Record(id: $0, version: 2) }))
        XCTAssertEqual(Set(resolved.map(\.id)), ["known", "extra"])
        XCTAssertEqual(resolved.first(where: { $0.id == "known" })?.version, 2)
    }

    func testMismatchedScopeMakesEvidenceIncomplete() {
        let listed = [Record(id: "known", version: 1)]
        XCTAssertNil(CloseoutInvoiceEvidence.resolve(listed: listed, paidHere: [], id: \.id, cached: { _ in nil }, valid: { $0.version == 2 }))
    }

    func testRecordedPaymentCannotCoverBalanceAgainWhenProjectionIsUnknown() {
        XCTAssertFalse(CloseoutInvoiceEvidence.covers(due: 100, pending: [], recorded: [100]))
        XCTAssertFalse(CloseoutInvoiceEvidence.covers(due: 100, pending: [50], recorded: [50]))
        XCTAssertTrue(CloseoutInvoiceEvidence.covers(due: 100, pending: [100], recorded: [100]))
    }

    func testPaymentSumRejectsOverflowAndNegativeAmounts() {
        XCTAssertNil(CloseoutInvoiceEvidence.sum([Int.max, 1]))
        XCTAssertNil(CloseoutInvoiceEvidence.sum([10, -1]))
        XCTAssertEqual(CloseoutInvoiceEvidence.sum([10, 15]), 25)
    }

    func testWrongCachedReplacementMakesEvidenceIncomplete() {
        XCTAssertNil(CloseoutInvoiceEvidence.resolve(listed: [Record(id: "known", version: 1)], paidHere: [], id: \.id, cached: { _ in Record(id: "wrong", version: 1) }))
    }

    func testWrongCachedInvoiceDoesNotResolveMissingPayment() {
        XCTAssertNil(CloseoutInvoiceEvidence.resolve(listed: [Record(id: "known", version: 1)], paidHere: ["missing"], id: \.id, cached: { _ in Record(id: "wrong", version: 1) }))
    }
}
