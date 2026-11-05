import XCTest

@MainActor
final class LegacyCustomerHandoffUITests: XCTestCase {
    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", screen, "--paper-preview-working-job", "--paper-preview-legacy-handoff-test", "--paper-preview-owner-auth", "approved"]
        app.launch()
        return app
    }

    private func verifyProtectedSessionReplacement(_ app: XCUIApplication, checkProbe: Bool = true) {
        let lock = app.buttons["lock"]
        XCTAssertTrue(lock.waitForExistence(timeout: 20))
        let replace = app.buttons["preview-replace-session"]
        XCTAssertTrue(replace.waitForExistence(timeout: 5)); replace.tap()
        let retired = app.staticTexts["Please hand the device back to your technician."]
        XCTAssertTrue(retired.waitForExistence(timeout: 20), "Customer cover must survive session replacement in a safe state")
        XCTAssertFalse(app.buttons["Collect payment"].isHittable)
        let handBack = app.buttons["customer-mode-owner-exit"]
        XCTAssertTrue(handBack.isHittable, "Staff hand-back must remain available")
        handBack.tap()
        if checkProbe {
            let probe = app.buttons["preview-handoff-probe"]
            XCTAssertTrue(probe.waitForExistence(timeout: 20)); probe.tap()
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Handoff available"), object: probe)], timeout: 10), .completed)
        }
    }

    func testLegacyEstimateCoverSurvivesSessionReplacement() {
        continueAfterFailure = false
        let app = launch("estimate-detail")
        let show = app.buttons["Show customer"]
        XCTAssertTrue(show.waitForExistence(timeout: 20)); show.tap()
        verifyProtectedSessionReplacement(app)
        XCTAssertTrue(show.waitForExistence(timeout: 20)); show.tap()
        XCTAssertTrue(app.buttons["lock"].waitForExistence(timeout: 15), "A new handoff must be available after exit")
    }

    func testLegacyInvoiceCustomerViewCanOpenFromAnInvoiceSheet() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-detail", "--paper-preview-working-job", "--paper-preview-legacy-handoff-test", "--paper-preview-legacy-sheet", "--paper-preview-owner-auth", "approved"]
        app.launch()
        let menu = app.buttons["Customer view, edit or open the PDF"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20)); menu.tap()
        let show = app.buttons["Customer view"].firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 10)); show.tap()
        XCTAssertTrue(app.buttons["lock"].waitForExistence(timeout: 20), "Customer view must open from an invoice sheet too")
    }

    func testSheetInvoiceCoverSurvivesSessionReplacement() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-detail", "--paper-preview-working-job", "--paper-preview-legacy-handoff-test", "--paper-preview-legacy-sheet", "--paper-preview-owner-auth", "approved"]
        app.launch()
        let menu = app.buttons["Customer view, edit or open the PDF"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20)); menu.tap()
        let show = app.buttons["Customer view"].firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 10)); show.tap()
        verifyProtectedSessionReplacement(app, checkProbe: false)
        XCTAssertTrue(menu.waitForExistence(timeout: 20)); menu.tap()
        XCTAssertTrue(show.waitForExistence(timeout: 10)); show.tap()
        XCTAssertTrue(app.buttons["lock"].waitForExistence(timeout: 15), "The sheet must be able to start another handoff")
    }

    func testJobLinkedInvoiceSheetShowsJobCustomerView() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-detail", "--paper-preview-working-job", "--paper-preview-legacy-handoff-test", "--paper-preview-legacy-sheet", "--paper-preview-job-sheet", "--paper-preview-job-documents", "--paper-preview-owner-auth", "approved"]
        app.launch()
        let menu = app.buttons["Customer view, edit or open the PDF"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20)); menu.tap()
        let show = app.buttons["Customer view"].firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 10)); show.tap()
        XCTAssertTrue(app.buttons["lock"].waitForExistence(timeout: 20), "Job customer view must open above its sheet")
        XCTAssertTrue(app.staticTexts["4 of 4 documents"].waitForExistence(timeout: 20), "The job's documents must be presented together")
        XCTAssertTrue(app.staticTexts["INV-2209"].exists)
        XCTAssertFalse(app.buttons["Collect payment"].isHittable)
    }

    func testJobSheetPayAfterForegroundOffersActionableRetry() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-detail", "--paper-preview-working-job", "--paper-preview-legacy-handoff-test", "--paper-preview-legacy-sheet", "--paper-preview-job-sheet", "--paper-preview-job-documents", "--paper-preview-job-invoice-signed", "--paper-preview-owner-auth", "approved", "--paper-preview-exit-authority-diagnostic"]
        app.launch()
        let menu = app.buttons["Customer view, edit or open the PDF"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20)); menu.tap()
        let show = app.buttons["Customer view"].firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 10)); show.tap()
        XCTAssertTrue(app.staticTexts["4 of 4 documents"].waitForExistence(timeout: 20))
        let diagnostic = app.staticTexts["preview-exit-authority"]
        XCTAssertTrue(diagnostic.waitForExistence(timeout: 10)); XCTAssertTrue(diagnostic.label.contains("true"))
        XCUIDevice.shared.press(.home); app.activate()
        let changed = NSPredicate(format: "label CONTAINS %@", "false")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: changed, object: diagnostic)], timeout: 20), .completed)
        let pay = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pay $")).firstMatch
        XCTAssertTrue(pay.waitForExistence(timeout: 20)); pay.tap()
        XCTAssertTrue(app.staticTexts["Access was refreshed. Tap Collect payment to continue."].waitForExistence(timeout: 20))
        XCTAssertFalse(app.navigationBars["Collect payment"].exists)
    }

    func testJobLinkedSheetSurvivesSessionReplacement() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-detail", "--paper-preview-working-job", "--paper-preview-legacy-handoff-test", "--paper-preview-legacy-sheet", "--paper-preview-job-sheet", "--paper-preview-job-documents", "--paper-preview-owner-auth", "approved"]
        app.launch()
        let menu = app.buttons["Customer view, edit or open the PDF"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20)); menu.tap()
        let show = app.buttons["Customer view"].firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 10)); show.tap()
        XCTAssertTrue(app.staticTexts["4 of 4 documents"].waitForExistence(timeout: 20))
        let replace = app.buttons["preview-replace-session"]
        XCTAssertTrue(replace.waitForExistence(timeout: 5)); replace.tap()
        XCTAssertTrue(app.staticTexts["Please hand the device back"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["Collect payment"].isHittable)
        let handBack = app.buttons["Hand back to the technician"]
        XCTAssertTrue(handBack.waitForExistence(timeout: 10)); XCTAssertTrue(handBack.isHittable); handBack.tap()
        let unlock = app.buttons["Technician: unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 10)); unlock.tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 20), "Authenticated hand-back must return to the staff invoice")
    }

    func testJobLinkedSheetPayReturnsToSameInvoice() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-detail", "--paper-preview-working-job", "--paper-preview-legacy-handoff-test", "--paper-preview-legacy-sheet", "--paper-preview-job-sheet", "--paper-preview-job-documents", "--paper-preview-job-invoice-signed", "--paper-preview-owner-auth", "approved"]
        app.launch()
        let menu = app.buttons["Customer view, edit or open the PDF"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20)); menu.tap()
        let show = app.buttons["Customer view"].firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 10)); show.tap()
        XCTAssertTrue(app.staticTexts["4 of 4 documents"].waitForExistence(timeout: 20))
        let pay = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pay $")).firstMatch
        XCTAssertTrue(pay.waitForExistence(timeout: 20)); pay.tap()
        XCTAssertTrue(app.navigationBars["Collect payment"].waitForExistence(timeout: 20))
        let identity = app.descendants(matching: .any)["collect-payment-invoice"]
        XCTAssertTrue(identity.waitForExistence(timeout: 10)); XCTAssertTrue(identity.label.contains("INV-2209"), identity.label)
    }

    func testSheetInvoiceRemainsProtectedAfterBackground() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-detail", "--paper-preview-working-job", "--paper-preview-legacy-handoff-test", "--paper-preview-legacy-sheet", "--paper-preview-owner-auth", "approved"]
        app.launch()
        let menu = app.buttons["Customer view, edit or open the PDF"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20)); menu.tap()
        let show = app.buttons["Customer view"].firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 10)); show.tap()
        XCTAssertTrue(app.buttons["lock"].waitForExistence(timeout: 20))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["lock"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["Collect payment"].isHittable, "Backgrounding must not expose staff controls")
    }

    func testSheetInvoicePayOpensTheSameInvoiceAfterHandBack() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-detail", "--paper-preview-working-job", "--paper-preview-legacy-handoff-test", "--paper-preview-legacy-sheet", "--paper-preview-owner-auth", "approved"]
        app.launch()
        let menu = app.buttons["Customer view, edit or open the PDF"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20)); menu.tap()
        let show = app.buttons["Customer view"].firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 10)); show.tap()
        let pay = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pay $")).firstMatch
        XCTAssertTrue(pay.waitForExistence(timeout: 20)); pay.tap()
        XCTAssertTrue(app.navigationBars["Collect payment"].waitForExistence(timeout: 20))
        let identity = app.descendants(matching: .any)["collect-payment-invoice"]
        XCTAssertTrue(identity.waitForExistence(timeout: 10)); XCTAssertTrue(identity.label.contains("INV-2209"), identity.label)
    }

    func testLegacyInvoicePayOpensItsInvoiceAfterHandBack() {
        continueAfterFailure = false
        let app = launch("invoice-detail")
        let menu = app.buttons["Customer view, edit or open the PDF"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20)); menu.tap()
        let show = app.buttons["Customer view"].firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 10)); show.tap()
        let pay = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pay $")).firstMatch
        XCTAssertTrue(pay.waitForExistence(timeout: 20)); pay.tap()
        let collect = app.navigationBars["Collect payment"]
        XCTAssertTrue(collect.waitForExistence(timeout: 20), "Payment must open after the protected customer cover dismisses")
        let identity = app.descendants(matching: .any)["collect-payment-invoice"]
        XCTAssertTrue(identity.waitForExistence(timeout: 10))
        XCTAssertTrue(identity.label.contains("INV-2209"), identity.label)
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 10)); menu.tap()
        XCTAssertTrue(show.waitForExistence(timeout: 10)); show.tap()
        XCTAssertTrue(app.buttons["lock"].waitForExistence(timeout: 15), "The legacy handoff lease must be reusable after Pay")
    }

    func testLegacyInvoiceCoverSurvivesSessionReplacement() {
        continueAfterFailure = false
        let app = launch("invoice-detail")
        let menu = app.buttons["Customer view, edit or open the PDF"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20)); menu.tap()
        let show = app.buttons["Customer view"].firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 10)); show.tap()
        verifyProtectedSessionReplacement(app)
        XCTAssertTrue(menu.waitForExistence(timeout: 20)); menu.tap()
        XCTAssertTrue(show.waitForExistence(timeout: 10)); show.tap()
        XCTAssertTrue(app.buttons["lock"].waitForExistence(timeout: 15), "A new handoff must be available after exit")
    }
}
