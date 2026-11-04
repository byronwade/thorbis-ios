import XCTest

@MainActor
final class LegacyCustomerHandoffUITests: XCTestCase {
    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", screen, "--paper-preview-working-job", "--paper-preview-legacy-handoff-test"]
        app.launch()
        return app
    }

    private func verifyProtectedSessionReplacement(_ app: XCUIApplication) {
        let lock = app.buttons["lock"]
        XCTAssertTrue(lock.waitForExistence(timeout: 20))
        let replace = app.buttons["preview-replace-session"]
        XCTAssertTrue(replace.waitForExistence(timeout: 5)); replace.tap()
        XCTAssertTrue(app.buttons["preview-session-replaced"].waitForExistence(timeout: 20), "Customer cover must survive session replacement")
        XCTAssertTrue(lock.isHittable, "Staff hand-back must remain available")
        lock.tap()
        let probe = app.buttons["preview-handoff-probe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 20)); probe.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Handoff available"), object: probe)], timeout: 10), .completed)
    }

    func testLegacyEstimateCoverSurvivesSessionReplacement() {
        continueAfterFailure = false
        let app = launch("estimate-detail")
        let show = app.buttons["Show customer"]
        XCTAssertTrue(show.waitForExistence(timeout: 20)); show.tap()
        verifyProtectedSessionReplacement(app)
    }

    func testLegacyInvoiceCoverSurvivesSessionReplacement() {
        continueAfterFailure = false
        let app = launch("invoice-detail")
        let menu = app.buttons["Customer view, edit or open the PDF"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20)); menu.tap()
        let show = app.buttons["Customer view"].firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 10)); show.tap()
        verifyProtectedSessionReplacement(app)
    }
}
