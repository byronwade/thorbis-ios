import XCTest
@testable import Thorbis

final class CustomerDocumentAmountsTests: XCTestCase {
    func testCustomerEstimateProjectionHidesMaterialsAndFailsClosedOnInvalidValues() throws {
        let work = FieldLine(id: "work", description: "Service", quantity: 1, unitPrice: .init(amount: 14000, currency: "USD"), source: nil)
        var material = FieldLine(id: "material", description: "Private material detail", quantity: 1, unitPrice: .init(amount: 5000, currency: "USD"), source: nil)
        material.showToCustomer = false
        let result = try XCTUnwrap(customerEstimateProjection([work, material], currency: "USD"))
        XCTAssertEqual(result.map(\.description), ["Service", "Materials"])
        XCTAssertEqual(result.last?.unitPrice.amount, 5000)
        XCTAssertEqual(CustomerDocumentAmounts(lines: result, currency: "USD")?.total, 19000)
        let charge = FieldLine(id: "hidden-charge", description: "Hidden charge", quantity: 1, unitPrice: .init(amount: 7000, currency: "USD"), source: nil, showToCustomer: false)
        let credit = FieldLine(id: "hidden-credit", description: "Hidden credit", quantity: 1, unitPrice: .init(amount: -2000, currency: "USD"), source: nil, showToCustomer: false)
        let net = try XCTUnwrap(customerEstimateProjection([work, charge, credit], currency: "USD"))
        XCTAssertEqual(net.map(\.description), ["Service", "Materials"])
        XCTAssertEqual(net.last?.unitPrice.amount, 5000)
        XCTAssertEqual(CustomerDocumentAmounts(lines: [work, charge, credit], currency: "USD")?.credits, -2000)
        XCTAssertEqual(CustomerDocumentAmounts(lines: net, currency: "USD")?.total, 19000)
        material = FieldLine(id: "bad", description: "Secret", quantity: 2, unitPrice: .init(amount: .max, currency: "USD"), source: nil, showToCustomer: false)
        XCTAssertNil(customerEstimateProjection([work, material], currency: "USD"))
        material = FieldLine(id: "bad", description: "Secret", quantity: 1, unitPrice: .init(amount: 1, currency: "EUR"), source: nil, showToCustomer: false)
        XCTAssertNil(customerEstimateProjection([work, material], currency: "USD"))
    }
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
