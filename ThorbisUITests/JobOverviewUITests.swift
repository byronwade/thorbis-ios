import XCTest

@MainActor
final class JobOverviewUITests: XCTestCase {
    func testMoreKeepsEverySecondaryActionAndOpensScheduling() {
        continueAfterFailure = false
        let app = preview("job")
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
        let app = preview("jobs")
        let job = app.staticTexts["Water heater install — Chen"].firstMatch
        XCTAssertTrue(job.waitForExistence(timeout: 15))
        job.tap()

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
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertTrue(directions.isHittable, "Directions must remain reachable below the enlarged header")
        capture(app, name: "Accessible contact actions after scrolling")
    }

    private func preview(_ screen: String, accessibleText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", screen]
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
