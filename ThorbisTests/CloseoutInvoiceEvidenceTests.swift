import XCTest
@testable import Thorbis

final class CloseoutInvoiceEvidenceTests: XCTestCase {
    private struct Record: Equatable { let id: String; let version: Int }

    func testMissingInvoiceWithQueuedPaymentMakesEvidenceIncomplete() {
        let listed = [Record(id: "known", version: 1)]
        XCTAssertNil(CloseoutInvoiceEvidence.resolve(listed: listed, paidHere: ["missing"], id: \.id, cached: { _ in nil }, equivalent: ==))
    }

    func testMissingInvoiceListIsIncompleteEvenIfPaymentInvoiceIsCached() {
        XCTAssertNil(CloseoutInvoiceEvidence.resolve(listed: Optional<[Record]>.none, paidHere: ["known"], id: \.id, cached: { Record(id: $0, version: 1) }, equivalent: ==))
    }

    func testCompleteMatchingEvidenceIncludesQueuedInvoice() throws {
        let listed = [Record(id: "known", version: 1)]
        let resolved = try XCTUnwrap(CloseoutInvoiceEvidence.resolve(listed: listed, paidHere: ["extra", "extra"], id: \.id, cached: { Record(id: $0, version: $0 == "known" ? 1 : 2) }, equivalent: ==))
        XCTAssertEqual(Set(resolved.map(\.id)), ["known", "extra"])
        XCTAssertEqual(resolved.first(where: { $0.id == "known" })?.version, 1)
    }

    func testMismatchedScopeMakesEvidenceIncomplete() {
        let listed = [Record(id: "known", version: 1)]
        XCTAssertNil(CloseoutInvoiceEvidence.resolve(listed: listed, paidHere: [], id: \.id, cached: { _ in nil }, equivalent: ==, valid: { $0.version == 2 }))
    }

    func testRecordedPaymentCannotCoverBalanceAgainWhenProjectionIsUnknown() {
        XCTAssertFalse(CloseoutInvoiceEvidence.covers(due: 100, pending: [], recorded: [100]))
        XCTAssertFalse(CloseoutInvoiceEvidence.covers(due: 100, pending: [50], recorded: [50]))
        XCTAssertTrue(CloseoutInvoiceEvidence.covers(due: 100, pending: [100], recorded: [100]))
    }

    func testInvoiceAmountsRejectOverflowAndWrongCurrency() {
        let overflow = FieldLine(id: "1", description: "Work", quantity: Int.max,
                                 unitPrice: FieldMoney(amount: 2, currency: "USD"), source: nil)
        let wrongCurrency = FieldLine(id: "2", description: "Work", quantity: 1,
                                      unitPrice: FieldMoney(amount: 100, currency: "EUR"), source: nil)
        XCTAssertNil(CustomerDocumentAmounts(lines: [overflow], currency: "USD"))
        XCTAssertNil(CustomerDocumentAmounts(lines: [wrongCurrency], currency: "USD"))
    }

    func testInvoiceAmountsAccountForDiscountsAndPayments() throws {
        let charge = FieldLine(id: "1", description: "Work", quantity: 1,
                               unitPrice: FieldMoney(amount: 1000, currency: "USD"), source: nil)
        let discount = FieldLine(id: "2", description: "Discount", quantity: 1,
                                 unitPrice: FieldMoney(amount: -200, currency: "USD"), source: nil)
        let amounts = try XCTUnwrap(CustomerDocumentAmounts(lines: [charge, discount], currency: "USD", amountPaid: 300))
        XCTAssertEqual(amounts.due, 500)
    }

    func testOnlyMatchingActorWorkspaceJobInvoiceAndCashOrCheckCanCover() {
        let valid = CloseoutInvoiceEvidence.PendingPayment(actorID: "actor", organizationID: "org", jobID: "job", invoiceID: "invoice", method: "cash", amount: 100)
        let invalid = [
            CloseoutInvoiceEvidence.PendingPayment(actorID: "other", organizationID: "org", jobID: "job", invoiceID: "invoice", method: "cash", amount: 100),
            .init(actorID: "actor", organizationID: "other", jobID: "job", invoiceID: "invoice", method: "cash", amount: 100),
            .init(actorID: "actor", organizationID: "org", jobID: "other", invoiceID: "invoice", method: "cash", amount: 100),
            .init(actorID: "actor", organizationID: "org", jobID: nil, invoiceID: "invoice", method: "cash", amount: 100),
            .init(actorID: "actor", organizationID: "org", jobID: "job", invoiceID: "other", method: "cash", amount: 100),
            .init(actorID: "actor", organizationID: "org", jobID: "job", invoiceID: "invoice", method: "card", amount: 100),
            .init(actorID: "actor", organizationID: "org", jobID: "job", invoiceID: "invoice", method: "cash", amount: -1)
        ]
        let check = CloseoutInvoiceEvidence.PendingPayment(actorID: "actor", organizationID: "org", jobID: "job", invoiceID: "invoice", method: "check", amount: 50)
        XCTAssertEqual(CloseoutInvoiceEvidence.pendingAmounts([valid, check], actorID: "actor", organizationID: "org", jobID: "job", invoiceID: "invoice"), [100, 50])
        for item in invalid {
            XCTAssertNil(CloseoutInvoiceEvidence.pendingAmounts([valid, item], actorID: "actor", organizationID: "org", jobID: "job", invoiceID: "invoice"))
        }
    }

    func testUnassociatedLegacyPaymentKeepsJobCoverageUnknown() {
        XCTAssertTrue(CloseoutInvoiceEvidence.hasUnassociatedPayments(["another-job", nil]))
        XCTAssertFalse(CloseoutInvoiceEvidence.hasUnassociatedPayments(["another-job", "job"]))
    }

    func testPaymentSumRejectsOverflowAndNegativeAmounts() {
        XCTAssertNil(CloseoutInvoiceEvidence.sum([Int.max, 1]))
        XCTAssertNil(CloseoutInvoiceEvidence.sum([10, -1]))
        XCTAssertEqual(CloseoutInvoiceEvidence.sum([10, 15]), 25)
    }

    func testDisagreeingListAndIndividualInvoiceMakesEvidenceIncomplete() {
        let listed = [Record(id: "known", version: 2)]
        XCTAssertNil(CloseoutInvoiceEvidence.resolve(listed: listed, paidHere: [], id: \.id,
            cached: { Record(id: $0, version: 1) }, equivalent: ==))
    }

    func testWrongCachedReplacementMakesEvidenceIncomplete() {
        XCTAssertNil(CloseoutInvoiceEvidence.resolve(listed: [Record(id: "known", version: 1)], paidHere: [], id: \.id, cached: { _ in Record(id: "wrong", version: 1) }, equivalent: ==))
    }

    func testWrongCachedInvoiceDoesNotResolveMissingPayment() {
        XCTAssertNil(CloseoutInvoiceEvidence.resolve(listed: [Record(id: "known", version: 1)], paidHere: ["missing"], id: \.id, cached: { _ in Record(id: "wrong", version: 1) }, equivalent: ==))
    }
}
