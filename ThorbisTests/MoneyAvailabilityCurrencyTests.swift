import XCTest
@testable import Thorbis

/// Balances and payouts arrive in each currency's smallest unit; the Payouts page and the
/// Payments setup page both show them through `MoneyAvailability.amountText`.
final class MoneyAvailabilityCurrencyTests: XCTestCase {
    func testDecimalPlacesFollowStripe() {
        XCTAssertEqual(MoneyAvailability.minorUnitDigits("USD"), 2)
        XCTAssertEqual(MoneyAvailability.minorUnitDigits("EUR"), 2)
        XCTAssertEqual(MoneyAvailability.minorUnitDigits("JPY"), 0)
        XCTAssertEqual(MoneyAvailability.minorUnitDigits("jpy"), 0)
        XCTAssertEqual(MoneyAvailability.minorUnitDigits("KRW"), 0)
        XCTAssertEqual(MoneyAvailability.minorUnitDigits("KWD"), 3)
        XCTAssertEqual(MoneyAvailability.minorUnitDigits("BHD"), 3)
        // Stripe still sends Icelandic krona and Ugandan shillings in hundredths.
        XCTAssertEqual(MoneyAvailability.minorUnitDigits("ISK"), 2)
        XCTAssertEqual(MoneyAvailability.minorUnitDigits("UGX"), 2)
    }

    func testUgandanShillingsAreDividedByHundred() {
        // Stripe: "to charge 5 UGX, provide an amount value of 500".
        XCTAssertEqual(MoneyAvailability.amountText(500, currency: "UGX"), money(500, currency: "UGX"))
        XCTAssertEqual(MoneyAvailability.amountText(500, currency: "UGX"), Decimal(5).formatted(.currency(code: "UGX")))
    }

    func testTwoDecimalCurrencyReadsAsBefore() {
        XCTAssertEqual(MoneyAvailability.amountText(1000, currency: "USD"), "$10.00")
        XCTAssertEqual(MoneyAvailability.amountText(412_000, currency: "USD"), money(412_000, currency: "USD"))
        XCTAssertEqual(MoneyAvailability.amountText(-1200, currency: "USD"), money(-1200, currency: "USD"))
    }

    func testZeroDecimalCurrencyIsNotDividedByHundred() {
        let text = MoneyAvailability.amountText(1000, currency: "JPY")
        XCTAssertEqual(text, Decimal(1000).formatted(.currency(code: "JPY")))
        XCTAssertTrue(text.contains("1,000"), text)
    }

    func testThreeDecimalCurrencyIsDividedByThousand() throws {
        let text = MoneyAvailability.amountText(1000, currency: "KWD")
        XCTAssertEqual(text, Decimal(1).formatted(.currency(code: "KWD")))
        XCTAssertTrue(text.contains("1.000"), text)
        XCTAssertEqual(MoneyAvailability.amountText(12_345, currency: "KWD"),
                       try XCTUnwrap(Decimal(string: "12.345")).formatted(.currency(code: "KWD")))
    }

    func testDecodedSnapshotShowsEachCurrencyAtItsOwnScale() throws {
        let body = #"{"version":1,"asOf":"2026-10-28T03:00:00.000Z","balances":[{"currency":"USD","available":1000,"pending":0,"explanation":"x"},{"currency":"JPY","available":1000,"pending":0,"explanation":"x"},{"currency":"KWD","available":1000,"pending":0,"explanation":"x"}],"payouts":[{"state":"paid","amount":5000,"currency":"JPY","arrivalDate":"2026-10-27","title":"Paid out","explanation":"x","responsibleActor":"none","providerCode":null}],"attention":null}"#
        let snapshot = try JSONDecoder().decode(MoneyAvailability.self, from: Data(body.utf8))

        let shown = snapshot.balances.map { MoneyAvailability.amountText($0.available, currency: $0.currency) }
        XCTAssertEqual(shown, [
            "$10.00",
            Decimal(1000).formatted(.currency(code: "JPY")),
            Decimal(1).formatted(.currency(code: "KWD")),
        ])
        let payout = try XCTUnwrap(snapshot.payouts.first)
        XCTAssertEqual(MoneyAvailability.amountText(payout.amount, currency: payout.currency),
                       Decimal(5000).formatted(.currency(code: "JPY")))
    }
}
