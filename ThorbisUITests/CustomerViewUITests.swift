import XCTest

/// BYR-1594: one Customer view door on the job reaches every estimate, each invoice and the
/// customer's own details, under one protected container with one staff hand-back.
@MainActor
final class CustomerViewUITests: XCTestCase {
    private let invoiceA = "00000000-0000-4000-8000-000000002209"
    private let estimateA = "00000000-0000-4000-8000-000000002218"

    func testCustomerViewOpensFromTheJobAndReachesEstimatesAnInvoiceAndYourDetails() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job",
                               "--paper-preview-job-documents", "--paper-preview-owner-auth", "approved"]
        app.launch()

        let door = app.buttons["job-customer-view"]
        XCTAssertTrue(door.waitForExistence(timeout: 20), "The job needs one visible Customer view door")
        XCTAssertEqual(door.label, "Show customer")
        door.tap()
        XCTAssertTrue(app.staticTexts["Your job documents"].waitForExistence(timeout: 10))
        capture(app, "Customer view home")

        // Estimates: the job's multi-estimate selection and approval.
        let approve = app.buttons["customer-view-approve-estimates"]
        XCTAssertTrue(approve.waitForExistence(timeout: 10))
        approve.tap()
        XCTAssertTrue(app.scrollViews["job-estimate-handoff"].waitForExistence(timeout: 10))
        capture(app, "Customer view estimates")
        back(app)

        // An invoice, with its own payments and balance.
        let invoice = app.buttons["customer-invoice-\(invoiceA)"]
        XCTAssertTrue(invoice.waitForExistence(timeout: 10))
        reveal(invoice, in: app)
        invoice.tap()
        XCTAssertTrue(app.navigationBars["INV-2209"].waitForExistence(timeout: 10))
        capture(app, "Customer view invoice")
        back(app)

        // Your details: the customer's own self-edit.
        let details = app.buttons["customer-view-details"]
        XCTAssertTrue(details.waitForExistence(timeout: 10))
        reveal(details, in: app)
        details.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Check what")).firstMatch.waitForExistence(timeout: 10))
        capture(app, "Customer view details")

        // One authenticated staff hand-back closes the whole Customer view.
        let exit = app.buttons.matching(identifier: "customer-mode-owner-exit").firstMatch
        XCTAssertTrue(exit.waitForExistence(timeout: 5))
        exit.tap()
        XCTAssertTrue(door.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Your job documents"].exists)
    }

    func testEstimateDetailOpensCustomerViewOnThatEstimateAndHandsBackToTheEstimate() {
        let app = launch(screen: "job-estimates")
        let row = app.buttons["job-estimate-\(estimateA)"]
        XCTAssertTrue(row.waitForExistence(timeout: 20)); row.tap()
        // #161: the estimate detail has no bar title; its heading is in the page.
        let door = detailDoor(app)
        XCTAssertTrue(door.waitForExistence(timeout: 10)); door.tap()
        // Opened on this estimate inside the protected container, ready to decide.
        XCTAssertTrue(app.navigationBars["EST-2218"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons.matching(identifier: "customer-mode-owner-exit").firstMatch.exists
                      || app.buttons["Technician: unlock to leave customer mode"].exists)
        capture(app, "Customer view estimate deep link")
        ownerExit(app)
        XCTAssertTrue(app.buttons["Show customer"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Your job documents"].exists)
    }

    func testInvoiceDetailOpensCustomerViewOnThatInvoice() {
        let app = launch(screen: "job-invoice")
        let paper = app.buttons["job-invoice-\(invoiceA)"]
        XCTAssertTrue(paper.waitForExistence(timeout: 20)); paper.tap()
        // #161: an invoice's Customer view moved into its ••• menu.
        let menu = app.buttons["Customer view, edit or open the PDF"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10)); menu.tap()
        let door = app.buttons["Customer view"].firstMatch
        XCTAssertTrue(door.waitForExistence(timeout: 5))
        door.tap()
        XCTAssertTrue(app.navigationBars["INV-2209"].waitForExistence(timeout: 15))
        capture(app, "Customer view invoice deep link")
        ownerExit(app)
        XCTAssertTrue(app.buttons["Customer view, edit or open the PDF"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Your job documents"].exists)
    }

    func testChangedDetailsStillGoThroughStaffReviewAfterHandBack() {
        let app = launch()
        let door = app.buttons["job-customer-view"]
        XCTAssertTrue(door.waitForExistence(timeout: 20)); door.tap()
        let details = app.buttons["customer-view-details"]
        XCTAssertTrue(details.waitForExistence(timeout: 10))
        reveal(details, in: app)
        details.tap()
        let name = app.textFields["Name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap(); name.typeText(" Jr")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Your job documents"].waitForExistence(timeout: 10))
        ownerExit(app)
        XCTAssertTrue(app.staticTexts["Review changes"].waitForExistence(timeout: 10), "Customer edits need the technician's review")
        capture(app, "Customer view details review")
        app.buttons["Discard changes"].tap()
        XCTAssertTrue(door.waitForExistence(timeout: 15))
    }

    private func launch(screen: String = "job") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", screen, "--paper-preview-working-job",
                               "--paper-preview-job-documents", "--paper-preview-owner-auth", "approved"]
        app.launch()
        return app
    }

    /// The detail screen's own door, not the job header's one still in the stack beneath it.
    private func detailDoor(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Show customer", "job-customer-view")).firstMatch
    }

    private func ownerExit(_ app: XCUIApplication) {
        let exit = app.buttons.matching(identifier: "customer-mode-owner-exit").firstMatch
        if exit.waitForExistence(timeout: 5) { exit.tap() } else { app.buttons["Technician: unlock to leave customer mode"].tap() }
    }

    /// Large cards can report hittable while their centre is still behind the fixed hand-back footer.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let list = app.scrollViews["customer-job-documents-list"]
        let bottom = app.buttons["Hand back to the technician"].firstMatch.frame.minY
        for _ in 0..<8 where !(element.isHittable && element.frame.maxY < bottom) {
            list.swipeUp(velocity: .slow)
        }
    }

    private func back(_ app: XCUIApplication) {
        let bar = app.navigationBars.firstMatch
        let back = bar.buttons["Customer view"].exists ? bar.buttons["Customer view"] : bar.buttons.element(boundBy: 0)
        back.tap()
        XCTAssertTrue(app.staticTexts["Your job documents"].waitForExistence(timeout: 10))
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
