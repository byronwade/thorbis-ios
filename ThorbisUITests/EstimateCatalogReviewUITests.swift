import XCTest

/// Adding price book items to an estimate. Since #183 the catalog is a cart sheet behind each
/// section's "Add item" (`estimate-add-item`, its value names the section): picks land in the section
/// it was opened from, nothing saves from the sheet, and "Done" returns to the builder for review.
@MainActor
final class EstimateCatalogReviewUITests: XCTestCase {
    func testCustomerMenuKeepsItsVisibleAccessibilityLabelWithoutOverride() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate"]
        app.launch()
        let customer = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Danielle Marlowe")).firstMatch
        XCTAssertTrue(customer.waitForExistence(timeout: 30), "The customer menu must retain its visible label for accessibility")
    }

    func testNewEstimateCanReviewAddedItemsWithoutSavingFromSearch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate", "--paper-preview-catalog-pages"]
        app.launch()
        openPicker(app.buttons.matching(identifier: "estimate-add-item").firstMatch, in: app)
        let search = app.textFields["price-book-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Replace capacitor")
        let item = app.buttons["price-book-item-00000000-0000-4000-8000-000000009201"]
        XCTAssertTrue(item.waitForExistence(timeout: 15))
        item.tap()
        let done = app.buttons["price-book-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertEqual(done.label, "Done · 1 item")
        // Nothing saves from the price book: its only commit returns to the builder.
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch.isHittable)
        done.tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Estimate title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch.exists)
        // The added line sits collapsed in the builder; tapping it opens its fields for review.
        let added = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Replace capacitor")).firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 5))
        added.tap()
        let editableLine = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Line description")).firstMatch
        XCTAssertTrue(editableLine.waitForExistence(timeout: 5))
    }

    func testReviewKeepsCatalogItemInItsChosenOption() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "estimate-revision"]
        app.launch()
        let optionTitle = app.textFields["Option package title"]
        XCTAssertTrue(optionTitle.waitForExistence(timeout: 30))
        let optionAdd = app.buttons.matching(identifier: "estimate-add-item")
            .matching(NSPredicate(format: "value CONTAINS %@", "Full system replacement")).firstMatch
        XCTAssertTrue(optionAdd.waitForExistence(timeout: 10), "Each option has its own Add item")
        openPicker(optionAdd, in: app)
        let destination = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "To ", "Full system replacement")).firstMatch
        XCTAssertTrue(destination.exists, "The picker names the option it adds to")
        let search = app.textFields["price-book-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Replace capacitor")
        let item = app.buttons["price-book-item-00000000-0000-4000-8000-000000009201"]
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        item.tap()
        app.buttons["price-book-done"].tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 5))
        XCTAssertTrue(optionTitle.waitForExistence(timeout: 5))
        openPicker(optionAdd, in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Replace capacitor")
        let added = app.buttons.matching(identifier: "price-book-item-00000000-0000-4000-8000-000000009201")
            .matching(NSPredicate(format: "value == %@", "1 in draft")).firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 10), "The added line must remain in the selected option")
    }

    func testDraftEstimateKeepsSaveUnavailableDuringCatalogReview() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "estimate-draft", "--paper-preview-catalog-pages"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Draft changes can't be saved yet."].waitForExistence(timeout: 30))
        openPicker(app.buttons.matching(identifier: "estimate-add-item").firstMatch, in: app)
        let search = app.textFields["price-book-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        XCTAssertTrue(app.staticTexts["Draft changes can't be saved yet."].exists, "The draft limit stays in view while adding")
        app.buttons["price-book-done"].tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 5))
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save draft")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
    }

    private func openPicker(_ add: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(add.waitForExistence(timeout: 30))
        // Clear of the pinned total and commit at the bottom, which cover the lower part of the page.
        let clear = app.frame.height * 0.7
        for _ in 0..<10 where !add.isHittable || add.frame.maxY > clear {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
        }
        XCTAssertTrue(add.isHittable)
        add.tap()
        XCTAssertTrue(app.buttons["price-book-done"].waitForExistence(timeout: 5), "Add item opens the price book")
    }
}
