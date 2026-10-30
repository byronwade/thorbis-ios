import XCTest

@MainActor
final class CustomerClarityUITests: XCTestCase {
    func testCustomerOverviewUsesOneClearRouteToJobsAndKeepsDetails() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Danielle Marlowe"].waitForExistence(timeout: 30))
        capture("Customer overview")
        let details = app.buttons["Customer details"]
        XCTAssertTrue(details.waitForExistence(timeout: 10))
        details.tap()
        XCTAssertTrue(app.staticTexts["Billing terms"].waitForExistence(timeout: 5))
        let jobs = app.buttons["Jobs"]
        for _ in 0..<8 where !jobs.isHittable { app.swipeDown() }
        XCTAssertTrue(jobs.waitForExistence(timeout: 10))
        jobs.tap()
        XCTAssertTrue(app.staticTexts["All jobs"].waitForExistence(timeout: 10))
        capture("Customer jobs")
        XCTAssertFalse(app.staticTexts["Next visit"].exists)
        app.buttons["Overview"].tap()
        XCTAssertTrue(app.buttons["Add contact"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Add location"].exists)
        app.buttons["Records"].tap()
        XCTAssertTrue(app.staticTexts["Photos"].waitForExistence(timeout: 15), app.debugDescription)
    }

    func testNoJobsShowsAnHonestEmptyHistory() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer", "--paper-preview-customer-no-jobs"]
        app.launch()
        XCTAssertTrue(app.buttons["Jobs"].waitForExistence(timeout: 30))
        app.buttons["Jobs"].tap()
        XCTAssertTrue(app.staticTexts["No jobs"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Next visit"].exists)
    }

    func testLongJobTitleWrapsAtLargestText() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer", "--paper-preview-customer-long-job", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let title = app.staticTexts["Air conditioning is not cooling the upstairs rooms after several hours of running"]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        XCTAssertGreaterThan(title.frame.height, 40)
        for _ in 0..<8 where !title.isHittable { app.swipeUp() }
        XCTAssertTrue(title.isHittable)
        capture("Customer overview large text")
    }

    func testBottomActionsFitAndExplainCustomerReviewAtLargestText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let customerAction = app.buttons["customer-handoff-action"]
        let newJob = app.buttons["customer-new-job-action"]
        XCTAssertTrue(customerAction.waitForExistence(timeout: 30))
        XCTAssertTrue(newJob.waitForExistence(timeout: 10))
        let screen = app.windows.firstMatch.frame
        for action in [customerAction, newJob] {
            XCTAssertGreaterThanOrEqual(action.frame.minX, screen.minX)
            XCTAssertLessThanOrEqual(action.frame.maxX, screen.maxX)
            XCTAssertGreaterThanOrEqual(action.frame.minY, screen.minY)
            XCTAssertLessThanOrEqual(action.frame.maxY, screen.maxY)
            XCTAssertTrue(action.isHittable)
        }
        XCTAssertEqual(customerAction.label, "Show to customer")
        XCTAssertGreaterThan(customerAction.frame.height, 80)
        capture("Customer bottom actions large text")
    }

    func testBottomActionsFitAtLargestStandardText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"]
        app.launch()
        let customerAction = app.buttons["customer-handoff-action"]
        let newJob = app.buttons["customer-new-job-action"]
        XCTAssertTrue(customerAction.waitForExistence(timeout: 30))
        XCTAssertTrue(newJob.waitForExistence(timeout: 10))
        let screen = app.windows.firstMatch.frame
        for action in [customerAction, newJob] {
            XCTAssertGreaterThanOrEqual(action.frame.minX, screen.minX)
            XCTAssertLessThanOrEqual(action.frame.maxX, screen.maxX)
            XCTAssertGreaterThanOrEqual(action.frame.minY, screen.minY)
            XCTAssertLessThanOrEqual(action.frame.maxY, screen.maxY)
            XCTAssertTrue(action.isHittable)
        }
        XCTAssertEqual(customerAction.label, "Show to customer")
        capture("Customer bottom actions largest standard text")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
