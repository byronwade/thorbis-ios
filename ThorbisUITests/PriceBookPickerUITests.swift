import XCTest

/// The price book picker (since #183 a cart sheet, `PriceBookCartPicker`, behind "Add item" in the
/// invoice editor and the estimate builder): search with the keyboard up, add an item as many times
/// as needed without the sheet closing, page past the first fifty, filter by category from the
/// Category circle, then "Done" returns to the document. Since Paper 33 the picker is Add
/// materials' "Price book" segment: a Scan · Paste · Price book row sits between the title and the
/// search field, so the list starts lower; the tests reach rows by identifier and scroll to them.
@MainActor
final class PriceBookPickerUITests: XCTestCase {
    private let sentinelID = "00000000-0000-4000-8000-000000009999"
    private let sentinel = "Camera sewer inspection"

    func testPartialCatalogCanAddLoadedItemAndDoesNotClaimAnUnloadedSearchIsEmpty() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor", "--paper-preview-catalog-partial"]
        app.launch()
        openPicker(in: app, addItem: "invoice-add-item")
        settleSearchFocus(in: app)
        let notice = app.staticTexts["price-book-partial"]
        XCTAssertTrue(notice.waitForExistence(timeout: 20))
        XCTAssertTrue(notice.label.contains("Search covers loaded items only"))
        let item = app.buttons["price-book-item-00000000-0000-4000-8000-000000009701"]
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        let loadingShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        loadingShot.name = "Loaded items with partial catalog notice"
        loadingShot.lifetime = .keepAlways
        add(loadingShot)
        reveal(item, in: app)
        item.tap()
        let one = app.buttons.matching(identifier: item.identifier)
            .matching(NSPredicate(format: "value == %@", "1 in draft")).firstMatch
        XCTAssertTrue(one.waitForExistence(timeout: 5), "The loaded item is the one added")
        XCTAssertTrue(app.buttons["price-book-done"].label.contains("1 item"))
        let search = app.textFields["invoice-catalog-search"]
        search.tap()
        search.typeText("camera sewer")
        XCTAssertTrue(notice.exists)
        XCTAssertFalse(app.staticTexts["No price book items match. Add it as a custom item above, or try another word."].exists)
        let searchShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        searchShot.name = "Search while later catalog pages are pending"
        searchShot.lifetime = .keepAlways
        add(searchShot)
    }

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

    func testInvoicePickerKeepsSearchAndAddedLineDuringAuthorityRevalidation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor",
                               "--paper-preview-catalog-pages", "--paper-preview-picker-revalidation", "--paper-preview-picker-feature-change"]
        app.launch()
        let before = lineCount(app)
        openPicker(in: app, addItem: "invoice-add-item")
        let search = app.textFields["invoice-catalog-search"]
        search.tap()
        search.typeText(sentinel)
        let item = app.buttons["price-book-item-\(sentinelID)"]
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        // Paper 33: the sheet's title, its Scan / Paste / Price book tabs and the preview's refresh
        // row sit above the results, so with the keyboard up the match starts under the Done bar
        // that rides it; a tap there lands on Done. Drag the results up until the row is clear.
        let done = app.buttons["price-book-done"]
        func clearOfDone() {
            for _ in 0..<6 where item.frame.maxY > done.frame.minY - 4 {
                let start = done.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -0.6))
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -90)))
            }
            XCTAssertLessThanOrEqual(item.frame.maxY, done.frame.minY, "The match must be reachable above the Done bar")
        }
        clearOfDone()
        item.tap()
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Adding keeps the picker open")
        XCTAssertTrue(done.label.contains("1 item"))
        let revalidate = app.buttons["price-book-preview-revalidate"]
        XCTAssertTrue(revalidate.waitForExistence(timeout: 5))
        revalidate.tap()
        XCTAssertTrue(app.staticTexts["price-book-preview-revalidated"].waitForExistence(timeout: 10))
        XCTAssertEqual(search.value as? String, sentinel)
        XCTAssertTrue(app.buttons["price-book-done"].label.contains("1 item"))
        XCTAssertTrue(item.waitForExistence(timeout: 10), "Catalog items must return after authority refresh")
        // The refreshed notice pushes the match down again.
        clearOfDone()
        item.tap()
        XCTAssertTrue(app.buttons["price-book-done"].label.contains("2 items"))
        app.buttons["price-book-done"].tap()
        XCTAssertEqual(lineCount(app), before + 2)
        let editor = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "invoice-line-description-")).firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, sentinel)
    }

    func testInvoicePickerKeepsCurrentPageDuringSameAuthorityRevalidation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor",
                               "--paper-preview-catalog-many", "--paper-preview-picker-revalidation", "--paper-preview-picker-feature-change"]
        app.launch()
        openPicker(in: app, addItem: "invoice-add-item")
        let search = app.textFields["invoice-catalog-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("plumbing\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let more = app.buttons["price-book-show-more"]
        expectation(for: NSPredicate(format: "exists == true AND label CONTAINS %@", "23 remaining"), evaluatedWith: more)
        waitForExpectations(timeout: 15)
        showMore(in: app)
        let range = app.staticTexts["price-book-page-range"]
        expectation(for: NSPredicate(format: "label == %@", "51–73 of 73"), evaluatedWith: range)
        waitForExpectations(timeout: 5)
        let revalidate = app.buttons["price-book-preview-revalidate"]
        XCTAssertTrue(revalidate.waitForExistence(timeout: 5))
        revalidate.tap()
        XCTAssertTrue(app.staticTexts["price-book-preview-revalidated"].waitForExistence(timeout: 10))
        XCTAssertEqual(range.label, "51–73 of 73", "A harmless authority refresh should preserve the current page")
        XCTAssertTrue(app.buttons["price-book-item-00000000-0000-4000-8000-000000009773"].exists)
    }

    func testInvoicePickerKeepsFirstPageSelectionOpen() {
        let app = openPriceBook()
        settleSearchFocus(in: app)
        let item = app.buttons["price-book-item-00000000-0000-4000-8000-000000009701"]
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        reveal(item, in: app)
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

    /// Paper 33: the invoice picker is one of Add materials' three ways in, and search stays with them.
    func testInvoicePickerShowsAddMaterialsSegments() {
        let app = openPriceBook()
        let search = app.textFields["invoice-catalog-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        for name in ["Scan", "Paste", "Price book"] {
            let segment = app.buttons[name].firstMatch
            XCTAssertTrue(segment.waitForExistence(timeout: 5), "\(name) is one of the picker's segments")
        }
        XCTAssertTrue(app.buttons["price-book-done"].exists, "Showing the segments leaves the picker open")
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
        for _ in 0..<12 where !last.isHittable { catalog(in: app).swipeUp() }
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
        for _ in 0..<12 where !last.isHittable { catalog(in: app).swipeUp() }
        XCTAssertTrue(last.waitForExistence(timeout: 5), app.debugDescription)
        last.tap()
        let added = app.buttons.matching(identifier: last.identifier)
            .matching(NSPredicate(format: "value == %@", "1 in draft")).firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 5))
        // After the first add the row reflows ("1 in draft"); wait until it is hittable again
        // before the second tap, or the tap misses under suite load.
        for _ in 0..<12 where !added.isHittable { catalog(in: app).swipeUp() }
        XCTAssertTrue(added.isHittable, app.debugDescription)
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

    /// What to swipe to move through the picker: the screen on a phone; on iPad the picker's own
    /// list, as the picker is a centred sheet over the editor sheet and the screen's middle is not
    /// reliably its list.
    private func catalog(in app: XCUIApplication) -> XCUIElement {
        guard app.usesTabletLayout else { return app }
        return app.scrollViews.containing(NSPredicate(format: "identifier BEGINSWITH %@", "price-book-item-")).firstMatch
    }

    private func showMore(in app: XCUIApplication) {
        let more = app.buttons["price-book-show-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        let done = app.buttons["price-book-done"]
        for _ in 0..<20 {
            if more.isHittable, more.frame.maxY < done.frame.minY { break }
            catalog(in: app).swipeUp()
        }
        XCTAssertTrue(more.isHittable)
        XCTAssertLessThan(more.frame.maxY, done.frame.minY, "Next items must be visibly above the footer")
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
        app.openPriceBook(from: app.buttons.matching(identifier: addItem).firstMatch)
    }

    /// The search field takes focus 350 ms after the picker opens (EB-01). Where that raises the
    /// software keyboard, Done rides on it and covers every row but the first, and the rows move
    /// as it rises; a tap on a row read before then lands on its neighbour. Wait for the focus,
    /// then put the keyboard away with the picker's own keyboard circle, as a person would.
    private func settleSearchFocus(in app: XCUIApplication) {
        let hide = app.buttons["Hide keyboard"].firstMatch
        XCTAssertTrue(hide.waitForExistence(timeout: 5), "The search field takes focus when the picker opens")
        hide.tap()
        XCTAssertTrue(app.buttons["Search the price book"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.waitForKeyboardToHide(timeout: 5))
    }

    /// Brings a row above the pinned Done bar. A row under the bar still reports hittable, and a
    /// tap on it lands on the bar or the row above.
    private func reveal(_ row: XCUIElement, in app: XCUIApplication) {
        let done = app.buttons["price-book-done"]
        func clear() -> Bool { row.exists && row.isHittable && row.frame.maxY <= done.frame.minY - 4 }
        for _ in 0..<8 where !clear() {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
        }
        XCTAssertTrue(clear(), "\(row.frame) is clear of Done at \(done.frame)")
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
        XCTAssertTrue(app.staticTexts["Edit invoice"].waitForExistence(timeout: 20))
        return app
    }

    private func openPriceBook() -> XCUIApplication {
        let app = launchInvoiceEditor()
        openPicker(in: app, addItem: "invoice-add-item")
        return app
    }
}
