import XCTest
@testable import Thorbis

/// What a failed refund request proves, read from the errors the API client really throws.
final class RefundSendFailureTests: XCTestCase {
    private let organizationID = "00000000-0000-4000-8000-000000000002"
    private let invoiceID = "00000000-0000-4000-8000-00000000000a"
    private let paymentID = "00000000-0000-4000-8000-00000000000b"
    /// The payment's own retry reference, made at run time.
    private let recordedPaymentReference = UUID().uuidString

    func testRefundOverTheRoleLimitIsRefusedInPlainWords() {
        // The server's body for ForbiddenError from the maxRefundAmount condition.
        let refusal = Problem(title: "authorization", status: 403,
                              detail: "not permitted: invoice.refund (condition_exceeded)", category: "authorization")
        XCTAssertEqual(RefundSendFailure.of(refusal),
                       .refusedUpFront("This refund is more than your role can approve. Ask your office."))
    }

    func testOtherRoleRefusalSaysTheRoleCannotRefund() {
        let refusal = Problem(title: "authorization", status: 403,
                              detail: "not permitted: invoice.refund (no_grant)", category: "authorization")
        XCTAssertEqual(RefundSendFailure.of(refusal), .refused(RefundSendFailure.roleRefusedMessage))
    }

    func testValidationRefusalShowsTheServerReason() {
        let refusal = Problem(title: "validation", status: 400,
                              detail: "validation failed: reason: Invalid length", category: "validation")
        XCTAssertEqual(RefundSendFailure.of(refusal),
                       .refusedUpFront("Thorbis refused this refund: validation failed: reason: Invalid length"))
    }

    func testConflictAndNotFoundAreRefusals() {
        let conflict = Problem(title: "conflict", status: 409,
                               detail: "cannot refund payment in status refunded", category: "conflict")
        XCTAssertEqual(RefundSendFailure.of(conflict),
                       .refused("Thorbis refused this refund: cannot refund payment in status refunded"))
        let missing = Problem(title: "not found", status: 404, detail: nil, category: "not_found")
        XCTAssertEqual(RefundSendFailure.of(missing), .refused("Thorbis refused this refund: not found"))
    }

    func testRequestTimeoutAndRateLimitStayUnconfirmed() {
        XCTAssertEqual(RefundSendFailure.of(Problem(title: "validation", status: 408, detail: "body late")), .unconfirmed)
        XCTAssertEqual(RefundSendFailure.of(Problem(title: "rate limited", status: 429, detail: "slow down")), .unconfirmed)
    }

    func testServerFailuresStayUnconfirmed() {
        for status in [500, 502, 503, 504] {
            XCTAssertEqual(RefundSendFailure.of(Problem(title: "Temporary failure", status: status, detail: "Try again.")),
                           .unconfirmed, "\(status)")
        }
    }

    func testAnUnreadableSuccessStaysUnconfirmed() {
        XCTAssertEqual(RefundSendFailure.of(Problem(title: "Invalid refund response", status: 200, detail: "x")), .unconfirmed)
        XCTAssertEqual(RefundSendFailure.of(Problem(title: "Invalid refund response", status: 202, detail: "x")), .unconfirmed)
        XCTAssertEqual(RefundSendFailure.of(Problem(title: "Invalid refund response", status: nil, detail: "x")), .unconfirmed)
    }

    func testCancellationStaysUnconfirmed() {
        XCTAssertEqual(RefundSendFailure.of(CancellationError()), .unconfirmed)
    }

    func testFailuresBeforeAConnectionWereNotSent() {
        let codes: [URLError.Code] = [.notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff,
                                      .cannotFindHost, .cannotConnectToHost]
        for code in codes {
            XCTAssertEqual(RefundSendFailure.of(URLError(code)), .notSent(RefundSendFailure.notSentMessage), "\(code)")
        }
        // As APIClient throws it: a "Network error" marked as never sent.
        let offline = Problem(title: "Network error", status: nil, detail: "This needs a connection.", neverSent: true)
        XCTAssertEqual(RefundSendFailure.of(offline), .notSent(RefundSendFailure.notSentMessage))
    }

    func testATimeoutOrDroppedConnectionIsNotNotSent() {
        XCTAssertEqual(RefundSendFailure.of(URLError(.timedOut)), .unconfirmed)
        XCTAssertEqual(RefundSendFailure.of(URLError(.networkConnectionLost)), .unconfirmed)
        let timedOut = Problem(title: "Network error", status: nil, detail: "This needs a connection.", neverSent: false)
        XCTAssertEqual(RefundSendFailure.of(timedOut), .unconfirmed)
    }

    func testADraftRefusedUpFrontStaysADraftForAnyPayment() {
        XCTAssertEqual(RefundSendFailure.refusedUpFront("no").state(sentFrom: .draft, inOneStep: false), .draft)
        XCTAssertEqual(RefundSendFailure.refusedUpFront("no").state(sentFrom: .draft, inOneStep: true), .draft)
    }

    func testACashOrCheckDraftThatWasRefusedOrNotSentStaysADraft() {
        XCTAssertEqual(RefundSendFailure.refused("no").state(sentFrom: .draft, inOneStep: true), .draft)
        XCTAssertEqual(RefundSendFailure.notSent("no").state(sentFrom: .draft, inOneStep: true), .draft)
        XCTAssertEqual(RefundSendFailure.unconfirmed.state(sentFrom: .draft, inOneStep: true), .uncertain)
    }

    func testACardDraftThatWasRefusedOrNotSentBecomesUnconfirmed() {
        // The server can refuse after the card company refunded, and iOS can call a request in flight offline.
        XCTAssertEqual(RefundSendFailure.refused("no").state(sentFrom: .draft, inOneStep: false), .uncertain)
        XCTAssertEqual(RefundSendFailure.notSent("no").state(sentFrom: .draft, inOneStep: false), .uncertain)
        XCTAssertEqual(RefundSendFailure.unconfirmed.state(sentFrom: .draft, inOneStep: false), .uncertain)
    }

    func testAnUnconfirmedRefundStaysUnconfirmedWhateverTheFailure() {
        // The server checks the role before it looks for an earlier refund.
        let failures = [RefundSendFailure.refusedUpFront("no"), .refused("no"), .notSent("no"), .unconfirmed]
        for failure in failures {
            for inOneStep in [false, true] {
                XCTAssertEqual(failure.state(sentFrom: .uncertain, inOneStep: inOneStep), .uncertain, "\(failure)")
            }
        }
    }

    func testAnAcceptedRefundKeepsItsStateWhateverTheFailure() {
        let failures = [RefundSendFailure.refusedUpFront("no"), .refused("no"), .notSent("no"), .unconfirmed]
        for failure in failures {
            for inOneStep in [false, true] {
                XCTAssertEqual(failure.state(sentFrom: .pending, inOneStep: inOneStep), .pending)
                XCTAssertEqual(failure.state(sentFrom: .reconciliationRequired, inOneStep: inOneStep), .reconciliationRequired)
            }
        }
    }

    func testARefusalThatLeavesTheRefundUnconfirmedSaysSo() {
        let refused = RefundSendFailure.refused("Your role can\u{2019}t refund this payment. Ask your office.")
        let error = Problem(title: "authorization", status: 403, detail: "x", category: "authorization")
        XCTAssertEqual(refused.message(for: error, sentFrom: .uncertain, next: .uncertain),
                       "Your role can\u{2019}t refund this payment. Ask your office. \(RefundSendFailure.stillUnconfirmedNote)")
        XCTAssertEqual(refused.message(for: error, sentFrom: .draft, next: .draft),
                       "Your role can\u{2019}t refund this payment. Ask your office.")
    }

    func testOnlyADraftSaysTheRefundWasNotSent() {
        let offline = RefundSendFailure.notSent(RefundSendFailure.notSentMessage)
        let error = URLError(.notConnectedToInternet)
        XCTAssertEqual(offline.message(for: error, sentFrom: .draft, next: .draft), RefundSendFailure.notSentMessage)
        XCTAssertEqual(offline.message(for: error, sentFrom: .draft, next: .uncertain), RefundSendFailure.lostConnectionMessage)
        XCTAssertEqual(offline.message(for: error, sentFrom: .uncertain, next: .uncertain), RefundSendFailure.unchangedOfflineMessage)
        XCTAssertEqual(offline.message(for: error, sentFrom: .pending, next: .pending), RefundSendFailure.unchangedOfflineMessage)
    }

    func testOnlyCashAndCheckAreRefundedInOneStep() {
        XCTAssertTrue(RefundPaymentRead.refundsInOneStep(payment(method: "cash")))
        XCTAssertTrue(RefundPaymentRead.refundsInOneStep(payment(method: "check")))
        for method in ["card", "ach", "financing", ""] {
            XCTAssertFalse(RefundPaymentRead.refundsInOneStep(payment(method: method)), method)
        }
    }

    func testAFreshReadOfAnUnrefundedPaymentSaysNotRefunded() {
        let mine = payment()
        guard case .notRefunded = RefundPaymentRead.verdict([payment(id: "00000000-0000-4000-8000-00000000000c"), mine], for: mine) else {
            return XCTFail("expected not refunded")
        }
    }

    func testAFreshReadOfARefundedPaymentEndsTheRefund() {
        let mine = payment()
        guard case .refunded = RefundPaymentRead.verdict([payment(status: .refunded, refundedAmount: 2_500)], for: mine) else {
            return XCTFail("expected refunded")
        }
    }

    func testAFreshReadThatDoesNotShowThePaymentClearlyAllowsNothing() {
        let mine = payment()
        let cases: [[FieldPaymentRecord]] = [
            [],
            [payment(refundedAmount: 1)],
            [payment(organizationID: "00000000-0000-4000-8000-000000000009")],
            [payment(invoiceID: "00000000-0000-4000-8000-000000000009")],
            [mine, mine],
        ]
        for payments in cases {
            guard case .unknown = RefundPaymentRead.verdict(payments, for: mine) else {
                return XCTFail("expected unknown for \(payments.count) payments")
            }
        }
    }

    private func payment(id: String? = nil, organizationID: String? = nil, invoiceID: String? = nil,
                         method: String = "card", status: FieldPaymentStatus = .recorded,
                         refundedAmount: Int? = nil) -> FieldPaymentRecord {
        FieldPaymentRecord(
            id: id ?? paymentID,
            organizationId: organizationID ?? self.organizationID,
            invoiceId: invoiceID ?? self.invoiceID,
            amount: FieldMoney(amount: 2_500, currency: "USD"),
            method: method,
            status: status,
            collectionEvidence: .unclassifiedLegacy,
            idempotencyKey: recordedPaymentReference,
            recordedAt: "2026-10-26T12:30:00Z",
            refundedAmount: refundedAmount,
            netAmount: nil,
            refundedAt: nil
        )
    }
}
