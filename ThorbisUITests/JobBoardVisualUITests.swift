import XCTest

@MainActor
final class JobBoardVisualUITests: XCTestCase {
    func testJobRowNamesItsStatusAndOpensTheJob() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "jobs"]
        app.launch()

        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "AC not cooling", "Dispatched")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        XCTAssertTrue(app.buttons["job-customer-link"].waitForExistence(timeout: 10))
    }
}
