import XCTest

@MainActor
final class PriceBookPickerUITests: XCTestCase {
    private let sentinelID = "00000000-0000-4000-8000-000000009999"
    private let sentinel = "Camera sewer inspection"

    func testInvoicePickerSearchesLaterPageAndStaysOpenForMultipleAdds() {
        let app = openPriceBook()
        let search = app.otherElements["price-book-search"].textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        search.typeText(sentinel)
        let result = app.buttons["price-book-item-\(sentinelID)"]
        XCTAssertTrue(result.waitForExistence(timeout: 10), "Search must include the second server page")
        result.tap()
        XCTAssertTrue(app.navigationBars["Add from Price Book"].exists)
        XCTAssertEqual(search.value as? String, sentinel)
        let one = app.buttons.matching(identifier: "price-book-item-\(sentinelID)")
            .matching(NSPredicate(format: "value == %@", "1 in draft")).firstMatch
        XCTAssertTrue(one.waitForExistence(timeout: 5))
        result.tap()
        let two = app.buttons.matching(identifier: "price-book-item-\(sentinelID)")
            .matching(NSPredicate(format: "value == %@", "2 in draft")).firstMatch
        XCTAssertTrue(two.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, sentinel)
        app.navigationBars["Add from Price Book"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Edit invoice"].waitForExistence(timeout: 5))
        let descriptions = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND value == %@", "invoice-line-description-", sentinel))
        XCTAssertEqual(descriptions.count, 2)
        for field in descriptions.allElementsBoundByIndex {
            let id = String(field.identifier.dropFirst("invoice-line-description-".count))
            let quantity = app.otherElements["invoice-line-quantity-\(id)"].textFields.firstMatch
            XCTAssertEqual(quantity.value as? String, "1")
        }
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
        XCTAssertTrue(app.navigationBars["Add from Price Book"].waitForExistence(timeout: 2))
    }

    func testUnmatchedSearchExplainsThatNoItemsMatch() {
        let app = openPriceBook()
        let search = app.otherElements["price-book-search"].textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        search.typeText("unlisted zebra nozzle")
        XCTAssertTrue(app.staticTexts["No matching items"].waitForExistence(timeout: 10))
    }

    func testSelectedCategoryStaysVisibleAfterClosingKeyboard() {
        let app = openPriceBook()
        let bar = app.otherElements["price-book-search"]
        let search = bar.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        bar.buttons["Materials"].tap()
        bar.buttons["Done"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(bar.buttons["Materials"].exists, "An active category must stay visible")
        XCTAssertTrue(bar.buttons["Materials"].isSelected)
        bar.buttons["All"].tap()
        XCTAssertTrue(app.buttons["price-book-item-00000000-0000-4000-8000-000000009701"].waitForExistence(timeout: 5))
    }

    func testInvoiceSearchAnnouncesCatalogSearchOnly() {
        let app = openPriceBook()
        let search = app.otherElements["price-book-search"].textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertEqual(search.label, "Search price book", "The spoken instruction must not promise custom lines in this picker")
    }

    func testInvoicePickerCanAddAnItemBeyondTheFirstFifty() {
        let app = openLargeCatalog(screen: "invoice-editor")
        showMore(in: app)
        let previous = app.buttons["price-book-previous"]
        XCTAssertTrue(previous.waitForExistence(timeout: 5))
        previous.tap()
        XCTAssertTrue(app.buttons["price-book-show-more"].waitForExistence(timeout: 5))
        let bar = app.otherElements["price-book-search"]
        let search = bar.textFields.firstMatch
        search.tap()
        search.typeText("plumbing")
        let more = app.buttons["price-book-show-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "Changing the query starts with the first batch again")
        XCTAssertTrue(more.label.contains("23 remaining"), more.label)
        more.tap()
        bar.buttons["Services"].tap()
        XCTAssertTrue(more.waitForExistence(timeout: 5), "Changing category starts with the first batch again")
        XCTAssertTrue(more.label.contains("23 remaining"), more.label)
        more.tap()
        XCTAssertEqual(app.staticTexts["price-book-page-range"].label, "Items 51–73 of 73")
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
        let search = app.textFields["Search price book or type a line"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("plumbing")
        let custom = app.buttons["price-book-add-custom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        showMore(in: app)
        XCTAssertTrue(custom.isHittable, "Custom lines stay at the top after expanding matches")
        custom.tap()
        let review = app.buttons["Review estimate · 1 item"]
        if review.waitForExistence(timeout: 2) { review.tap() }
        let line = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Line description")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        XCTAssertEqual(line.value as? String, "plumbing")
    }

    private func openLargeCatalog(screen: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", screen, "--paper-preview-catalog-many"]
        app.launch()
        if screen == "invoice-editor" {
            let open = app.buttons["Add from price book"]
            XCTAssertTrue(open.waitForExistence(timeout: 15))
            open.tap()
        }
        XCTAssertTrue(app.buttons["price-book-item-00000000-0000-4000-8000-000000009701"].waitForExistence(timeout: 15))
        let loaded = app.buttons["price-book-show-more"]
        let complete = NSPredicate(format: "exists == true AND label CONTAINS %@", "23 remaining")
        expectation(for: complete, evaluatedWith: loaded)
        waitForExpectations(timeout: 15)
        return app
    }

    private func showMore(in app: XCUIApplication) {
        let more = app.buttons["price-book-show-more"]
        for _ in 0..<20 where !more.isHittable { app.swipeUp() }
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        XCTAssertTrue(more.isHittable)
        more.tap()
    }

    private func openPriceBook() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "invoice-editor", "--paper-preview-catalog-pages"]
        app.launch()
        let open = app.buttons["Add from price book"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()
        XCTAssertTrue(app.navigationBars["Add from Price Book"].waitForExistence(timeout: 5))
        return app
    }
}
