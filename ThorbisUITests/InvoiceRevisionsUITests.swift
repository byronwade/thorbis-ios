import XCTest

/// Reopen a completed job and add an approved estimate to the job's invoice, both behind server
/// flags the preview turns on with `--paper-preview-invoice-revisions` (sample answers, no server).
@MainActor
final class InvoiceRevisionsUITests: XCTestCase {
    private let approvedEstimate = "00000000-0000-4000-8000-000000002238"

    private func launch(_ screen: String, _ extra: [String]) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", screen] + extra
        app.launch()
        return app
    }

    private func reopenRow(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reopen job'")).firstMatch
    }

    func testACompletedJobReopensFromItsMenuAfterAConfirm() {
        let app = launch("job", ["--paper-preview-job-status", "completed", "--paper-preview-invoice-revisions"])
        let more = app.buttons["Job actions"]
        XCTAssertTrue(more.waitForExistence(timeout: 20)); more.tap()
        let row = reopenRow(app)
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.staticTexts["Reopen this job?"].waitForExistence(timeout: 5), "Reopening asks first")
        XCTAssertTrue(app.textFields["job-reopen-reason"].exists || app.textViews["job-reopen-reason"].exists, "The reason is offered")
        let confirm = app.buttons["Reopen job"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        let working = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Working'")).firstMatch
        XCTAssertTrue(working.waitForExistence(timeout: 10), "The job is a working job again")
        more.tap()
        XCTAssertFalse(reopenRow(app).waitForExistence(timeout: 2), "A working job has nothing to reopen")
    }

    func testReopenIsHiddenWhileItsFlagIsOff() {
        let app = launch("job", ["--paper-preview-job-status", "completed"])
        let more = app.buttons["Job actions"]
        XCTAssertTrue(more.waitForExistence(timeout: 20))
        // The job first shows the copy the last launch saved, which may not be a completed job. Open
        // the menu once this launch's completed job is on screen, so its status is not what hides Reopen.
        let completed = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Job status, Completed")).firstMatch
        XCTAssertTrue(completed.waitForExistence(timeout: 10), "The job is a completed job")
        more.tap()
        XCTAssertTrue(app.staticTexts["More"].waitForExistence(timeout: 5))
        XCTAssertFalse(reopenRow(app).exists)
    }

    func testAnApprovedEstimateIsAddedToTheInvoiceOnlyAfterAConfirm() {
        let app = launch("job-estimates", ["--paper-preview-job-documents", "--paper-preview-approved-unknown-total",
                                           "--paper-preview-invoice-revisions"])
        let add = app.buttons["job-estimate-add-to-invoice-\(approvedEstimate)"]
        XCTAssertTrue(add.waitForExistence(timeout: 20)); add.tap()
        XCTAssertTrue(app.staticTexts["Add to the invoice?"].waitForExistence(timeout: 5), "Never added silently")
        app.buttons["Not now"].tap()
        XCTAssertTrue(add.waitForExistence(timeout: 5), "Declining leaves the offer")
        add.tap()
        let confirm = app.buttons["Add to invoice"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: add)],
                                      timeout: 10), .completed, "Once on the invoice it is not offered again")
        XCTAssertTrue(app.buttons["job-estimate-\(approvedEstimate)"].exists, "The estimate's own row stays")
    }

    func testAddToInvoiceIsHiddenWhileItsFlagIsOff() {
        let app = launch("job-estimates", ["--paper-preview-job-documents", "--paper-preview-approved-unknown-total"])
        XCTAssertTrue(app.buttons["job-estimate-\(approvedEstimate)"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["job-estimate-add-to-invoice-\(approvedEstimate)"].exists)
    }

    func testAnIssuedInvoiceShowsItsChangesAndOpensForEditingOnlyWithTheFlag() {
        let on = launch("invoice-detail", ["--paper-preview-invoice-revisions"])
        XCTAssertTrue(on.buttons["invoice-detail-edit-items"].waitForExistence(timeout: 20))
        XCTAssertTrue(on.staticTexts["invoice-unsigned-version"].waitForExistence(timeout: 5))
        let change = on.buttons["invoice-change-2"]
        XCTAssertTrue(change.waitForExistence(timeout: 5))
        XCTAssertTrue(change.label.contains("Estimate added"), change.label)
        on.terminate()

        let off = launch("invoice-detail", [])
        XCTAssertTrue(off.staticTexts["invoice-detail-title"].waitForExistence(timeout: 20))
        // The title can be drawn from the invoice the first launch saved, and that copy never shows
        // Edit or the note. The page's menu exists only once this launch's invoice has answered.
        XCTAssertTrue(off.buttons["Customer view, edit or open the PDF"].waitForExistence(timeout: 20))
        XCTAssertFalse(off.buttons["invoice-detail-edit-items"].exists, "An issued invoice stays closed while the flag is off")
        XCTAssertFalse(off.staticTexts["invoice-unsigned-version"].exists)
    }
}
