import XCTest

@MainActor
final class JobListSearchUITests: XCTestCase {
    func testSearchFiltersJobsAndClearingRestoresThem() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "jobs"]
        app.launch()
        let search = app.textFields["Search jobs"]
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Kitchen sink backup — Petrov"].waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Kitchen")
        XCTAssertTrue(app.staticTexts["Kitchen sink backup — Petrov"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["AC not cooling"].exists)
        app.buttons["Clear search"].tap()
        XCTAssertTrue(app.staticTexts["AC not cooling"].waitForExistence(timeout: 10))
        app.buttons["Filter jobs"].tap()
        XCTAssertTrue(app.staticTexts["Ordering"].waitForExistence(timeout: 10))
    }
}
