import XCTest
@testable import Thorbis

final class CustomerDocumentAmountsTests: XCTestCase {
    private func line(_ id: String, quantity: Int = 1, amount: Int, currency: String = "USD") -> FieldLine {
        FieldLine(id: id, description: id, quantity: quantity, unitPrice: .init(amount: amount, currency: currency), source: nil)
    }

    func testDiscountsRemainSeparateFromChargesAndReduceTheActualBalance() throws {
        let amounts = try XCTUnwrap(CustomerDocumentAmounts(lines: [line("Repair", quantity: 2, amount: 12500), line("Member discount", amount: -2500)], currency: "USD", amountPaid: 10000))
        XCTAssertEqual(amounts.subtotal, 25000)
        XCTAssertEqual(amounts.credits, -2500)
        XCTAssertEqual(amounts.total, 22500)
        XCTAssertEqual(amounts.paid, 10000)
        XCTAssertEqual(amounts.due, 12500)
    }

    func testInvoiceHeadlineRespectsDraftPaymentEvidenceAndStaleness() throws {
        let zero = try XCTUnwrap(CustomerDocumentAmounts(lines: [], currency: "USD"))
        let unpaid = try XCTUnwrap(CustomerDocumentAmounts(lines: [line("Work", amount: 10000)], currency: "USD"))
        let partial = try XCTUnwrap(CustomerDocumentAmounts(lines: [line("Work", amount: 10000)], currency: "USD", amountPaid: 4000))
        let paid = try XCTUnwrap(CustomerDocumentAmounts(lines: [line("Work", amount: 10000)], currency: "USD", amountPaid: 10000))
        func summary(_ status: String, _ fresh: Bool, _ amounts: CustomerDocumentAmounts, _ reconciled: Bool) -> CustomerInvoiceBalanceSummary {
            .init(status: status, fresh: fresh, amounts: amounts, historyReconciled: reconciled)
        }
        XCTAssertEqual(summary("draft", true, unpaid, false), .init(title: "Draft total", amount: 10000))
        XCTAssertEqual(summary("issued", true, zero, true), .init(title: "No balance due", amount: 0))
        XCTAssertEqual(summary("issued", true, partial, true), .init(title: "Amount due", amount: 6000))
        XCTAssertEqual(summary("paid", true, paid, true), .init(title: "Paid in full", amount: 0))
        XCTAssertEqual(summary("paid", true, paid, false), .init(title: "No balance due", amount: 0))
        XCTAssertEqual(summary("paid", false, paid, true), .init(title: "Last known balance", amount: 0))
        XCTAssertEqual(summary("void", true, unpaid, false), .init(title: "Voided invoice", amount: nil))
        XCTAssertEqual(summary("void", false, unpaid, false), .init(title: "Last known status: Voided", amount: nil))
    }

    func testUnverifiableMoneyIsNeverPresentedAsZeroOrACollectableBalance() {
        XCTAssertNil(CustomerDocumentAmounts(lines: [line("Overflow", quantity: 2, amount: .max)], currency: "USD"))
        XCTAssertNil(CustomerDocumentAmounts(lines: [line("Wrong currency", amount: 100, currency: "EUR")], currency: "USD"))
        XCTAssertNil(CustomerDocumentAmounts(lines: [line("Negative total", amount: -100)], currency: "USD"))
        XCTAssertNil(CustomerDocumentAmounts(lines: [line("Service", amount: 100)], currency: "USD", amountPaid: -1))
    }
}
