import XCTest

@MainActor
final class CustomerClarityUITests: XCTestCase {
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
        // v2: the account's details sit on Overview itself (no "Customer details" disclosure).
        XCTAssertTrue(app.staticTexts["Billing terms"].waitForExistence(timeout: 10))
        // The tabs are Overview, "Jobs · N" and Money.
        let jobs = jobsTab(app)
        for _ in 0..<8 where !jobs.isHittable { app.swipeDown() }
        XCTAssertTrue(jobs.waitForExistence(timeout: 10))
        jobs.tap()
        let history = app.staticTexts.matching(NSPredicate(format: "label == %@ OR label == %@", "Open", "Past")).firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        capture("Customer jobs")
        XCTAssertFalse(app.staticTexts["Next visit"].exists)
        // The jobs' photos, notes and documents follow the history on the Jobs tab.
        let photos = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Photos")).firstMatch
        for _ in 0..<10 where !photos.exists { app.swipeUp() }
        XCTAssertTrue(photos.waitForExistence(timeout: 15), app.debugDescription)
        for _ in 0..<10 where !app.buttons["Overview"].isHittable { app.swipeDown() }
        app.buttons["Overview"].tap()
        let addContact = app.buttons["Add contact"]
        for _ in 0..<8 where !addContact.exists { app.swipeUp() }
        XCTAssertTrue(addContact.waitForExistence(timeout: 10))
        let addLocation = app.buttons["Add location"]
        for _ in 0..<8 where !addLocation.exists { app.swipeUp() }
        XCTAssertTrue(addLocation.exists)
    }

    func testNoJobsShowsAnHonestEmptyHistory() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer", "--paper-preview-customer-no-jobs"]
        app.launch()
        let jobs = jobsTab(app)
        XCTAssertTrue(jobs.waitForExistence(timeout: 30))
        jobs.tap()
        // The empty history names the one action (design.thorbis.com "Empty names the one action").
        XCTAssertTrue(app.staticTexts["No jobs yet."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Next visit"].exists)
    }

    /// The Jobs tab, labelled "Jobs · N" while jobs are visible.
    private func jobsTab(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", "Jobs", "Jobs ·")).firstMatch
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
        XCTAssertEqual(customerAction.label, "Customer view")
        // "Customer view" fits on one line now; the target still clears the large commit height.
        XCTAssertGreaterThanOrEqual(customerAction.frame.height, 56)
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
        XCTAssertEqual(customerAction.label, "Customer view")
        capture("Customer bottom actions largest standard text")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
