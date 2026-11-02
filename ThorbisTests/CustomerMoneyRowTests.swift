import XCTest
@testable import Thorbis

final class CustomerMoneyRowTests: XCTestCase {
    func testEstimateOptionsAreNotPresentedAsOnePrice() {
        let row = CustomerMoneyRow.estimate(PaperPreview.estimate)
        XCTAssertEqual(row.reference, "EST-2218")
        XCTAssertEqual(row.meta, "1 option")
        XCTAssertNil(row.amount)
        XCTAssertNil(row.amountNote)
    }

    func testInvoiceShowsTotalRatherThanBalanceAfterPartialPayment() throws {
        let invoice = try changingInvoice { $0["amountPaid"] = 10_000 }
        let row = CustomerMoneyRow.invoice(invoice)
        XCTAssertEqual(row.reference, "INV-2209")
        XCTAssertEqual(row.amount, money(34_000, currency: "USD"))
        XCTAssertEqual(row.amountNote, "Last known total")
    }

    func testInvoiceTotalIsLabeledAsLastKnownWhenSourceFreshnessIsUnknown() {
        let row = CustomerMoneyRow.invoice(PaperPreview.issuedInvoice)
        XCTAssertEqual(row.amountNote, "Last known total")
    }

    func testVoidAndUnsupportedCurrencyDoNotPresentATotal() throws {
        let void = try changingInvoice { $0["status"] = "void" }
        let otherCurrency = try changingInvoice { $0["currency"] = "JPY" }
        XCTAssertNil(CustomerMoneyRow.invoice(void).amount)
        XCTAssertNil(CustomerMoneyRow.invoice(otherCurrency).amount)
    }

    func testOverflowDoesNotPresentATotal() throws {
        let invoice = try changingInvoice { json in
            json["lines"] = [["id": "overflow", "description": "Work", "quantity": 2,
                              "unitPrice": ["amount": Int.max, "currency": "USD"]]]
        }
        XCTAssertNil(CustomerMoneyRow.invoice(invoice).amount)
    }

    private func changingInvoice(_ edit: (inout [String: Any]) -> Void) throws -> InvoiceRecord {
        let data = try JSONEncoder().encode(PaperPreview.issuedInvoice)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        edit(&json)
        return try JSONDecoder().decode(InvoiceRecord.self, from: JSONSerialization.data(withJSONObject: json))
    }
}
