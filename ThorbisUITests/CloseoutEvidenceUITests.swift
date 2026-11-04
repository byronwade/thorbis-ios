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

    private func launch(_ scenario: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job-closeout"]
        app.launchEnvironment["THORBIS_CLOSEOUT_TEST"] = scenario
        app.launch()
        XCTAssertTrue(app.staticTexts["Payment is due"].waitForExistence(timeout: 20))
        return app
    }
}
