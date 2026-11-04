import XCTest

final class CloseoutEvidenceUITests: XCTestCase {
    func testCompletePendingPaymentSatisfiesMountedChecklist() {
        let app = launch("pending")
        XCTAssertTrue(app.staticTexts["1 of 1"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Waiting to sync"].exists)
    }

    func testMissingQueuedInvoiceKeepsMountedChecklistBlocked() {
        let app = launch("missing")
        XCTAssertTrue(app.staticTexts["0 of 1"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Waiting to sync"].exists)
    }

    func testForeignInvoiceKeepsMountedChecklistBlocked() {
        let app = launch("foreign")
        XCTAssertTrue(app.staticTexts["0 of 1"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Waiting to sync"].exists)
    }

    func testRecordedPaymentWithoutProjectionKeepsMountedChecklistBlocked() {
        let app = launch("recorded")
        XCTAssertTrue(app.staticTexts["0 of 1"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Waiting to sync"].exists)
    }

    func testDisagreeingCachedInvoicesKeepMountedChecklistBlocked() {
        let app = launch("disagreement")
        XCTAssertTrue(app.staticTexts["0 of 1"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Waiting to sync"].exists)
    }

    func testLegacyPaymentWithUnknownJobKeepsMountedChecklistBlocked() {
        let app = launch("legacy")
        XCTAssertTrue(app.staticTexts["0 of 1"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Waiting to sync"].exists)
    }

    func testLegacyPendingPaymentOpensSavedWorkReview() {
        let app = launch("legacy")
        let review = app.buttons["Review saved work"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        review.tap()
        XCTAssertTrue(app.buttons["saved-work-sync"].waitForExistence(timeout: 10))
    }

    func testLegacyRecordedPaymentOpensItsInvoice() {
        let app = launch("legacy-recorded")
        let invoice = app.buttons["Open invoice 00002209"]
        XCTAssertTrue(invoice.waitForExistence(timeout: 10))
        invoice.tap()
        XCTAssertTrue(app.staticTexts["invoice-detail-title"].waitForExistence(timeout: 10))
    }

    func testUnavailableInvoicePermissionExplainsHowToRecover() {
        let app = launch("noaccess")
        XCTAssertTrue(app.staticTexts["Ask your office to enable your invoice and payment access, then refresh those invoices on this phone."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Open invoice 00002209"].exists)
    }

    func testUnavailablePaymentFeatureExplainsHowToRecover() {
        let app = launch("no-payments")
        XCTAssertTrue(app.staticTexts["Ask your office to enable your invoice and payment access, then refresh those invoices on this phone."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Open invoice 00002209"].exists)
    }

    func testInvoicePermissionLossClosesOpenRecoveryRoute() {
        let app = launch("revoke")
        let invoice = app.buttons["Open invoice 00002209"]
        XCTAssertTrue(invoice.waitForExistence(timeout: 10))
        invoice.tap()
        XCTAssertTrue(app.staticTexts["invoice-detail-title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Ask your office to enable your invoice and payment access, then refresh those invoices on this phone."].waitForExistence(timeout: 20))
    }

    func testOfflineSavedWorkCannotSyncUntilReconnected() {
        let app = launch("offline")
        let review = app.buttons["Review saved work"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        review.tap()
        let sync = app.buttons["saved-work-sync"]
        XCTAssertTrue(sync.waitForExistence(timeout: 10))
        XCTAssertFalse(sync.isEnabled)
        XCTAssertTrue(app.staticTexts["Offline · work stays saved on this phone"].exists)
    }

    func testSatisfiedServerPaymentDoesNotShowRecoveryWarning() {
        let app = launch("satisfied")
        XCTAssertTrue(app.staticTexts["1 of 1"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Payments to check"].exists)
        XCTAssertFalse(app.buttons["Open invoice 00002209"].exists)
    }

    private func launch(_ scenario: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job-closeout"]
        app.launchEnvironment["THORBIS_CLOSEOUT_TEST"] = scenario
        app.launch()
        XCTAssertTrue(app.staticTexts[scenario == "satisfied" ? "Payment recorded" : "Payment is due"].waitForExistence(timeout: 20))
        return app
    }
}
