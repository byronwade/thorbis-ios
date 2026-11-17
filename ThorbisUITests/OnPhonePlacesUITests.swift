import XCTest

/// The places kept on this phone (Paper 27, 84, 82A): each opens from its own preview screen and
/// its main action works end to end.
@MainActor
final class OnPhonePlacesUITests: XCTestCase {
    private func launch(_ screen: String, role: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", screen, "--paper-preview-role", role]
        app.launch()
        return app
    }

    func testTimeClockClocksInAndOut() {
        continueAfterFailure = false
        let app = launch("time-clock", role: "tech")
        XCTAssertTrue(app.staticTexts["timeclock-root"].waitForExistence(timeout: 30))
        let clockOut = app.buttons["timeclock-clock-out"]
        // A run left clocked in by an earlier pass starts from clocked in.
        if !clockOut.exists {
            let clockIn = app.buttons["timeclock-clock-in"]
            XCTAssertTrue(clockIn.waitForExistence(timeout: 10))
            clockIn.tap()
        }
        XCTAssertTrue(clockOut.waitForExistence(timeout: 10), "Clocking in offers Clock out")
        XCTAssertTrue(app.buttons["timeclock-start-break"].exists, "A running clock offers a break")
        clockOut.tap()
        XCTAssertTrue(app.buttons["timeclock-clock-in"].waitForExistence(timeout: 10), "Clocking out offers Clock in again")
    }

    func testTruckStockAddsAnItem() {
        continueAfterFailure = false
        let app = launch("truck-stock", role: "tech")
        XCTAssertTrue(app.staticTexts["Truck stock"].waitForExistence(timeout: 30))
        let name = "Test fitting \(Int(Date().timeIntervalSince1970) % 100_000)"
        app.buttons["header-create"].firstMatch.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(name)
        app.buttons["truckstock-save"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 10), "The saved item is listed")
    }

    func testPipelineOpensWithItsStages() {
        continueAfterFailure = false
        let app = launch("pipeline", role: "office")
        XCTAssertTrue(app.staticTexts["Pipeline"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'pipeline-stage-'")).firstMatch.exists)
    }
}
