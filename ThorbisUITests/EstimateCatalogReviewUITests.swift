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
        app.openPriceBook(from: app.buttons.matching(identifier: "estimate-add-item").firstMatch)
        let search = app.waitForPriceBookSearch()
        XCTAssertTrue(search.exists)
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
        XCTAssertTrue(app.waitForLineDescription(timeout: 5).exists)
    }

    func testLongCustomDescriptionRemainsEditableAndExplainsSaveLimit() {
        checkLongCustomDescriptionAtKeyboard(largeText: false)
    }

    func testLongCustomDescriptionAndSaveStayReachableAtLargestText() {
        checkLongCustomDescriptionAtKeyboard(largeText: true)
    }

    private func checkLongCustomDescriptionAtKeyboard(largeText: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate"]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        app.openPriceBook(from: app.buttons.matching(identifier: "estimate-add-item").firstMatch)
        let search = app.waitForPriceBookSearch()
        XCTAssertTrue(search.exists)
        search.tap()
        let fullDescription = String(repeating: "scope ", count: 40) + "last words"
        search.typeText(fullDescription)
        let add = app.buttons["price-book-add-custom"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        if largeText { XCTAssertLessThanOrEqual(add.frame.height, app.frame.height / 2, "A long query must not make the custom-item action taller than half the screen") }
        add.tap()
        let description = app.waitForLineDescription()
        XCTAssertTrue(description.exists)
        XCTAssertEqual(description.value as? String, fullDescription)
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch
        let keyboardDone = app.keyboardDoneButton
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 5))
        XCTAssertFalse(save.frame.intersects(keyboardDone.frame), "The keyboard Done control must not cover any part of Save")
        save.tap()
        let warning = app.waitForDescriptionLengthWarning()
        XCTAssertTrue(warning.exists)
        XCTAssertTrue(warning.isHittable, "The warning must remain visible while the keyboard is open")
        XCTAssertTrue(save.isHittable, "Save must remain reachable while the warning is displayed")
        XCTAssertEqual(description.value as? String, fullDescription)
    }

    func testRevisionShowsLengthWarningWhenSavingWithNumberKeyboardOpen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        // This preview has a sent revision and valid manual/Price Book source identities.
        // The builder-line showcase intentionally includes incomplete Price Book provenance,
        // which correctly disables editing and is not a suitable editor fixture.
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "estimate-revision"]
        app.launch()
        let line = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Compressor diagnostic")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 30))
        line.tap()
        let description = app.waitForLineDescription(timeout: 30)
        XCTAssertTrue(description.exists)
        XCTAssertTrue(description.isEnabled, "The revision fixture must be editable with supported provenance")
        description.tap()
        description.typeText(String(repeating: "x", count: 201))
        let price = app.textFields["Price each in dollars"]
        XCTAssertTrue(price.waitForExistence(timeout: 5))
        price.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save revised draft")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isHittable)
        let keyboardDone = app.keyboardDoneButton
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 5))
        XCTAssertFalse(save.frame.intersects(keyboardDone.frame), "The keyboard Done control must not cover any part of Save")
        save.tap()
        XCTAssertTrue(app.waitForDescriptionLengthWarning().exists)
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
        app.openPriceBook(from: optionAdd)
        let destination = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "To ", "Full system replacement")).firstMatch
        XCTAssertTrue(destination.exists, "The picker names the option it adds to")
        let search = app.waitForPriceBookSearch()
        XCTAssertTrue(search.exists)
        search.tap()
        search.typeText("Replace capacitor")
        let item = app.buttons["price-book-item-00000000-0000-4000-8000-000000009201"]
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        item.tap()
        app.buttons["price-book-done"].tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 5))
        XCTAssertTrue(optionTitle.waitForExistence(timeout: 5))
        app.openPriceBook(from: optionAdd)
        let searchAgain = app.waitForPriceBookSearch()
        XCTAssertTrue(searchAgain.exists)
        searchAgain.tap()
        searchAgain.typeText("Replace capacitor")
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
        app.openPriceBook(from: app.buttons.matching(identifier: "estimate-add-item").firstMatch)
        let search = app.waitForPriceBookSearch()
        XCTAssertTrue(search.exists)
        search.tap()
        XCTAssertTrue(app.staticTexts["Draft changes can't be saved yet."].exists, "The draft limit stays in view while adding")
        app.buttons["price-book-done"].tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 5))
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save draft")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
    }
}
