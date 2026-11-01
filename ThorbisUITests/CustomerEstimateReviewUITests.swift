import XCTest

@MainActor
final class CustomerEstimateReviewUITests: XCTestCase {
    func testOpeningCannotApproveCallerTermsBeforeServerReadCompletes() {
        let app = preview(extra: ["--paper-preview-review-pending"])
        XCTAssertTrue(app.descendants(matching: .any)["customer-estimate-opening"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Approve")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["You're approving"].exists)
        XCTAssertTrue(app.buttons["Not today"].exists)
        capture(app, "Opening the canonical estimate")
    }

    func testReviewShowsCanonicalChoiceDescriptionAndPrice() {
        let app = preview(extra: ["--paper-preview-canonical-estimate"])
        XCTAssertTrue(app.staticTexts["Reviewed protection"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Verified surge protection"].exists)
        XCTAssertTrue(approveButton(app, total: "$543.21").exists)
        XCTAssertFalse(app.staticTexts["Surge protector, installed"].exists)
        capture(app, "Canonical customer estimate review")
    }

    func testFailedOpeningCanRetryWithoutApprovingStaleTerms() {
        let app = preview(extra: ["--paper-preview-canonical-estimate", "--paper-preview-review-failure"])
        let retry = app.buttons["Try again"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Approve")).firstMatch.exists)
        XCTAssertTrue(app.buttons["Not today"].exists)
        capture(app, "Estimate opening recovery")
        app.buttons["Restore sample connection"].tap()
        retry.tap()
        XCTAssertTrue(app.staticTexts["Reviewed protection"].waitForExistence(timeout: 10))
        XCTAssertTrue(approveButton(app, total: "$543.21").exists)
    }

    /// #161: the commit names the chosen option ("Approve Reviewed protection · $543.21", or
    /// "Approve · $543.21" when that doesn't fit). The exact total stays required.
    private func approveButton(_ app: XCUIApplication, total: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "Approve", "· " + total)).firstMatch
    }

    private func preview(extra: [String]) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "present-estimate-review"] + extra
        app.launch()
        return app
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = name
        proof.lifetime = .keepAlways
        add(proof)
    }
}
