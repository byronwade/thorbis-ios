import XCTest
@testable import Thorbis

/// "Collected" on Money, Payments and Home counts what each payment still brings in, as the web does.
final class CompanyPaymentTotalsTests: XCTestCase {
    private func payment(_ id: String, amount: Int, refunded: Int = 0, status: String = "recorded") -> CompanyPayment {
        CompanyPayment(id: id, invoiceID: "i", amount: amount, refundedAmount: refunded, method: "cash", status: status,
                       recordedAt: "2026-11-21T12:00:00Z")
    }

    func testAPartRefundCountsWhatIsLeft() {
        XCTAssertEqual(payment("a", amount: 10_000, refunded: 2_500).net, 7_500)
        XCTAssertEqual(payment("b", amount: 10_000).net, 10_000)
        XCTAssertEqual(payment("c", amount: 10_000, refunded: 10_000, status: "refunded").net, 0)
    }

    func testCollectedSumsEveryPaymentNetOfRefunds() {
        let payments = [payment("a", amount: 10_000, refunded: 2_500), payment("b", amount: 4_000),
                        payment("c", amount: 6_000, refunded: 6_000, status: "refunded")]
        XCTAssertEqual(CompanyPayment.collected(payments), 11_500)
        XCTAssertEqual(CompanyPayment.collected([]), 0)
    }

    func testARefundLargerThanThePaymentNeverCountsBelowZero() {
        XCTAssertEqual(payment("a", amount: 1_000, refunded: 1_500).net, 0)
    }
}
