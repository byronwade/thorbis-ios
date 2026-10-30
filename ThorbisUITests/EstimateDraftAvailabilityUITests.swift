import XCTest

@MainActor
final class EstimateDraftAvailabilityUITests: XCTestCase {
    func testDraftInputIsRetainedAndUnavailableSaveIsExplained() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "estimate-draft"]
        app.launch()
        let title = app.textFields["Estimate title"]
        XCTAssertTrue(title.waitForExistence(timeout: 30), app.debugDescription)
        title.tap()
        title.typeText(" updated")
        XCTAssertTrue((title.value as? String)?.contains(" updated") == true)
        XCTAssertTrue(app.staticTexts["Draft changes can't be saved yet."].exists)
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save draft")).firstMatch
        XCTAssertTrue(save.exists)
        XCTAssertFalse(save.isEnabled)
    }

    func testDraftWarningRemainsVisibleWhileSearchingCatalog() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "estimate-draft"]
        app.launch()
        let warning = app.staticTexts["Draft changes can't be saved yet."]
        XCTAssertTrue(warning.waitForExistence(timeout: 30))
        let search = app.textFields["Search price book or type a line"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        XCTAssertTrue(warning.exists,
                      "The limitation must remain visible while adding catalog items")
        XCTAssertTrue(app.frame.contains(CGPoint(x: warning.frame.midX, y: warning.frame.midY)))
    }
}
