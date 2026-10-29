import XCTest

@MainActor
final class CustomerDocumentBookUITests: XCTestCase {
    func testEstimateReviewAndInvoiceSignatureLeaveTheSwipeSurface() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job", "--paper-preview-job-documents"]
        app.launch()
        XCTAssertTrue(app.buttons["Job actions"].waitForExistence(timeout: 15))
        app.buttons["Job actions"].tap()
        app.buttons["Show to customer"].tap()
        let estimate = app.buttons["customer-estimate-00000000-0000-4000-8000-000000002218"]
        XCTAssertTrue(estimate.waitForExistence(timeout: 10))
        estimate.tap()
        let review = app.buttons["customer-book-review-sign"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        thorbisStableButton(app, "customer-book-review-sign").tap()
        XCTAssertTrue(app.scrollViews["customer-estimate-presentation-00000000-0000-4000-8000-000000002218"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Approve and sign")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.collectionViews["customer-document-pages"].exists)
        XCTAssertTrue(app.buttons["Not today"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["customer-document-position"].waitForExistence(timeout: 5))
        app.buttons["Choose a job document"].tap()
        app.buttons["INV-2209"].tap()
        let sign = app.buttons["Sign for the work"]
        XCTAssertTrue(sign.waitForExistence(timeout: 10))
        sign.tap()
        XCTAssertTrue(app.textFields["Your full name"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.collectionViews["customer-document-pages"].exists)
        XCTAssertTrue(app.navigationBars["INV-2209"].exists)
    }

    func testSwipesAndButtonsBrowseEveryDocumentForOnlyThisJob() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job", "--paper-preview-job-documents"]
        app.launch()
        let actions = app.buttons["Job actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 15))
        actions.tap()
        app.buttons["Show to customer"].tap()
        let first = app.buttons["customer-estimate-00000000-0000-4000-8000-000000002218"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        let position = app.staticTexts["customer-document-position"]
        XCTAssertTrue(position.waitForExistence(timeout: 10))
        XCTAssertEqual(position.label, "1 of 4 documents")
        XCTAssertFalse(app.buttons["Previous document"].isEnabled)
        app.buttons["Next document"].tap()
        XCTAssertEqual(position.label, "2 of 4 documents")
        XCTAssertTrue(app.staticTexts["Water heater add-ons"].exists)
        app.collectionViews["customer-document-pages"].swipeLeft()
        XCTAssertTrue(app.staticTexts["customer-invoice-summary"].waitForExistence(timeout: 10))
        XCTAssertEqual(position.label, "3 of 4 documents")
        app.buttons["Next document"].tap()
        XCTAssertEqual(position.label, "4 of 4 documents")
        XCTAssertFalse(app.buttons["Next document"].isEnabled)
        XCTAssertFalse(app.staticTexts["INV-2241"].exists)
        XCTAssertFalse(app.staticTexts["Other job estimate"].exists)
        app.buttons["Previous document"].tap()
        XCTAssertEqual(position.label, "3 of 4 documents")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Job document paging"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
