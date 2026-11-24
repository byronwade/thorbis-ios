import XCTest

@MainActor
final class EstimateDraftAvailabilityUITests: XCTestCase {
    private let oldLimit = "Draft changes can't be saved yet."

    /// A draft can be edited and saved: the edit stays in the field, nothing says saving is
    /// unavailable, and Save draft turns on once something changed.
    func testDraftInputIsRetainedAndSaveIsOffered() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "estimate-draft"]
        app.launch()
        let title = app.textFields["Estimate title"]
        XCTAssertTrue(title.waitForExistence(timeout: 30), app.debugDescription)
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save draft")).firstMatch
        XCTAssertTrue(save.exists)
        XCTAssertFalse(save.isEnabled, "Nothing to save before an edit")
        title.tap()
        title.typeText(" updated")
        // The field's value and Save draft catch up a beat after the last key on a slow runner.
        let typed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (title.value as? String)?.contains(" updated") == true
        }, object: title)
        XCTAssertEqual(XCTWaiter.wait(for: [typed], timeout: 10), .completed, "The edit stays in the field")
        XCTAssertFalse(app.staticTexts[oldLimit].exists)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed, "An edited draft can be saved")
    }

    /// The catalog sheet no longer repeats a limit that is gone.
    func testCatalogSearchShowsNoDraftLimit() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "estimate-draft"]
        app.launch()
        XCTAssertTrue(app.textFields["Estimate title"].waitForExistence(timeout: 30))
        // Since #183 the catalog is a sheet over the builder (behind "Add item").
        app.openPriceBook(from: app.buttons.matching(identifier: "estimate-add-item").firstMatch)
        let search = app.textFields["price-book-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[oldLimit].exists)
    }
}
