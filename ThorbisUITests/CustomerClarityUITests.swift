import XCTest

@MainActor
final class CustomerClarityUITests: XCTestCase {
    func testLocationDetailsOpenInDrawerAndCanBeEdited() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer"]
        app.launch()
        let details = app.buttons["location-details-00000000-0000-4000-8000-000000007001"]
        for _ in 0..<8 where !details.isHittable { app.swipeUp() }
        XCTAssertTrue(details.waitForExistence(timeout: 15))
        XCTAssertTrue(details.isHittable)
        details.tap()
        XCTAssertTrue(app.staticTexts["Sample location for design preview"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Driveway on the left"].exists)
        capture("Customer location details")
        let edit = app.buttons["Edit location details"]
        XCTAssertTrue(edit.exists)
        edit.tap()
        XCTAssertTrue(app.staticTexts["Edit location"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Save changes"].exists)
    }

    func testLongLocationDetailsRemainReadableWithoutEditPermission() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer", "--paper-preview-customer-read-only", "--paper-preview-location-long-notes", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let details = app.buttons["location-details-00000000-0000-4000-8000-000000007001"]
        for _ in 0..<18 where !details.isHittable { app.swipeUp() }
        XCTAssertTrue(details.waitForExistence(timeout: 15))
        XCTAssertTrue(details.isHittable)
        details.tap()
        let notes = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Final paragraph: lock the side gate when you leave.")).firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Edit location details"].exists)
        capture("Long location details read only")
    }
    func testNextVisitStaysReadableAndOpensItsJob() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer", "-thorbis.appearance", "dark"]
        app.launch()
        let visit = app.buttons["customer-next-visit"]
        XCTAssertTrue(visit.waitForExistence(timeout: 30))
        XCTAssertTrue(visit.isHittable)
        capture("Customer dark overview")
        visit.tap()
        XCTAssertTrue(app.buttons["Job actions"].waitForExistence(timeout: 10))
    }

    func testCustomerNavigationRemainsUsableAfterScrolling() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer", "-thorbis.appearance", "dark"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Danielle Marlowe"].waitForExistence(timeout: 30))
        app.swipeUp()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.isHittable)
        capture("Customer dark scrolled navigation")
    }

    func testLongCustomerAndVisitRemainReadableAtLargestText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer", "--paper-preview-customer-name-long", "--paper-preview-customer-long-job", "-thorbis.appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let name = app.staticTexts["Birch Community Hall and Neighborhood Services Center"]
        XCTAssertTrue(name.waitForExistence(timeout: 30))
        XCTAssertGreaterThan(name.frame.height, 40)
        let visit = app.buttons["customer-next-visit"]
        for _ in 0..<10 where !visit.isHittable { app.swipeUp() }
        XCTAssertTrue(visit.isHittable)
        let title = app.staticTexts["Air conditioning is not cooling the upstairs rooms after several hours of running"]
        XCTAssertTrue(title.exists)
        XCTAssertGreaterThan(title.frame.height, 40)
        capture("Customer long name and visit, largest text")
        visit.tap()
        XCTAssertTrue(app.buttons["Job actions"].waitForExistence(timeout: 10))
    }
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
        let visit = app.buttons["customer-next-visit"]
        for _ in 0..<8 where !visit.isHittable { app.swipeUp() }
        XCTAssertTrue(visit.isHittable)
        capture("Customer overview large text")
    }

    func testBottomActionsFitAndExplainCustomerReviewAtLargestText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let customerAction = app.buttons["customer-handoff-action"]
        let newJob = app.buttons["customer-new-job-action"]
        XCTAssertTrue(app.staticTexts["Danielle Marlowe"].waitForExistence(timeout: 30))
        for _ in 0..<30 where !customerAction.isHittable { app.swipeUp() }
        XCTAssertTrue(customerAction.isHittable)
        XCTAssertEqual(customerAction.label, "Show to customer")
        XCTAssertGreaterThan(customerAction.frame.height, 80)
        for _ in 0..<4 where !newJob.isHittable { app.swipeUp() }
        XCTAssertTrue(newJob.isHittable)
        capture("Customer actions large text")
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
