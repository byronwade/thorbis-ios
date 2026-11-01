import XCTest

@MainActor
final class CustomerDocumentBookRecoveryUITests: XCTestCase {
    func testRefreshingTheSameStaleEstimateLoadsIssuedTermsWithoutLeavingItsPage() {
        let app = launch(extra: "--paper-preview-job-estimate-recovery")
        let estimate = app.buttons["customer-estimate-00000000-0000-4000-8000-000000002218"]
        XCTAssertTrue(estimate.waitForExistence(timeout: 10))
        XCTAssertTrue(estimate.isEnabled)
        app.buttons["Sample connection"].tap()
        app.buttons["Make sample estimate unavailable"].tap()
        let overview = app.scrollViews["customer-job-documents-list"]
        XCTAssertTrue(overview.exists)
        estimate.tap()
        let stale = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false"), object: estimate)
        XCTAssertEqual(XCTWaiter.wait(for: [stale], timeout: 10), .completed)

        let invoice = app.buttons["customer-invoice-00000000-0000-4000-8000-000000002209"]
        reveal(invoice, in: overview)
        invoice.tap()
        XCTAssertTrue(app.staticTexts["customer-invoice-summary"].waitForExistence(timeout: 10))
        choose("EST-2218", in: app)
        XCTAssertTrue(app.staticTexts["This copy needs a refresh before you can decide."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Review and sign"].exists)
        XCTAssertEqual(app.staticTexts["customer-document-position"].label, "1 of 4 documents")
        app.buttons["Sample connection"].tap()
        app.buttons["Restore sample connection"].tap()
        app.buttons["Refresh documents"].tap()
        XCTAssertTrue(app.buttons["Review and sign"].waitForExistence(timeout: 10), "An identical refreshed estimate must reload its issued terms")
        XCTAssertFalse(app.staticTexts["This copy needs a refresh before you can decide."].exists)
        XCTAssertEqual(app.staticTexts["customer-document-position"].label, "1 of 4 documents")
        XCTAssertTrue(app.staticTexts["Main drain repair"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Compressor diagnostic")).firstMatch.exists)
        capture(app, name: "Stale estimate recovered on the same page")
    }

    func testInvalidDraftAmountsShowAnExplicitUnavailableStateWithoutCrashing() {
        let app = launch(extra: "--paper-preview-job-estimate-invalid-money")
        let draft = app.buttons["customer-estimate-00000000-0000-4000-8000-000000002238"]
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        draft.tap()
        let error = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "These amounts couldn’t be verified", "These amounts couldn't be verified")).firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 10), "Unchecked or unverifiable amounts must never reach the line card")
        XCTAssertTrue(app.buttons["Next document"].exists)
        XCTAssertFalse(app.buttons["Review and sign"].exists)
        XCTAssertFalse(app.buttons["Sign for the work"].exists)
        capture(app, name: "Unverifiable draft estimate amounts")
    }

    private func launch(extra: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job",
                               "--paper-preview-job-documents", extra]
        app.launch()
        XCTAssertTrue(app.buttons["Job actions"].waitForExistence(timeout: 15))
        app.buttons["Job actions"].tap()
        thorbisCustomerViewMenuItem(app).tap()
        return app
    }

    private func choose(_ reference: String, in app: XCUIApplication) {
        app.buttons["Choose a job document"].tap()
        app.buttons[reference].tap()
    }

    private func reveal(_ element: XCUIElement, in scroll: XCUIElement) {
        for _ in 0..<5 {
            if element.exists && element.isHittable { return }
            scroll.swipeUp()
        }
        XCTAssertTrue(element.exists)
        XCTAssertTrue(element.isHittable)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
