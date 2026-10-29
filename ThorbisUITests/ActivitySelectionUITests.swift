import XCTest

@MainActor
final class ActivitySelectionUITests: XCTestCase {
    func testActivityWithoutRecordIdentityOpensReadableDetails() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer-activity", "--paper-preview-long-activity"]
        app.launch()
        let payment = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Card payment of $480.00")).firstMatch
        XCTAssertTrue(payment.waitForExistence(timeout: 20), "Every activity row should be selectable")
        payment.tap()
        XCTAssertTrue(app.navigationBars["Activity details"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Final activity detail.")).firstMatch.exists)
        XCTAssertTrue(app.buttons["Done"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(payment.waitForExistence(timeout: 5))
    }
}
