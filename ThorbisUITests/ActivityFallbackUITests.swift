import XCTest

@MainActor
final class ActivityFallbackUITests: XCTestCase {
    func testUnlinkedCustomerPaymentCanBeOpenedWithoutInventingInvoice() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer-activity"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Card payment of $480.00"].waitForExistence(timeout: 30), "The payment must be loaded before checking selection")
        let payment = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Card payment of $480.00")).firstMatch
        guard payment.waitForExistence(timeout: 5) else { XCTFail("The loaded feed entry should be selectable"); return }
        payment.tap()
        XCTAssertTrue(app.staticTexts["Card payment of $480.00"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Activity"].exists)
        XCTAssertFalse(app.navigationBars["Invoice"].exists)
    }
}
