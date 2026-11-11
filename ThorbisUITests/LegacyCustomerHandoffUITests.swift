import XCTest

@MainActor
final class LegacyCustomerHandoffUITests: XCTestCase {
    func testInvoiceCustomerViewRemainsProtectedAfterSessionReplacement() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-detail", "--paper-preview-working-job", "--paper-preview-legacy-handoff-test"]
        app.launch()
        let menu = app.buttons["Customer view, edit or open the PDF"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30)); menu.tap()
        let show = app.buttons["Customer view"].firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 10)); show.tap()
        XCTAssertTrue(app.buttons["lock"].waitForExistence(timeout: 20))
        let replace = app.buttons["preview-replace-session"]
        XCTAssertTrue(replace.waitForExistence(timeout: 5)); replace.tap()
        XCTAssertTrue(app.staticTexts["Please hand the device back to your technician."].waitForExistence(timeout: 20), "The customer view must remain protected after a session replacement")
        XCTAssertFalse(app.buttons["Collect payment"].isHittable)
    }
}
