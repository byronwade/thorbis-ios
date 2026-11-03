import XCTest

final class CustomerGuardedOwnerUITests: XCTestCase {
    func testCrossOwnerDenialRemovesAlreadyRenderedCustomerText() {
        let app = XCUIApplication()
        app.launchArguments.append("--customer-guarded-owner-preview")
        app.launch()
        let secret = app.staticTexts["owner-secret"]
        XCTAssertTrue(secret.waitForExistence(timeout: 10))
        app.buttons["Deny in another owner"].tap()
        XCTAssertTrue(app.staticTexts["owner-retired"].waitForExistence(timeout: 5))
        XCTAssertFalse(secret.exists)
    }
}
