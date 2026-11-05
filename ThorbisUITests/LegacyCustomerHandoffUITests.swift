import XCTest

@MainActor
final class LegacyCustomerHandoffUITests: XCTestCase {
    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", screen, "--paper-preview-working-job", "--paper-preview-legacy-handoff-test", "--paper-preview-owner-auth", "approved"]
        app.launch()
        return app
    }

    private func verifyProtectedSessionReplacement(_ app: XCUIApplication) {
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
        let probe = app.buttons["preview-handoff-probe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 20))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Handoff available"), object: probe)], timeout: 10), .completed)
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
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-detail", "--paper-preview-working-job", "--paper-preview-legacy-handoff-test", "--paper-preview-legacy-sheet"]
        app.launch()
        let menu = app.buttons["Customer view, edit or open the PDF"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20)); menu.tap()
        let show = app.buttons["Customer view"].firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 10)); show.tap()
        let state = app.staticTexts["preview-legacy-owner-state"]
        XCTAssertTrue(state.waitForExistence(timeout: 10), "The owner diagnostic must be visible")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Legacy active"), object: state)], timeout: 10), .completed, "The customer handoff must be claimed")
        XCTAssertEqual(state.label, "Legacy active")
        XCTAssertTrue(app.buttons["lock"].waitForExistence(timeout: 20), "Customer view must open from an invoice sheet too")
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
