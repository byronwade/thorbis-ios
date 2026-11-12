import XCTest

/// Adding price book items to an estimate. Since #183 the catalog is a cart sheet behind each
/// section's "Add item" (`estimate-add-item`, its value names the section): picks land in the section
/// it was opened from, nothing saves from the sheet, and "Done" returns to the builder for review.
@MainActor
final class EstimateCatalogReviewUITests: XCTestCase {
    func testLongEstimateOptionCanAddFromItsHeading() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "estimate-revision", "--paper-preview-long-catalog-sections"]
        app.launch()
        XCTAssertTrue(app.textFields["Option package title"].waitForExistence(timeout: 30))
        let add = app.buttons.matching(identifier: "estimate-add-item-heading")
            .matching(NSPredicate(format: "value CONTAINS %@", "Full system replacement")).firstMatch
        for _ in 0..<8 where !add.exists { app.swipeUp() }
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        XCTAssertTrue(add.isHittable)
        XCTAssertGreaterThanOrEqual(add.frame.height, 44)
        add.tap()
        let destination = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "To ", "Full system replacement")).firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 10))
        let search = app.textFields["price-book-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("Replace capacitor")
        let item = app.buttons["price-book-item-00000000-0000-4000-8000-000000009201"]
        XCTAssertTrue(item.waitForExistence(timeout: 10)); item.tap()
        let doneWithItem = app.buttons.matching(identifier: "price-book-done")
            .matching(NSPredicate(format: "label == %@", "Done · 1 item")).firstMatch
        XCTAssertTrue(doneWithItem.waitForExistence(timeout: 10), "The picker must confirm the item was added before closing")
        app.buttons["price-book-done"].tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.textFields["Option package title"].exists)
        openPicker(add, in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("Replace capacitor")
        let selected = app.buttons.matching(identifier: "price-book-item-00000000-0000-4000-8000-000000009201")
            .matching(NSPredicate(format: "value == %@", "1 in draft")).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 10), "The added item must remain in the chosen option")
        app.buttons["price-book-done"].tap()
        let other = app.buttons.matching(identifier: "estimate-add-item-heading")
            .matching(NSPredicate(format: "value CONTAINS %@", "Second system option")).firstMatch
        for _ in 0..<12 where !other.exists { app.swipeUp() }
        XCTAssertTrue(other.waitForExistence(timeout: 10))
        openPicker(other, in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "To ", "Second system option")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("Replace capacitor")
        let otherItem = app.buttons["price-book-item-00000000-0000-4000-8000-000000009201"]
        XCTAssertTrue(otherItem.waitForExistence(timeout: 10))
        XCTAssertEqual(otherItem.value as? String, "Not added", "A different option must not inherit the first option's draft quantity")
    }

    func testEstimateHeadingActionRespectsEditPermission() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "estimate-revision", "--paper-preview-long-catalog-sections", "--paper-preview-deny-document-edit"]
        app.launch()
        XCTAssertTrue(app.textFields["Option package title"].waitForExistence(timeout: 30))
        let add = app.buttons.matching(identifier: "estimate-add-item-heading")
            .matching(NSPredicate(format: "value CONTAINS %@", "Full system replacement")).firstMatch
        for _ in 0..<8 where !add.exists { app.swipeUp() }
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        XCTAssertFalse(add.isEnabled)
    }

    func testEstimateHeadingActionRespectsLineLimit() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "estimate-revision", "--paper-preview-max-catalog-sections"]
        app.launch()
        XCTAssertTrue(app.textFields["Option package title"].waitForExistence(timeout: 30))
        let add = app.buttons.matching(identifier: "estimate-add-item-heading")
            .matching(NSPredicate(format: "value CONTAINS %@", "Full system replacement")).firstMatch
        for _ in 0..<8 where !add.exists { app.swipeUp() }
        XCTAssertTrue(add.waitForExistence(timeout: 20))
        XCTAssertFalse(add.isEnabled, "The option must respect its 500-line limit")
    }

    func testEstimateHeadingActionAtLargestText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "estimate-revision", "--paper-preview-long-catalog-sections", "--paper-preview-large-option-range", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.textFields["Option package title"].waitForExistence(timeout: 30))
        let total = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "2 options", "The customer chooses one")).firstMatch
        XCTAssertTrue(total.waitForExistence(timeout: 10), "The full option summary must remain available")
        let low = app.staticTexts["estimate-total-value-0"]
        let high = app.staticTexts["estimate-total-value-1"]
        XCTAssertTrue(low.exists && high.exists, "Each end of the range needs its own visible line")
        XCTAssertEqual(low.label, "$120.00")
        XCTAssertEqual(high.label, "– $1,199,999.88")
        XCTAssertGreaterThanOrEqual(high.frame.minY, low.frame.maxY)
        XCTAssertLessThanOrEqual(high.frame.maxX, app.frame.maxX)
        for _ in 0..<20 where high.frame.maxY > app.frame.height * 0.68 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
        }
        XCTAssertLessThan(high.frame.maxY, app.frame.height * 0.75, "The full amount should be above the fixed save action")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Estimate total at largest text"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let add = app.buttons.matching(identifier: "estimate-add-item-heading")
            .matching(NSPredicate(format: "value CONTAINS %@", "Full system replacement")).firstMatch
        for _ in 0..<30 where !add.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
        }
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        XCTAssertTrue(add.isHittable, "Shortcut frame: \(add.frame); app hierarchy: \(app.debugDescription)")
        XCTAssertGreaterThanOrEqual(add.frame.height, 44)
        add.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "To ", "Full system replacement")).firstMatch.waitForExistence(timeout: 10))
    }

    func testShortEstimateOptionKeepsItsExistingAddAction() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "estimate-revision"]
        app.launch()
        XCTAssertTrue(app.textFields["Option package title"].waitForExistence(timeout: 30))
        let heading = app.buttons.matching(identifier: "estimate-add-item-heading")
            .matching(NSPredicate(format: "value CONTAINS %@", "Full system replacement")).firstMatch
        XCTAssertFalse(heading.exists)
        let existing = app.buttons.matching(identifier: "estimate-add-item")
            .matching(NSPredicate(format: "value CONTAINS %@", "Full system replacement")).firstMatch
        XCTAssertTrue(existing.exists)
    }

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
        openPicker(app.buttons.matching(identifier: "estimate-add-item").firstMatch, in: app)
        let search = app.textFields["price-book-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        let fullDescription = String(repeating: "scope ", count: 40) + "last words"
        search.typeText(fullDescription)
        let add = app.buttons["price-book-add-custom"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        if largeText { XCTAssertLessThanOrEqual(add.frame.height, app.frame.height / 2, "A long query must not make the custom-item action taller than half the screen") }
        add.tap()
        let description = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Line description")).firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 10))
        XCTAssertEqual(description.value as? String, fullDescription)
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch
        let keyboardDone = app.buttons["Done"].firstMatch
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 5))
        XCTAssertFalse(save.frame.intersects(keyboardDone.frame), "The keyboard Done control must not cover any part of Save")
        save.tap()
        let warning = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Error: Item descriptions can be up to 200 characters")).firstMatch
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
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
        let description = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Line description")).firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 30))
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
        let keyboardDone = app.buttons["Done"].firstMatch
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 5))
        XCTAssertFalse(save.frame.intersects(keyboardDone.frame), "The keyboard Done control must not cover any part of Save")
        save.tap()
        let warning = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Error: Item descriptions can be up to 200 characters")).firstMatch
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
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
