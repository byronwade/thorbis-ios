import XCTest
@testable import Thorbis

final class CustomerJobDocumentBookTests: XCTestCase {
    func testSelectionKeepsKindAndIdentityWhileMovingWithoutWrapping() {
        let estimate = CustomerJobDocumentID.estimate("same-id")
        let invoice = CustomerJobDocumentID.invoice("same-id")
        var state = CustomerJobDocumentSelection(ids: [estimate, estimate, invoice], selected: estimate)
        XCTAssertEqual(state.ids, [estimate, invoice])
        XCTAssertNil(state.previous)
        XCTAssertEqual(state.next, invoice)
        state.select(invoice)
        XCTAssertEqual(state.position, "2 of 2 documents")
        XCTAssertEqual(state.previous, estimate)
        XCTAssertNil(state.next)
        state.select(.invoice("unrelated"))
        XCTAssertEqual(state.selected, invoice)
    }

    func testRemovingSelectedDocumentNeverReusesItsIndexForAnother() {
        let first = CustomerJobDocumentID.estimate("first")
        let second = CustomerJobDocumentID.estimate("second")
        var state = CustomerJobDocumentSelection(ids: [first, second], selected: second)
        state.reconcile([second, first])
        XCTAssertEqual(state.selected, second)
        XCTAssertEqual(state.position, "1 of 2 documents")
        state.reconcile([first])
        XCTAssertNil(state.selected)
        XCTAssertNil(state.previous)
        XCTAssertNil(state.next)
    }

    func testPrepareFetchKeepsSignedTermsWhenSessionIsNotCurrent() {
        var cached = signedTerms()
        XCTAssertFalse(cached.prepareFetch(fresh: true, inScope: true, status: "approved", sessionCurrent: false))
        XCTAssertEqual(cached, signedTerms())
    }

    func testPrepareFetchKeepsSignedTermsWhenCopyIsStaleOrOutOfScope() {
        var stale = signedTerms()
        XCTAssertFalse(stale.prepareFetch(fresh: false, inScope: true, status: "approved", sessionCurrent: true))
        XCTAssertEqual(stale, signedTerms())
        var foreign = signedTerms()
        XCTAssertFalse(foreign.prepareFetch(fresh: true, inScope: false, status: "approved", sessionCurrent: true))
        XCTAssertEqual(foreign, signedTerms())
    }

    func testPrepareFetchClearsSignedTermsOnlyWhenAnApprovedFetchCanStart() {
        var cached = signedTerms()
        XCTAssertTrue(cached.prepareFetch(fresh: true, inScope: true, status: "approved", sessionCurrent: true))
        XCTAssertNil(cached.receipt)
        XCTAssertNil(cached.issued)
        XCTAssertNil(cached.error)
        var sent = signedTerms()
        XCTAssertTrue(sent.prepareFetch(fresh: true, inScope: true, status: "sent", sessionCurrent: true))
        XCTAssertNil(sent.receipt)
        var draft = signedTerms()
        XCTAssertFalse(draft.prepareFetch(fresh: true, inScope: true, status: "draft", sessionCurrent: true))
        XCTAssertEqual(draft, signedTerms())
    }

    private func signedTerms() -> CustomerEstimateBookCachedTerms {
        let line = FieldLine(id: "plug", description: "New cleanout plug", quantity: 3,
                             unitPrice: FieldMoney(amount: 2500, currency: "USD"), source: nil)
        let issued = CustomerIssuedEstimateRevision(
            id: "00000000-0000-4000-8000-000000000105", estimateId: "00000000-0000-4000-8000-000000000001",
            organizationId: "o", customerId: "c", locationId: nil, revisionNumber: 2, status: "approved",
            title: "Drain repair", lines: [line], options: nil, totalAmount: 7_500, currency: "USD")
        let receipt = CustomerEstimateAcceptanceReceipt(
            id: "00000000-0000-4000-8000-000000000077", estimateId: issued.estimateId, revisionId: issued.id,
            revisionNumber: issued.revisionNumber, contentHash: "signed-content-hash", optionId: nil, optionTitle: nil,
            signerName: "Canonical signer", acceptedAt: "2026-10-29T12:00:00Z", totalAmount: issued.totalAmount,
            currency: issued.currency, lines: issued.lines)
        return CustomerEstimateBookCachedTerms(
            receipt: receipt, issued: issued,
            error: "The signed estimate isn't available. Hand the device back to your technician.")
    }
}
