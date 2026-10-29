import XCTest

@MainActor
final class EstimateCatalogReviewUITests: XCTestCase {
    func testNewEstimateCanReviewAddedItemsWithoutSavingFromSearch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "new-estimate", "--paper-preview-catalog-pages"]
        app.launch()
        let search = app.textFields["Search price book or type a line"]
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        search.tap()
        search.typeText("Replace capacitor")
        let item = app.buttons["price-book-item-00000000-0000-4000-8000-000000009201"]
        XCTAssertTrue(item.waitForExistence(timeout: 15))
        item.tap()
        let review = app.buttons["Review estimate · 1 item"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch.exists)
        review.tap()
        XCTAssertTrue(app.textFields["Estimate title"].waitForExistence(timeout: 5))
        XCTAssertNotEqual(search.value as? String, "Replace capacitor")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save estimate")).firstMatch.exists)
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
        let materialButtons = app.buttons.matching(identifier: "Add to Materials")
        XCTAssertGreaterThanOrEqual(materialButtons.count, 2)
        let optionAdd = materialButtons.element(boundBy: 1)
        for _ in 0..<5 where !optionAdd.isHittable { app.swipeUp() }
        XCTAssertTrue(optionAdd.isHittable)
        optionAdd.tap()
        let search = app.textFields.matching(NSPredicate(format: "label BEGINSWITH %@", "Add to Full system replacement")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.typeText("Replace capacitor")
        let item = app.buttons["price-book-item-00000000-0000-4000-8000-000000009201"]
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        item.tap()
        let review = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Review estimate")).firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        review.tap()
        XCTAssertTrue(optionTitle.waitForExistence(timeout: 5))
        for _ in 0..<5 where !optionAdd.isHittable { app.swipeUp() }
        XCTAssertTrue(optionAdd.isHittable)
        optionAdd.tap()
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.typeText("Replace capacitor")
        let added = app.buttons.matching(identifier: "price-book-item-00000000-0000-4000-8000-000000009201")
            .matching(NSPredicate(format: "value == %@", "1 in draft")).firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 10), "The added line must remain in the selected option and Materials group")
    }

    func testDraftEstimateKeepsSaveUnavailableDuringCatalogReview() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "estimate-draft", "--paper-preview-catalog-pages"]
        app.launch()
        let search = app.textFields["Search price book or type a line"]
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        search.tap()
        let review = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Review estimate")).firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Draft changes can't be saved yet."].exists)
        review.tap()
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save draft")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
    }
}
