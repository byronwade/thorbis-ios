import XCTest

final class JobCustomerLocationsUITests: XCTestCase {
    /// The job's Directions circle asks which of the account's locations to drive to; it never assumes
    /// one is the job site. Its rows read "Location 1, Service · 1 Test Street" (title and the
    /// kind · address line combine), and the job's own Locations section lists the same words, so
    /// the rows are looked for inside the "Directions to" popover only.
    @MainActor
    func testDirectionsRequiresChoosingAnAccountLocation() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-few-locations"]
        app.launch()
        let directions = app.buttons["job-directions"]
        XCTAssertTrue(directions.waitForExistence(timeout: 20))
        let menu = app.otherElements["Directions to"]
        XCTAssertFalse(menu.exists, "Nothing is chosen for the person before they tap Directions")
        directions.tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "Directions opens the location chooser")
        for number in 1...3 {
            let row = menu.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Location \(number),")).firstMatch
            XCTAssertTrue(row.exists, "Location \(number) is offered")
        }
        XCTAssertFalse(app.staticTexts["Getting in"].exists, "No location is asserted to be the job site by default")
    }
}
