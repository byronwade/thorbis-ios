import XCTest
@testable import Thorbis

@MainActor
final class TerminalIsolationTests: XCTestCase {
    func testOnlyOneAttemptOwnsTheTerminal() {
        let gate = TerminalIsolation()
        let first = gate.acquire()
        XCTAssertNotNil(first)
        XCTAssertNil(gate.acquire())
        gate.release(first!, uncertain: false)
        XCTAssertNotNil(gate.acquire())
    }

    func testUnknownConfirmationPreventsAnotherAttempt() {
        let gate = TerminalIsolation()
        let first = gate.acquire()!
        gate.release(first, uncertain: true)
        XCTAssertNil(gate.acquire())
        gate.release(UUID(), uncertain: false)
        XCTAssertNil(gate.acquire())
    }

    func testResetDisconnectsBeforeClearingAndAbortsOnFailure() async throws {
        var calls: [String] = []
        try await TerminalIsolation.reset(connected: true, disconnect: { calls.append("disconnect") }, clear: { calls.append("clear") })
        XCTAssertEqual(calls, ["disconnect", "clear"])
        calls = []
        do {
            try await TerminalIsolation.reset(connected: true, disconnect: { calls.append("disconnect"); throw Failure() }, clear: { calls.append("clear") })
            XCTFail("disconnect failure must stop the reset")
        } catch { XCTAssertEqual(calls, ["disconnect"]) }
    }

    func testTokenLocationMustMatchThePinnedIntent() {
        XCTAssertTrue(TerminalIsolation.tokenMatches(expected: "tml_123", actual: "tml_123"))
        XCTAssertFalse(TerminalIsolation.tokenMatches(expected: "tml_123", actual: "tml_other"))
        XCTAssertFalse(TerminalIsolation.tokenMatches(expected: "", actual: ""))
    }

    func testPaymentMustMatchAmountAndCurrencyReviewedByTechnician() {
        let reviewed = FieldMoney(amount: 12_345, currency: "USD")
        XCTAssertTrue(TerminalIsolation.matchesReviewedPayment(reviewed, server: reviewed, stripeAmount: 12_345, stripeCurrency: "usd"))
        XCTAssertFalse(TerminalIsolation.matchesReviewedPayment(reviewed, server: FieldMoney(amount: 12_346, currency: "USD"), stripeAmount: 12_346, stripeCurrency: "usd"))
        XCTAssertFalse(TerminalIsolation.matchesReviewedPayment(reviewed, server: FieldMoney(amount: 12_345, currency: "CAD"), stripeAmount: 12_345, stripeCurrency: "cad"))
        XCTAssertFalse(TerminalIsolation.matchesReviewedPayment(reviewed, server: reviewed, stripeAmount: 12_346, stripeCurrency: "usd"))
        XCTAssertFalse(TerminalIsolation.matchesReviewedPayment(reviewed, server: reviewed, stripeAmount: 12_345, stripeCurrency: "cad"))
        let zero = FieldMoney(amount: 0, currency: "USD")
        XCTAssertFalse(TerminalIsolation.matchesReviewedPayment(zero, server: zero, stripeAmount: 0, stripeCurrency: "usd"))
    }

    func testResetWithoutReaderStillClearsAndClearFailurePropagates() async {
        var calls: [String] = []
        do {
            try await TerminalIsolation.reset(connected: false, disconnect: { calls.append("disconnect") },
                                              clear: { calls.append("clear"); throw Failure() })
            XCTFail("clearing credentials must succeed before a new account can connect")
        } catch {
            XCTAssertEqual(calls, ["clear"])
        }
    }

    private struct Failure: Error {}
}
