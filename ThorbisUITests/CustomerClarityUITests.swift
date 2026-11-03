import XCTest

@MainActor
final class CustomerClarityUITests: XCTestCase {
    func testContactOffersDirectCallAndTextWithoutHidingOtherActions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer", "--paper-preview-scroll", "center"]
        app.launch()
        let call = app.buttons["Call Danielle Marlowe"]
        XCTAssertTrue(app.staticTexts["Contacts"].waitForExistence(timeout: 20))
        app.swipeUp()
        for _ in 0..<12 where !call.isHittable { app.swipeUp() }
        XCTAssertTrue(call.waitForExistence(timeout: 20))
        XCTAssertTrue(call.isHittable)
        XCTAssertGreaterThanOrEqual(call.frame.height, 44)
        XCTAssertGreaterThanOrEqual(call.frame.width, 44)
        let text = app.buttons["Text Danielle Marlowe"]
        XCTAssertTrue(text.isHittable)
        XCTAssertGreaterThanOrEqual(text.frame.height, 44)
        XCTAssertGreaterThanOrEqual(text.frame.width, 44)
        let actions = app.buttons["Contact actions for Danielle Marlowe"]
        XCTAssertTrue(actions.isHittable)
        capture("Customer contacts and quick actions")
        actions.tap()
        XCTAssertTrue(app.buttons["Save to Contacts"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["Edit contact"].waitForExistence(timeout: 5), app.debugDescription)
    }

    func testContactActionsStayReachableAtLargestText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer", "--paper-preview-customer-name-long", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let name = "Birch Community Hall and Neighborhood Services Center"
        let call = app.buttons["Call \(name)"]
        for _ in 0..<20 where !call.isHittable { app.swipeUp() }
        XCTAssertTrue(call.waitForExistence(timeout: 20))
        XCTAssertTrue(call.isHittable)
        XCTAssertGreaterThanOrEqual(call.frame.width, 44)
        XCTAssertGreaterThanOrEqual(call.frame.height, 44)
        XCTAssertTrue(app.buttons["Text \(name)"].isHittable)
        XCTAssertTrue(app.buttons["Contact actions for \(name)"].isHittable)
        capture("Customer contact and quick actions, largest text")
    }
    func testLongLocationNoteOpensReaderAndExistingEditor() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer", "--paper-preview-location-long-note", "--paper-preview-scroll", "center", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let more = app.buttons["location-note-more-00000000-0000-4000-8000-000000007001"]
        for _ in 0..<16 where !more.isHittable { app.swipeUp() }
        XCTAssertTrue(more.waitForExistence(timeout: 20))
        XCTAssertTrue(more.isHittable)
        capture("Customer location note preview, largest text")
        more.tap()
        let full = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "final paragraph contains the site-specific cleanup instructions")).firstMatch
        XCTAssertTrue(full.waitForExistence(timeout: 10))
        capture("Customer location note reader")
        let edit = app.buttons["Edit location"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(app.buttons["Cancel location changes"].waitForExistence(timeout: 10))
    }

    func testLocationNoteDenialClosesReaderAndFreshReadRestoresIt() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer", "--paper-preview-location-long-note", "--paper-preview-location-note-denial", "--paper-preview-scroll", "center"]
        app.launch()
        let more = app.buttons["location-note-more-00000000-0000-4000-8000-000000007001"]
        XCTAssertTrue(more.waitForExistence(timeout: 30))
        for _ in 0..<8 where !more.isHittable { app.swipeUp() }
        XCTAssertTrue(more.isHittable)
        app.buttons["Deny sample location shortly"].tap()
        more.tap()
        XCTAssertTrue(app.navigationBars["Site notes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Site notes"].waitForNonExistence(timeout: 20))
        XCTAssertFalse(more.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "final paragraph contains the site-specific cleanup instructions")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Site notes unavailable. Refresh to try again."].exists)
        app.buttons["Restore sample location"].tap()
        XCTAssertTrue(more.waitForExistence(timeout: 15))
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
        // The name is the page's title and, here, also its primary contact; the title comes first.
        let name = app.staticTexts.matching(NSPredicate(format: "label == %@", "Birch Community Hall and Neighborhood Services Center")).firstMatch
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
        let newJob = app.buttons["customer-new-job-action"]
        XCTAssertTrue(app.staticTexts["Danielle Marlowe"].firstMatch.waitForExistence(timeout: 30))
        // At accessibility sizes New job follows the content instead of pinning over it.
        for _ in 0..<30 where !newJob.isHittable { app.swipeUp() }
        XCTAssertTrue(newJob.isHittable)
        XCTAssertGreaterThanOrEqual(newJob.frame.height, 44)
        capture("Customer actions large text")
        // v2: Customer view is one row of the Customer actions popover, not a second commit.
        for _ in 0..<30 where !app.buttons["Customer actions"].isHittable { app.swipeDown() }
        app.buttons["Customer actions"].tap()
        // The row reads "Customer view" over "Hand the phone over to check their details".
        let customerView = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Customer view")).firstMatch
        XCTAssertTrue(customerView.waitForExistence(timeout: 5))
    }

    func testBottomActionsFitAtLargestStandardText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"]
        app.launch()
        // v2: New job is the page's one ink commit; Customer view lives in Customer actions.
        let newJob = app.buttons["customer-new-job-action"]
        XCTAssertTrue(newJob.waitForExistence(timeout: 30))
        let screen = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(newJob.frame.minX, screen.minX)
        XCTAssertLessThanOrEqual(newJob.frame.maxX, screen.maxX)
        XCTAssertGreaterThanOrEqual(newJob.frame.minY, screen.minY)
        XCTAssertLessThanOrEqual(newJob.frame.maxY, screen.maxY)
        XCTAssertTrue(newJob.isHittable)
        XCTAssertEqual(newJob.label, "New job")
        capture("Customer bottom actions largest standard text")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
