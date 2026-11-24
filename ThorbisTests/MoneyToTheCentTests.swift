import XCTest
@testable import Thorbis

/// Money, Home and the drawer show what is owed to the cent, as the web does. The drawer's
/// count beside Money stays whole dollars, cut toward zero, and says the exact amount aloud.
@MainActor
final class MoneyToTheCentTests: XCTestCase {
    func testDashboardAmountsKeepTheirCents() {
        XCTAssertEqual(money(6_213_951, currency: "USD"), "$62,139.51")
        XCTAssertEqual(money(1_438_050, currency: "USD"), "$14,380.50")
    }

    func testAWholeAmountShowsTwoZeros() {
        XCTAssertEqual(money(1_000_000, currency: "USD"), "$10,000.00")
    }

    func testZeroReadsAsZeroDollarsAndZeroCents() {
        XCTAssertEqual(money(0, currency: "USD"), "$0.00")
    }

    func testANegativeAmountKeepsItsCents() {
        XCTAssertEqual(money(-1_299, currency: "USD"), "-$12.99")
    }

    func testHomeTotalsKeepTheirCents() {
        var owed = HomeAmounts()
        owed.add(1_000_000, "USD")
        owed.add(438_050, "USD")
        XCTAssertEqual(owed.text, "$14,380.50")
    }

    func testHomeTotalsKeepEachCurrencyApartWithCents() {
        var owed = HomeAmounts()
        owed.add(100, "USD")
        owed.add(50_050, "EUR")
        XCTAssertEqual(owed.text, "€500.50 + $1.00")
    }

    func testHomeTotalsShowANegativeBalanceExactly() {
        var owed = HomeAmounts()
        owed.add(-1_299, "USD")
        XCTAssertEqual(owed.text, "-$12.99")
    }

    func testTheDrawerCountCutsTowardZero() {
        XCTAssertEqual(compactMoney(6_213_951), "$62,139")
        XCTAssertEqual(compactMoney(124_099), "$1,240")
        XCTAssertEqual(compactMoney(124_000), "$1,240")
    }

    func testTheDrawerCountCutsANegativeAmountTowardZero() {
        XCTAssertEqual(compactMoney(-124_099), "-$1,240")
    }

    func testTheDrawerCountShowsCentsUnderOneDollar() {
        XCTAssertEqual(compactMoney(50), "$0.50")
        XCTAssertEqual(compactMoney(0), "$0.00")
    }

    func testTheDrawerCountFollowsItsCurrency() {
        XCTAssertEqual(compactMoney(124_099, currency: "EUR"), "€1,240")
    }

    func testTheDrawerSaysTheExactAmountOwed() {
        XCTAssertEqual(PlaceCount.due(6_213_951), PlaceCount(text: "$62,139", spoken: "$62,139.51 due"))
        XCTAssertEqual(PlaceCount.due(50), PlaceCount(text: "$0.50", spoken: "$0.50 due"))
    }

    func testTheDrawerShowsNothingWhenNothingIsOwed() {
        XCTAssertNil(PlaceCount.due(nil))
        XCTAssertNil(PlaceCount.due(0))
        XCTAssertNil(PlaceCount.due(-500))
    }
}
