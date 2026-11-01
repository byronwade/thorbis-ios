import XCTest

/// The price book picker (since #183 a cart sheet, `PriceBookCartPicker`, behind "Add item" in the
/// invoice editor and the estimate builder): search with the keyboard up, add an item as many times
/// as needed without the sheet closing, page past the first fifty, filter by category from the
/// Category circle, then "Done" returns to the document.
@MainActor
final class PriceBookPickerUITests: XCTestCase {
    private let sentinelID = "00000000-0000-4000-8000-000000009999"
    private let sentinel = "Camera sewer inspection"

    func testInvoicePickerSearchesLaterPageAndStaysOpenForMultipleAdds() {
        let app = launchInvoiceEditor()
        let before = lineCount(app)
        openPicker(in: app, addItem: "invoice-add-item")
        let search = app.textFields["invoice-catalog-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        search.typeText(sentinel)
        let result = app.buttons["price-book-item-\(sentinelID)"]
        XCTAssertTrue(result.waitForExistence(timeout: 10), "Search must include the second server page")
        result.tap()
        XCTAssertTrue(app.buttons["price-book-done"].exists, "Adding keeps the picker open")
        XCTAssertEqual(search.value as? String, sentinel)
        let one = app.buttons.matching(identifier: "price-book-item-\(sentinelID)")
            .matching(NSPredicate(format: "value == %@", "1 in draft")).firstMatch
        XCTAssertTrue(one.waitForExistence(timeout: 5))
        result.tap()
        let two = app.buttons.matching(identifier: "price-book-item-\(sentinelID)")
            .matching(NSPredicate(format: "value == %@", "2 in draft")).firstMatch
        XCTAssertTrue(two.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, sentinel)
        app.buttons["price-book-done"].tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 5))
        XCTAssertEqual(lineCount(app), before + 2, "Each add is its own separately priced line")
        // Done opens the last added line: one unit of the sentinel at its own price.
        let open = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "invoice-line-description-")).firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertEqual(open.value as? String, sentinel)
        let id = String(open.identifier.dropFirst("invoice-line-description-".count))
        XCTAssertEqual(app.textFields["invoice-line-quantity-\(id)"].value as? String, "1")
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "Two separately priced catalog lines"
        proof.lifetime = .keepAlways
        add(proof)
    }

    func testInvoicePickerKeepsFirstPageSelectionOpen() {
        let app = openPriceBook()
        let item = app.buttons["price-book-item-00000000-0000-4000-8000-000000009701"]
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        item.tap()
        let added = app.buttons.matching(identifier: item.identifier)
            .matching(NSPredicate(format: "value == %@", "1 in draft")).firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["price-book-done"].exists, "The picker stays open after an add")
        XCTAssertEqual(app.buttons["price-book-done"].label, "Done · 1 item")
    }

    func testUnmatchedSearchExplainsThatNoItemsMatch() {
        let app = openPriceBook()
        let search = app.textFields["invoice-catalog-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        search.typeText("unlisted zebra nozzle")
        // The invoice picker also adds custom lines, so "no match" points at that row.
        XCTAssertTrue(app.staticTexts["No price book items match. Add it as a custom item above, or try another word."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["price-book-add-custom"].exists)
    }

    func testSelectedCategoryStaysVisibleAfterClosingKeyboard() {
        let app = openPriceBook()
        let search = app.textFields["invoice-catalog-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        chooseCategory("Materials", in: app)
        if app.keyboards.firstMatch.exists { search.typeText("\n") }
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Showing materials"].exists, "An active category must stay visible")
        XCTAssertEqual(app.buttons["Category"].value as? String, "Materials")
        chooseCategory("All", in: app)
        XCTAssertTrue(app.staticTexts["Showing materials"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["price-book-item-00000000-0000-4000-8000-000000009701"].waitForExistence(timeout: 5))
    }

    func testInvoiceSearchAnnouncesCatalogSearchOnly() {
        let app = openPriceBook()
        let search = app.textFields["invoice-catalog-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertEqual(search.label, "Search price book", "The spoken instruction must not promise custom lines in this field")
    }

    func testInvoicePickerCanAddAnItemBeyondTheFirstFifty() {
        let app = openLargeCatalog(screen: "invoice-editor")
        showMore(in: app)
        let previous = app.buttons["price-book-previous"]
        XCTAssertTrue(previous.waitForExistence(timeout: 5))
        for _ in 0..<12 where !previous.isHittable { app.swipeDown() }
        previous.tap()
        XCTAssertTrue(app.buttons["price-book-show-more"].waitForExistence(timeout: 5))
        let search = app.textFields["invoice-catalog-search"]
        for _ in 0..<12 where !search.isHittable { app.swipeDown() }
        search.tap()
        search.typeText("plumbing")
        let more = app.buttons["price-book-show-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "Changing the query starts with the first batch again")
        XCTAssertTrue(more.label.contains("23 remaining"), more.label)
        showMore(in: app)
        for _ in 0..<12 where !app.buttons["Category"].isHittable { app.swipeDown() }
        chooseCategory("Services", in: app)
        XCTAssertTrue(more.waitForExistence(timeout: 5), "Changing category starts with the first batch again")
        XCTAssertTrue(more.label.contains("23 remaining"), more.label)
        showMore(in: app)
        let range = app.staticTexts["price-book-page-range"]
        expectation(for: NSPredicate(format: "label == %@", "51–73 of 73"), evaluatedWith: range)
        waitForExpectations(timeout: 5)
        let last = app.buttons["price-book-item-00000000-0000-4000-8000-000000009773"]
        for _ in 0..<12 where !last.isHittable { app.swipeUp() }
        XCTAssertTrue(last.waitForExistence(timeout: 5), app.debugDescription)
        last.tap()
        let added = app.buttons.matching(identifier: last.identifier)
            .matching(NSPredicate(format: "value == %@", "1 in draft")).firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 5))
        added.tap()
        let twice = app.buttons.matching(identifier: last.identifier)
            .matching(NSPredicate(format: "value == %@", "2 in draft")).firstMatch
        XCTAssertTrue(twice.waitForExistence(timeout: 5), "Selected item stays on this page for another add")
    }

    func testEstimateBuilderCanAddAnItemBeyondTheFirstFifty() {
        let app = openLargeCatalog(screen: "new-estimate")
        showMore(in: app)
        let last = app.buttons["price-book-item-00000000-0000-4000-8000-000000009773"]
        for _ in 0..<12 where !last.isHittable { app.swipeUp() }
        XCTAssertTrue(last.waitForExistence(timeout: 5), app.debugDescription)
        last.tap()
        let added = app.buttons.matching(identifier: last.identifier)
            .matching(NSPredicate(format: "value == %@", "1 in draft")).firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 5))
        added.tap()
        let twice = app.buttons.matching(identifier: last.identifier)
            .matching(NSPredicate(format: "value == %@", "2 in draft")).firstMatch
        XCTAssertTrue(twice.waitForExistence(timeout: 5), "Recent items do not move while browsing")
    }

    func testEstimateCustomLineRemainsAvailableAfterExpandingMatches() {
        let app = openLargeCatalog(screen: "new-estimate")
        let search = app.textFields["price-book-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("plumbing")
        let custom = app.buttons["price-book-add-custom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        showMore(in: app)
        // The custom line leads the list: after expanding matches it is still there, at the top.
        for _ in 0..<12 where !custom.isHittable { app.swipeDown() }
        XCTAssertTrue(custom.isHittable, "Custom lines stay at the top after expanding matches")
        custom.tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 5), "A custom line closes the picker")
        let line = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Line description")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        XCTAssertEqual(line.value as? String, "plumbing")
    }

    private func openLargeCatalog(screen: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", screen, "--paper-preview-catalog-many"]
        app.launch()
        openPicker(in: app, addItem: screen == "invoice-editor" ? "invoice-add-item" : "estimate-add-item")
        XCTAssertTrue(app.buttons["price-book-item-00000000-0000-4000-8000-000000009701"].waitForExistence(timeout: 15))
        let loaded = app.buttons["price-book-show-more"]
        let complete = NSPredicate(format: "exists == true AND label CONTAINS %@", "23 remaining")
        expectation(for: complete, evaluatedWith: loaded)
        waitForExpectations(timeout: 15)
        return app
    }

    private func showMore(in app: XCUIApplication) {
        let more = app.buttons["price-book-show-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        for _ in 0..<20 where !more.isHittable { app.swipeUp() }
        XCTAssertTrue(more.isHittable)
        more.tap()
    }

    /// The category sits behind the picker's Category circle (a ThorbisMenu) since #183.
    private func chooseCategory(_ name: String, in app: XCUIApplication) {
        let category = app.buttons["Category"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        category.tap()
        let choice = app.buttons[name]
        XCTAssertTrue(choice.waitForExistence(timeout: 5), app.debugDescription)
        choice.tap()
        XCTAssertTrue(choice.waitForNonExistence(timeout: 5))
    }

    /// Opens the picker from the document's "Add item" row.
    private func openPicker(in app: XCUIApplication, addItem: String) {
        let add = app.buttons.matching(identifier: addItem).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 20))
        for _ in 0..<8 where !add.isHittable { app.swipeUp() }
        add.tap()
        XCTAssertTrue(app.buttons["price-book-done"].waitForExistence(timeout: 5), "Add item opens the price book")
    }

    /// "Line items · N" read from its identifier, so additions are counted, not guessed.
    private func lineCount(_ app: XCUIApplication) -> Int {
        let header = app.staticTexts["invoice-line-count"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        return Int(header.label.components(separatedBy: "·").last?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0
    }

    private func launchInvoiceEditor() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor", "--paper-preview-catalog-pages"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Edit invoice"].waitForExistence(timeout: 20))
        return app
    }

    private func openPriceBook() -> XCUIApplication {
        let app = launchInvoiceEditor()
        openPicker(in: app, addItem: "invoice-add-item")
        return app
    }
}
