import XCTest

@MainActor
final class CustomerDocumentBookSigningUITests: XCTestCase {
    func testAnUnsignedPaidInvoiceCanStillBeSignedWithoutCollectingAgain() {
        let app = paidInvoice(signed: false)
        let sign = app.buttons["Sign for the work"]
        XCTAssertTrue(sign.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pay $")).firstMatch.exists)
        sign.tap()
        XCTAssertTrue(app.textFields["Your full name"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.collectionViews["customer-document-pages"].exists)
    }

    func testAPaidInvoicesCurrentSignatureRemainsVisibleWithoutAnotherPaymentAction() {
        let app = paidInvoice(signed: true)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Signed by Preview customer")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Sign for the work"].exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pay $")).firstMatch.exists)
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "Paid invoice signature evidence"
        proof.lifetime = .keepAlways
        add(proof)
    }

    private func paidInvoice(signed: Bool) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job", "--paper-preview-job-documents"]
        if signed { app.launchArguments.append("--paper-preview-job-invoice-signed") }
        app.launch()
        XCTAssertTrue(app.buttons["Job actions"].waitForExistence(timeout: 15))
        app.buttons["Job actions"].tap()
        thorbisCustomerViewMenuItem(app).tap()
        let estimate = app.buttons["customer-estimate-00000000-0000-4000-8000-000000002218"]
        XCTAssertTrue(estimate.waitForExistence(timeout: 10))
        estimate.tap()
        XCTAssertTrue(app.buttons["Choose a job document"].waitForExistence(timeout: 10))
        app.buttons["Choose a job document"].tap()
        app.buttons["INV-2240"].tap()
        XCTAssertTrue(app.staticTexts["Deposit invoice"].waitForExistence(timeout: 10))
        return app
    }
}
