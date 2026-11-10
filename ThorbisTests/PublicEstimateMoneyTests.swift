import XCTest
@testable import Thorbis

final class PublicEstimateMoneyTests: XCTestCase {
    func testUSDMinorUnitsAndLegacyIntegralDecimals() {
        XCTAssertEqual(PublicEstimateMoney.format(4200, currency: "USD"), "$42.00")
        XCTAssertEqual(PublicEstimateMoney.format(4200.0, currency: "USD"), "$42.00")
        XCTAssertEqual(PublicEstimateMoney.format(-500, currency: "USD"), "-$5.00")
        XCTAssertEqual(PublicEstimateMoney.format(9_007_199_254_740_991, currency: "USD"), "$90,071,992,547,409.91")
    }

    func testInvalidOrUnsupportedAmountsAreUnavailable() {
        XCTAssertNil(PublicEstimateMoney.format(42.5, currency: "USD"))
        XCTAssertNil(PublicEstimateMoney.format(.infinity, currency: "USD"))
        XCTAssertNil(PublicEstimateMoney.format(9_007_199_254_740_992, currency: "USD"))
        XCTAssertNil(PublicEstimateMoney.format(4200, currency: "EUR"))
    }

    func testLineMultiplicationUsesExactMinorUnits() {
        XCTAssertEqual(PublicEstimateMoney.lineTotal(quantity: 2, unitPrice: 4200), 8400)
        XCTAssertEqual(PublicEstimateMoney.lineTotal(quantity: 2, unitPrice: -500), -1000)
        XCTAssertNil(PublicEstimateMoney.lineTotal(quantity: 2.5, unitPrice: -500))
        XCTAssertNil(PublicEstimateMoney.lineTotal(quantity: 100_001, unitPrice: 1))
        XCTAssertNil(PublicEstimateMoney.lineTotal(quantity: 0.5, unitPrice: 1))
        XCTAssertNil(PublicEstimateMoney.lineTotal(quantity: 2, unitPrice: 9_007_199_254_740_991))
    }
}
