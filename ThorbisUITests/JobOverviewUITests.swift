import XCTest

@MainActor
final class JobOverviewUITests: XCTestCase {
    func testJobOverviewKeepsVisitActionsBeforeCustomerDetails() {
        let app = preview("job", working: true)
        let visit = app.staticTexts["On this visit"]
        let locations = app.staticTexts["Customer locations"]
        XCTAssertTrue(visit.waitForExistence(timeout: 20))
        XCTAssertTrue(locations.waitForExistence(timeout: 20))
        XCTAssertLessThan(visit.frame.minY, locations.frame.minY)
        XCTAssertTrue(button(startingWith: "Notes", in: app).exists)
        XCTAssertTrue(button(startingWith: "Photos", in: app).exists)
        let details = app.buttons["More job details"]
        for _ in 0..<8 where !details.isHittable { app.swipeUp() }
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        details.tap()
        let jobID = app.staticTexts["Job ID"]
        for _ in 0..<4 where !jobID.isHittable { app.swipeUp() }
        XCTAssertTrue(jobID.waitForExistence(timeout: 5))
        XCTAssertTrue(jobID.isHittable)
    }

    func testDocumentTabsKeepJobNameWithoutRepeatingOverviewActions() {
        let app = preview("job", working: true)
        XCTAssertTrue(app.buttons["Estimates"].waitForExistence(timeout: 20))
        app.buttons["Estimates"].tap()
        XCTAssertTrue(app.buttons["Call"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Step ")).firstMatch.exists)
        XCTAssertTrue(app.buttons["Overview"].exists)
        app.buttons["Overview"].tap()
        XCTAssertTrue(app.buttons["Call"].waitForExistence(timeout: 5))
    }

    func testSingleEstimateOptionUsesSingularLabel() {
        let app = preview("job-estimates", working: true)
        XCTAssertTrue(app.staticTexts["1 option"].waitForExistence(timeout: 20))
    }

    func testLongJobTitleWrapsOnEstimateTab() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job-estimates",
                               "--paper-preview-working-job", "--paper-preview-long-job-title"]
        app.launch()
        let title = app.staticTexts["Diagnose the upstairs air conditioner and replace the damaged compressor at the back of the property"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        XCTAssertGreaterThan(title.frame.height, 70, "The complete job title should wrap beyond two lines")
        XCTAssertTrue(app.buttons["Job actions"].exists)
    }

    func testMoreKeepsEverySecondaryActionAndOpensScheduling() {
        continueAfterFailure = false
        let app = preview("job", working: true)
        // The financial step appears only after the job's paper finishes loading.
        // Open the menu on the loaded record, rather than during its initial redraws.
        XCTAssertTrue(button(startingWith: "Collect ", in: app).waitForExistence(timeout: 15))
        let more = app.buttons["Job actions"]
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        more.tap()

        for title in ["Reschedule", "Reassign technician", "Wrap up", "Follow-ups", "Show to customer", "Copy job ID"] {
            let action = button(startingWith: title, in: app)
            XCTAssertTrue(action.waitForExistence(timeout: 3), "Missing secondary action: \(title)")
            XCTAssertTrue(action.isHittable, "Secondary action is unreachable: \(title)")
        }
        capture(app, name: "Job More menu")

        app.buttons["Reschedule"].tap()
        XCTAssertTrue(app.buttons["Save schedule"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(more.waitForExistence(timeout: 5))
    }

    func testInProgressJobKeepsItsPaymentStepAndWrapUpChecklist() {
        continueAfterFailure = false
        let app = preview("job", working: true)

        let collect = button(startingWith: "Collect ", in: app)
        XCTAssertTrue(collect.waitForExistence(timeout: 10))
        XCTAssertTrue(collect.isHittable)
        capture(app, name: "In-progress Job Overview")
        app.buttons["Job actions"].tap()
        button(startingWith: "Wrap up", in: app).tap()
        XCTAssertTrue(app.staticTexts["Wrap up this job"].waitForExistence(timeout: 5))
    }

    func testAccessibleTextKeepsContactActionsSeparateAndThePrimaryActionReadable() {
        continueAfterFailure = false
        let app = preview("job", accessibleText: true)
        let call = app.buttons["Call"]
        let text = app.buttons["Text"]
        let directions = app.buttons["Directions in Maps"]
        let primary = app.buttons["On my way"]
        XCTAssertTrue(call.waitForExistence(timeout: 15))
        XCTAssertTrue(primary.waitForExistence(timeout: 5))
        capture(app, name: "Job Overview with accessible text")
        XCTAssertGreaterThanOrEqual(text.frame.minY, call.frame.maxY)
        XCTAssertGreaterThanOrEqual(directions.frame.minY, text.frame.maxY)
        XCTAssertGreaterThan(primary.frame.height, 50)
        XCTAssertTrue(primary.isHittable)
        let content = app.scrollViews.containing(.button, identifier: "Directions in Maps").firstMatch
        for _ in 0..<3 where !directions.isHittable { content.swipeUp() }
        XCTAssertTrue(directions.isHittable, "Directions must remain reachable below the enlarged header")
        capture(app, name: "Accessible contact actions after scrolling")
    }

    private func preview(_ screen: String, accessibleText: Bool = false, working: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", screen]
        if working { app.launchArguments += ["--paper-preview-working-job"] }
        if accessibleText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-thorbis.appearance", "dark"]
        }
        app.launch()
        return app
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func button(startingWith title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }
}
