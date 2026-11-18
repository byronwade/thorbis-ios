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

        XCTAssertTrue(app.staticTexts["job-title"].waitForExistence(timeout: 30))
        // Paper 21K: the job's Customer view door is a row in More.
        let door = thorbisCustomerViewDoor(app)
        XCTAssertTrue(door.waitForExistence(timeout: 20), "The job needs one Customer view door in More")
        XCTAssertTrue(door.label.hasPrefix("Customer view"), door.label)
        door.tap()
        XCTAssertTrue(app.staticTexts["customer-view-title"].waitForExistence(timeout: 10))
        capture(app, "Customer view home")

        // Estimates: the job's multi-estimate selection and approval.
        let approve = app.buttons["customer-view-approve-estimates"]
        // The button now sits under the cards; off-screen rows drop out of the snapshot.
        for _ in 0..<8 where !approve.exists { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(approve.waitForExistence(timeout: 10))
        reveal(approve, in: app)
        approve.tap()
        XCTAssertTrue(app.scrollViews["job-estimate-handoff"].waitForExistence(timeout: 10))
        capture(app, "Customer view estimates")
        back(app)

        // An invoice, with its own payments and balance.
        let invoice = app.buttons["customer-invoice-\(invoiceA)"]
        for _ in 0..<8 where !invoice.exists { app.swipeDown(velocity: .slow) }
        XCTAssertTrue(invoice.waitForExistence(timeout: 10))
        reveal(invoice, in: app)
        invoice.tap()
        XCTAssertTrue(app.navigationBars["INV-2209"].waitForExistence(timeout: 10))
        capture(app, "Customer view invoice")
        back(app)

        // Your details: the customer's own self-edit.
        let details = revealCustomerDetails(in: app)
        XCTAssertTrue(details.waitForExistence(timeout: 10))
        reveal(details, in: app)
        details.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "uses these to reach you")).firstMatch.waitForExistence(timeout: 10))
        capture(app, "Customer view details")

        // One authenticated staff hand-back closes the whole Customer view.
        let exit = app.buttons.matching(identifier: "customer-mode-owner-exit").firstMatch
        XCTAssertTrue(exit.waitForExistence(timeout: 5))
        exit.tap()
        // Back on the staff job: its More circle answers and the door is in More again.
        XCTAssertTrue(thorbisWaitForStaffJob(app), "The staff job must answer again after the hand-back")
        XCTAssertFalse(app.staticTexts["customer-view-title"].exists)
        XCTAssertTrue(thorbisCustomerViewDoor(app).waitForExistence(timeout: 15))
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
        XCTAssertFalse(app.staticTexts["customer-view-title"].exists)
    }

    func testInvoiceDetailOpensCustomerViewOnThatInvoice() {
        let app = launch(screen: "job-invoice")
        let paper = app.buttons["job-invoice-\(invoiceA)"]
        XCTAssertTrue(paper.waitForExistence(timeout: 20))
        // Cream sheet: the invoice row can start under the pinned Collect payment commit.
        app.scrollClearOfFoot(paper)
        paper.tap()
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
        XCTAssertFalse(app.staticTexts["customer-view-title"].exists)
    }

    func testChangedDetailsStillGoThroughStaffReviewAfterHandBack() {
        let app = launch()
        // Paper 21K: the door is More › Customer view.
        let door = thorbisCustomerViewDoor(app)
        XCTAssertTrue(door.waitForExistence(timeout: 20))
        door.tap()
        XCTAssertTrue(app.staticTexts["customer-view-title"].waitForExistence(timeout: 10))
        let details = revealCustomerDetails(in: app)
        XCTAssertTrue(details.waitForExistence(timeout: 10))
        reveal(details, in: app)
        details.tap()
        let name = app.textFields["Name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap(); name.typeText(" Jr")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["customer-view-title"].waitForExistence(timeout: 10))
        ownerExit(app)
        XCTAssertTrue(app.staticTexts["Review changes"].waitForExistence(timeout: 10), "Customer edits need the technician's review")
        capture(app, "Customer view details review")
        app.buttons["Discard changes"].tap()
        XCTAssertTrue(app.buttons["Job actions"].waitForExistence(timeout: 15))
        XCTAssertTrue(thorbisCustomerViewDoor(app).waitForExistence(timeout: 10))
    }

    /// Presenting one estimate from a job that has two: the customer gets the job's whole Customer
    /// view (the same verified, locked hand-off as "Show estimates"), opened on the tapped estimate,
    /// can page to the other one, sees both on the home, and staff screens stay locked until unlock.
    func testPresentingAnEstimateOnAJobWithTwoEstimatesShowsBothAndReachesTheSecond() {
        let app = launch(screen: "job-estimates")
        let row = app.buttons["job-estimate-\(estimateA)"]
        XCTAssertTrue(row.waitForExistence(timeout: 20)); row.tap()
        let door = detailDoor(app)
        XCTAssertTrue(door.waitForExistence(timeout: 10)); door.tap()
        // Starts on the estimate the technician tapped.
        XCTAssertTrue(app.navigationBars["EST-2218"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["customer-document-position"].waitForExistence(timeout: 10))
        // The job's second estimate is one step away.
        let next = app.buttons["Next document"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5)); next.tap()
        XCTAssertTrue(app.navigationBars["EST-2238"].waitForExistence(timeout: 10), "The job's other estimate must be reachable")
        // Still locked: no staff control answers under Customer view.
        XCTAssertFalse(app.buttons["Job actions"].exists && app.buttons["Job actions"].isHittable)
        XCTAssertFalse(app.buttons["Show customer"].exists && app.buttons["Show customer"].firstMatch.isHittable)
        // Back on the customer's home both estimates are listed together.
        back(app)
        let estimates = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "customer-estimate-"))
        XCTAssertGreaterThanOrEqual(estimates.count, 2, "Customer view lists every estimate on the job")
        capture(app, "Customer view from one of two estimates")
        // Only the technician's unlock returns to staff screens.
        XCTAssertFalse(app.buttons["Job actions"].exists && app.buttons["Job actions"].isHittable)
        ownerExit(app)
        XCTAssertTrue(app.buttons["Show customer"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["customer-view-title"].exists)
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
        app.buttons.matching(NSPredicate(format: "label == %@", "Show customer")).firstMatch
    }

    private func ownerExit(_ app: XCUIApplication) {
        let exit = app.buttons.matching(identifier: "customer-mode-owner-exit").firstMatch
        if exit.waitForExistence(timeout: 5) { exit.tap(); return }
        let lock = app.buttons["Technician: unlock to leave customer mode"]
        if lock.exists { lock.tap(); return }
        // Paper 38B: Customer view's home has no bar. Handing back is the pill at its foot, then the
        // technician's unlock on the hand-back screen.
        app.buttons["Hand back to the technician"].tap()
        let unlock = app.buttons["Technician: unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 10)); unlock.tap()
    }

    /// Details sit under estimates and invoices; iOS 26 snapshots often omit off-screen SwiftUI rows.
    private func revealCustomerDetails(in app: XCUIApplication) -> XCUIElement {
        let details = app.buttons["customer-view-details"]
        let list = documentsList(in: app)
        for _ in 0..<8 where !details.exists {
            if list.exists {
                list.swipeUp(velocity: .slow)
            } else {
                app.swipeUp(velocity: .slow)
            }
        }
        return details
    }

    private func documentsList(in app: XCUIApplication) -> XCUIElement {
        let scroll = app.scrollViews["customer-job-documents-list"]
        return scroll.exists ? scroll : app.otherElements["customer-job-documents-list"]
    }

    /// Large cards can report hittable while their centre is still behind the fixed hand-back footer.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let list = documentsList(in: app)
        let footer = app.buttons["Hand back to the technician"].firstMatch
        for _ in 0..<12 {
            let top = app.navigationBars.firstMatch.frame.maxY
            let bottom = footer.exists ? footer.frame.minY : app.frame.maxY
            if element.isHittable && element.frame.midY > top && element.frame.midY < bottom { return }
            guard list.exists else { return }
            if element.frame.midY <= top { list.swipeDown(velocity: .slow) } else { list.swipeUp(velocity: .slow) }
        }
        XCTFail("Customer view control must be hittable and clear of navigation and hand-back controls")
    }

    private func back(_ app: XCUIApplication) {
        let bar = app.navigationBars.firstMatch
        let back = bar.buttons["Customer view"].exists ? bar.buttons["Customer view"] : bar.buttons.element(boundBy: 0)
        back.tap()
        XCTAssertTrue(app.staticTexts["customer-view-title"].waitForExistence(timeout: 10))
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
