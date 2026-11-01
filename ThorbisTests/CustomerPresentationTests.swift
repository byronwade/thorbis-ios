import XCTest
@testable import Thorbis

final class CustomerPresentationTests: XCTestCase {
    private func line(_ id: String, _ quantity: Int, _ cents: Int) -> FieldLine {
        FieldLine(id: id, description: "Line \(id)", quantity: quantity, unitPrice: FieldMoney(amount: cents, currency: "USD"), source: nil)
    }

    private func estimate(status: String = "sent", options: [FieldEstimateOption]? = nil) -> EstimateRecord {
        EstimateRecord(id: "00000000-0000-4000-8000-000000000001", organizationId: "o", customerId: "c", createdByUserId: "u",
                       locationId: nil, status: status, currentRevisionNumber: 2, title: "AC repair",
                       lines: [line("a", 2, 12_000), line("b", 1, 24_000)], options: options,
                       createdAt: "2026-10-28T00:00:00Z", updatedAt: "2026-10-28T00:00:00Z",
                       sentAt: nil, approvedAt: nil, declinedAt: nil)
    }

    private let options = [
        FieldEstimateOption(id: "good", title: "Repair", description: "", lines: [], totalAmount: 48_000, currency: "USD"),
        FieldEstimateOption(id: "better", title: "Better", description: "", lines: [], totalAmount: 248_000, currency: "USD"),
    ]

    func testSingleScopeOpensOnTheReviewWithItsOwnTotal() {
        let flow = CustomerEstimateFlow(estimate: estimate())
        XCTAssertEqual(flow.step, .review)
        XCTAssertTrue(flow.canReview)
        XCTAssertEqual(flow.total, 48_000)
        XCTAssertEqual(flow.choiceName, "AC repair")
        XCTAssertEqual(flow.approveTitle, "Approve and sign · \(money(48_000, currency: "USD"))")
    }

    func testOptionsMustBeChosenBeforeTheReviewAndTheCommitNamesTheAmount() {
        var flow = CustomerEstimateFlow(estimate: estimate(options: options))
        XCTAssertEqual(flow.step, .choose)
        XCTAssertFalse(flow.canReview)
        flow.review()
        XCTAssertEqual(flow.step, .choose, "choosing is required before reviewing")
        XCTAssertEqual(flow.reviewTitle, "Choose an option")

        flow.choose("better")
        XCTAssertEqual(flow.reviewTitle, "Review Better · \(money(248_000, currency: "USD"))")
        flow.review()
        XCTAssertEqual(flow.step, .review)
        XCTAssertEqual(flow.total, 248_000)
        XCTAssertEqual(flow.choiceName, "Better")

        flow.step = .sign
        flow.back()
        XCTAssertEqual(flow.step, .review)
        flow.back()
        XCTAssertEqual(flow.step, .choose)
    }

    func testAnApprovedEstimateOpensOnTheConfirmation() {
        XCTAssertEqual(CustomerEstimateFlow(estimate: estimate(status: "approved")).step, .done)
    }

    func testCanonicalRevisionReplacesCallerTermsBeforeReview() throws {
        var flow = CustomerEstimateFlow(estimate: estimate())
        try flow.useIssuedRevision(issued())
        XCTAssertEqual(flow.choiceName, "Drain repair")
        XCTAssertEqual(flow.lines.first?.description, "New cleanout plug")
        XCTAssertEqual(flow.lines.first?.quantity, 3)
        XCTAssertEqual(flow.total, 7_500)
        XCTAssertEqual(flow.step, .review)
    }

    func testExistingChoiceKeepsItsIdentityWithCanonicalDetails() throws {
        var flow = CustomerEstimateFlow(estimate: estimate(options: options))
        flow.choose("better")
        flow.review()
        let canonical = FieldEstimateOption(id: "better", title: "Repair with protection", description: "Reviewed work",
                                            lines: [line("current", 1, 99_900)], totalAmount: 99_900, currency: "USD")
        try flow.useIssuedRevision(issued(options: [canonical]))
        XCTAssertEqual(flow.selectedOptionID, "better")
        XCTAssertEqual(flow.choiceName, "Repair with protection")
        XCTAssertEqual(flow.lines.first?.id, "current")
        XCTAssertEqual(flow.total, 99_900)
        XCTAssertEqual(flow.step, .review)
    }

    func testRemovedChoiceRequiresCustomerToChooseAgain() throws {
        var flow = CustomerEstimateFlow(estimate: estimate(options: options))
        flow.choose("better")
        flow.review()
        try flow.useIssuedRevision(issued(options: [options[0]]))
        XCTAssertNil(flow.selectedOptionID)
        XCTAssertEqual(flow.step, .choose)
        XCTAssertFalse(flow.canReview)
        XCTAssertNil(flow.total)
    }

    private func issued(options: [FieldEstimateOption] = []) -> CustomerIssuedEstimateRevision {
        CustomerIssuedEstimateRevision(id: "00000000-0000-4000-8000-000000000105", estimateId: "00000000-0000-4000-8000-000000000001",
                                      organizationId: "o", customerId: "c", locationId: nil, revisionNumber: 2, status: "issued",
                                      title: "Drain repair", lines: [FieldLine(id: "plug", description: "New cleanout plug", quantity: 3,
                                      unitPrice: FieldMoney(amount: 2500, currency: "USD"), source: nil)], options: options,
                                      totalAmount: 7_500, currency: "USD")
    }

    func testTheSignatureHintSaysWhatIsMissing() {
        XCTAssertEqual(customerSignatureHint(name: " ", hasInk: false), "Type your name and sign to finish.")
        XCTAssertEqual(customerSignatureHint(name: "", hasInk: true), "Type your name to finish.")
        XCTAssertEqual(customerSignatureHint(name: "Dana", hasInk: false), "Sign in the box to finish.")
        XCTAssertNil(customerSignatureHint(name: "Dana", hasInk: true))
    }

    func testCustomerTypeStepsUpOnIPad() {
        XCTAssertEqual(CustomerType(.compact).body, 20)
        XCTAssertEqual(CustomerType(.regular).body, 22)
        XCTAssertEqual(CustomerType(.compact).total, 34)
        XCTAssertEqual(CustomerType(nil).small, 17)
        XCTAssertEqual(CustomerType(.regular).target, 56)
    }

    func testInkPresenceIgnoresTaps() {
        XCTAssertFalse(SignatureInk.hasInk([[CGPoint(x: 1, y: 1)]]))
        XCTAssertTrue(SignatureInk.hasInk([[CGPoint(x: 1, y: 1), CGPoint(x: 4, y: 4)]]))
    }

    func testSavingsCountOnlyPriceBookLinesChargedBelowList() {
        let member = FieldLine(id: "m", description: "Tune-up", quantity: 2, unitPrice: FieldMoney(amount: 17_000, currency: "USD"),
                               source: FieldLineSource(kind: "price_book", originalUnitPrice: FieldMoney(amount: 20_000, currency: "USD")))
        let marked = FieldLine(id: "u", description: "Filter", quantity: 1, unitPrice: FieldMoney(amount: 5_000, currency: "USD"),
                               source: FieldLineSource(kind: "price_book", originalUnitPrice: FieldMoney(amount: 4_000, currency: "USD")))
        let invoiced = FieldLine(id: "i", description: "Tune-up", quantity: 1, unitPrice: FieldMoney(amount: 17_000, currency: "USD"),
                                 source: FieldLineSource(kind: "estimate", estimateLineSource: FieldEstimateLineSourceSnapshot(
                                     kind: "price_book", originalUnitPrice: FieldMoney(amount: 20_000, currency: "USD"))))
        let lines = [member, marked, invoiced, line("x", 1, 9_000)]
        XCTAssertEqual(customerSavings(lines), 9_000)
        XCTAssertEqual(customerSavingsRows(lines, currency: "USD", isMember: true),
                       [CustomerAmountRow(label: "Member savings", amount: "−\(money(9_000, currency: "USD"))", emphasis: false)])
        XCTAssertEqual(customerSavingsRows(lines, currency: "USD", isMember: false).first?.label, "Savings")
        XCTAssertTrue(customerSavingsRows([marked, line("x", 1, 9_000)], currency: "USD", isMember: true).isEmpty)
    }
}
