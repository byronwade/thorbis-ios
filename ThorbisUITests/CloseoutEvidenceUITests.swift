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

    func testLegacyRecordedPaymentIdentifiesInvoiceWithoutOpeningRoute() {
        let app = launch("legacy-recorded")
        XCTAssertTrue(app.staticTexts["Invoice 2209"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["00000000-0000-4000-8000-000000002209"].exists)
        XCTAssertTrue(app.staticTexts["Connect, then search these invoice IDs in Invoices on this phone to refresh payments already sent."].exists)
    }

    func testUnavailableInvoicePermissionExplainsHowToRecover() {
        let app = launch("noaccess")
        XCTAssertTrue(app.staticTexts["Ask your office to enable your invoice and payment access, then refresh those invoices on this phone."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["00000000-0000-4000-8000-000000002209"].exists)
    }

    func testUnavailablePaymentFeatureExplainsHowToRecover() {
        let app = launch("no-payments")
        XCTAssertTrue(app.staticTexts["Ask your office to enable your invoice and payment access, then refresh those invoices on this phone."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["00000000-0000-4000-8000-000000002209"].exists)
    }

    func testMissingSavedWorkEditAccessExplainsRecovery() {
        let app = launch("noedit")
        XCTAssertTrue(app.staticTexts["Ask your office to restore your access to sync saved work on this phone."].waitForExistence(timeout: 10))
        app.buttons["Review saved work"].tap()
        let sync = app.buttons["saved-work-sync"]
        XCTAssertTrue(sync.waitForExistence(timeout: 10))
        XCTAssertFalse(sync.isEnabled)
    }

    func testEditingPermissionLossMakesOpenSavedWorkReadOnly() {
        let app = launch("legacy-revoke")
        app.buttons["Review saved work"].tap()
        XCTAssertTrue(app.buttons["saved-work-sync"].waitForExistence(timeout: 10))
        app.buttons["Sample controls"].tap()
        let revoke = app.buttons["Revoke sample editing shortly"]
        XCTAssertTrue(revoke.waitForExistence(timeout: 10))
        revoke.tap()
        XCTAssertTrue(app.staticTexts["You can review saved work. Your current access doesn't allow retrying or discarding changes."].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["saved-work-sync"].isEnabled)
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
    }

    func testInvoicesCanBeFoundByFullID() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoices"]
        app.launch()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap()
        search.typeText("00000000-0000-4000-8000-000000002209")
        XCTAssertTrue(app.staticTexts["Danielle Marlowe"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["No invoices."].exists)
    }

    private func launch(_ scenario: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job-closeout"]
        if scenario == "legacy-revoke" {
            app.launchArguments += ["--paper-preview-saved-work-session", UUID().uuidString, "--paper-preview-saved-work-controls"]
        }
        app.launchEnvironment["THORBIS_CLOSEOUT_TEST"] = scenario
        app.launch()
        XCTAssertTrue(app.staticTexts[scenario == "satisfied" ? "Payment recorded" : "Payment is due"].waitForExistence(timeout: 20))
        return app
    }
}
