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
        // Since #183 the catalog is a sheet over the builder (behind "Add item"); it repeats the limit.
        let add = app.buttons.matching(identifier: "estimate-add-item").firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        for _ in 0..<8 where !add.isHittable { app.swipeUp() }
        add.tap()
        let search = app.textFields["price-book-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let shown = app.staticTexts.matching(NSPredicate(format: "label == %@", "Draft changes can't be saved yet."))
            .allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(shown, "The limitation must remain visible while adding catalog items")
        if let shown { XCTAssertTrue(app.frame.contains(CGPoint(x: shown.frame.midX, y: shown.frame.midY))) }
    }
}
