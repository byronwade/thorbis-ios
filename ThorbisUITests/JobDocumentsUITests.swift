import XCTest

@MainActor
final class JobDocumentsUITests: XCTestCase {
    private let invoiceA = "00000000-0000-4000-8000-000000002209"
    private let depositA = "00000000-0000-4000-8000-000000002240"
    private let invoiceB = "00000000-0000-4000-8000-000000002241"
    private let estimateA = "00000000-0000-4000-8000-000000002218"
    private let addonA = "00000000-0000-4000-8000-000000002238"

    func testAllJobInvoicesAreVisibleAndOpenTheirOwnDetail() {
        continueAfterFailure = false
        let app = preview()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Collect $340.00")).firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Invoice"].waitForExistence(timeout: 15))
        app.buttons["Invoice"].tap()
        let issued = app.buttons["job-invoice-\(invoiceA)"]
        let deposit = app.buttons["job-invoice-\(depositA)"]
        XCTAssertTrue(issued.waitForExistence(timeout: 10))
        XCTAssertTrue(deposit.exists)
        XCTAssertFalse(app.buttons["job-invoice-\(invoiceB)"].exists)
        capture(app, "Every invoice for this job")
        deposit.tap()
        XCTAssertTrue(app.staticTexts["INV-2240"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["INV-2241"].exists)
    }

    func testCommercialHandoffListsOnlyThisJobsEstimatesAndInvoices() {
        continueAfterFailure = false
        let app = preview()
        let more = app.buttons["Job actions"]
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        more.tap()
        app.buttons["Show to customer"].tap()
        XCTAssertTrue(app.staticTexts["Your job documents"].waitForExistence(timeout: 10))
        for identifier in ["customer-estimate-\(estimateA)", "customer-estimate-\(addonA)",
                           "customer-invoice-\(invoiceA)", "customer-invoice-\(depositA)"] {
            XCTAssertTrue(app.buttons[identifier].exists, identifier)
        }
        XCTAssertFalse(app.buttons["customer-invoice-\(invoiceB)"].exists)
        XCTAssertFalse(app.staticTexts["Other job estimate"].exists)
        capture(app, "Customer job documents")
    }

    func testCustomerCanBrowseDraftWithoutIssuingItAndReturnToDocuments() {
        continueAfterFailure = false
        let app = preview()
        handToCustomer(app)
        app.buttons["customer-estimate-\(addonA)"].tap()
        XCTAssertTrue(app.navigationBars["EST-2238"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Water heater add-ons"].exists)
        XCTAssertFalse(app.buttons["Sign to approve"].exists)
        XCTAssertFalse(app.buttons["Send estimate"].exists)
        XCTAssertTrue(app.buttons["Technician: unlock to leave customer mode"].exists)
        app.navigationBars.buttons["Documents"].tap()
        XCTAssertTrue(app.buttons["customer-estimate-\(estimateA)"].waitForExistence(timeout: 5))
        app.buttons["customer-estimate-\(estimateA)"].tap()
        XCTAssertTrue(app.navigationBars["EST-2218"].waitForExistence(timeout: 5))
        capture(app, "Customer estimate review")
    }

    func testPartialEstimatesKeepSuccessfulPaperAndUnavailableReference() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-job-documents-partial"])
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Couldn't load all estimates")).firstMatch.waitForExistence(timeout: 15))
        app.buttons["Estimates"].tap()
        XCTAssertTrue(app.buttons["job-estimate-\(estimateA)"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["job-estimate-unavailable-\(addonA)"].exists)
        XCTAssertFalse(app.staticTexts["No estimates yet"].exists)
        capture(app, "Partial job estimates")
    }

    func testLargestTextAndDarkModeKeepEveryCustomerDocumentReachable() {
        continueAfterFailure = false
        let app = preview(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                                  "-thorbis.appearance", "dark"])
        handToCustomer(app)
        capture(app, "Accessible customer documents")
        let invoice = app.buttons["customer-invoice-\(invoiceA)"]
        reveal(invoice, in: app)
        invoice.tap()
        XCTAssertTrue(app.navigationBars["INV-2209"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Technician: unlock to leave customer mode"].exists)
        capture(app, "Accessible customer invoice")
    }

    func testCustomerPaymentReturnsToTheSelectedInvoicesStaffCollection() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-job-invoice-signed", "--paper-preview-owner-auth", "approved"])
        handToCustomer(app)
        let invoice = app.buttons["customer-invoice-\(invoiceA)"]
        reveal(invoice, in: app)
        invoice.tap()
        let pay = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pay $340.00")).firstMatch
        XCTAssertTrue(pay.waitForExistence(timeout: 5))
        pay.tap()
        let cash = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Cash")).firstMatch
        XCTAssertTrue(cash.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Your job documents"].exists)
        XCTAssertTrue(app.buttons["received-payment-methods"].exists)
        capture(app, "Selected invoice collection after customer handoff")
    }

    func testDeclinedOwnerAuthenticationKeepsCustomerOutOfStaffCollection() {
        continueAfterFailure = false
        let app = preview(extra: ["--paper-preview-job-invoice-signed", "--paper-preview-owner-auth", "denied"])
        handToCustomer(app)
        let invoice = app.buttons["customer-invoice-\(invoiceA)"]
        reveal(invoice, in: app)
        invoice.tap()
        let pay = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pay $340.00")).firstMatch
        XCTAssertTrue(pay.waitForExistence(timeout: 5))
        pay.tap()
        XCTAssertTrue(app.navigationBars["INV-2209"].exists)
        XCTAssertFalse(app.buttons["received-payment-methods"].exists)
        XCTAssertTrue(pay.isEnabled)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        let list = app.scrollViews["customer-job-documents-list"]
        let top = app.navigationBars["Documents"].frame.maxY
        let bottom = app.buttons["Hand back to the technician"].frame.minY
        // Large cards can report hittable while their center is still behind the fixed footer.
        for _ in 0..<10 {
            if element.isHittable && element.frame.midY > top && element.frame.midY < bottom { break }
            list.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
        XCTAssertGreaterThan(element.frame.midY, top)
        XCTAssertLessThan(element.frame.midY, bottom)
    }

    private func handToCustomer(_ app: XCUIApplication) {
        let more = app.buttons["Job actions"]
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        more.tap()
        let show = app.buttons["Show to customer"]
        for _ in 0..<5 where !show.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(show.isHittable)
        show.tap()
        XCTAssertTrue(app.staticTexts["Your job documents"].waitForExistence(timeout: 10))
    }

    private func preview(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job", "--paper-preview-job-documents"] + extra
        app.launch()
        return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
