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

    func testUnverifiableMoneyIsNeverPresentedAsZeroOrACollectableBalance() {
        XCTAssertNil(CustomerDocumentAmounts(lines: [line("Overflow", quantity: 2, amount: .max)], currency: "USD"))
        XCTAssertNil(CustomerDocumentAmounts(lines: [line("Wrong currency", amount: 100, currency: "EUR")], currency: "USD"))
        XCTAssertNil(CustomerDocumentAmounts(lines: [line("Negative total", amount: -100)], currency: "USD"))
        XCTAssertNil(CustomerDocumentAmounts(lines: [line("Service", amount: 100)], currency: "USD", amountPaid: -1))
    }
}
