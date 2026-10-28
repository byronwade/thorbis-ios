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
        XCTAssertTrue(app.buttons["Approve and sign · $543.21"].exists)
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
        XCTAssertTrue(app.buttons["Approve and sign · $543.21"].exists)
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
