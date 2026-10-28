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
