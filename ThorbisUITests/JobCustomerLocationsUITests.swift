import XCTest

final class JobCustomerLocationsUITests: XCTestCase {
    func testDirectionsRequiresChoosingAnAccountLocation() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-few-locations"]
        app.launch()
        let directions = app.buttons["Directions"]
        XCTAssertTrue(directions.waitForExistence(timeout: 20))
        directions.tap()
        XCTAssertTrue(app.buttons["Location 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Location 2"].exists)
        XCTAssertTrue(app.buttons["Location 3"].exists)
        XCTAssertFalse(app.staticTexts["Getting in"].exists, "No location is asserted to be the job site by default")
    }
}
