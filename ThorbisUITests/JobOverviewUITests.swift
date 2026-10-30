import XCTest

@MainActor
final class JobOverviewUITests: XCTestCase {
    func testJobHeaderKeepsTitleClearOfNavigationAndBalanceOpensInvoice() {
        let app = preview("job", working: true)
        let title = app.staticTexts["AC not cooling"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        let bar = app.navigationBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(title.frame.minY, bar.frame.maxY,
                                    "The job title must not sit behind navigation controls")
        let balance = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Balance due")).firstMatch
        XCTAssertTrue(balance.waitForExistence(timeout: 20))
        XCTAssertTrue(balance.isHittable)
        capture(app, name: "Job header before invoice")
        balance.tap()
        XCTAssertTrue(app.staticTexts["Invoices"].waitForExistence(timeout: 10), "Tapping the balance should open invoice content")
    }

    /// The Thorbis back circle replaces the system one; both it and the edge swipe still go back.
    func testThorbisBackButtonAndEdgeSwipeReturnFromJob() {
        for useSwipe in [false, true] {
            let app = preview("job", working: true)
            let title = app.staticTexts["AC not cooling"]
            XCTAssertTrue(title.waitForExistence(timeout: 20))
            let back = app.navigationBars.firstMatch.buttons["Back"]
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(back.frame.width, 43.5)
            XCTAssertGreaterThanOrEqual(back.frame.height, 43.5)
            let actions = app.buttons["Job actions"]
            XCTAssertTrue(actions.exists)
            XCTAssertTrue(app.buttons["Share job"].exists)
            if useSwipe {
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
                start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
            } else {
                back.tap()
            }
            // The jobs list also shows the title, so watch the job's own controls leave.
            XCTAssertTrue(actions.waitForNonExistence(timeout: 5), useSwipe ? "Edge swipe should pop the job" : "Back should pop the job")
        }
    }

    func testDarkJobHeaderKeepsWorkAndPaymentVisible() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job", "-thorbis.appearance", "dark"]
        app.launch()
        let title = app.staticTexts["AC not cooling"]
        let collect = button(startingWith: "Collect ", in: app)
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        XCTAssertTrue(collect.waitForExistence(timeout: 20))
        XCTAssertTrue(title.isHittable)
        XCTAssertTrue(collect.isHittable)
        XCTAssertGreaterThanOrEqual(title.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        capture(app, name: "Dark job overview")
    }

    func testAllJobTabsRemainReachableAtStandardAndLargeText() {
        for accessible in [false, true] {
            let app = preview("job", accessibleText: accessible, working: true)
            if accessible {
                let chooser = app.buttons["job-section-chooser"]
                for _ in 0..<4 where !chooser.isHittable { app.swipeUp() }
                XCTAssertTrue(chooser.isHittable)
                chooser.tap()
            }
            let activity = app.buttons["Activity"]
            if !accessible { for _ in 0..<4 where !activity.isHittable { app.swipeUp() } }
            XCTAssertTrue(activity.waitForExistence(timeout: 10))
            XCTAssertTrue(activity.isHittable, "Activity should be visible without horizontal scrolling")
            XCTAssertLessThanOrEqual(activity.frame.maxX, app.frame.maxX)
            capture(app, name: accessible ? "Job tabs at large text" : "Job tabs on narrow phone")
            activity.tap()
            XCTAssertTrue(app.buttons["Notes"].waitForExistence(timeout: 10))
            app.terminate()
        }
    }

    func testCustomerLinkIsComfortableAndOpensCustomerProfile() {
        let app = preview("job", working: true)
        let customer = app.buttons["job-customer-link"]
        XCTAssertTrue(customer.waitForExistence(timeout: 20))
        XCTAssertGreaterThanOrEqual(customer.frame.height, 44)
        XCTAssertGreaterThanOrEqual(customer.frame.width, 44)
        XCTAssertTrue(customer.label.contains("Danielle Marlowe"))
        customer.tap()
        XCTAssertTrue(app.buttons["Customer actions"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Records"].exists)
    }

    func testShortCustomerNameStillHasComfortableTapTarget() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job",
                               "--paper-preview-short-customer-name"]
        app.launch()
        let customer = app.buttons["job-customer-link"]
        XCTAssertTrue(customer.waitForExistence(timeout: 20))
        XCTAssertEqual(customer.label, "I")
        XCTAssertGreaterThanOrEqual(customer.frame.width, 44)
        XCTAssertGreaterThanOrEqual(customer.frame.height, 44)
    }

    func testJobOverviewKeepsVisitActionsBeforeCustomerDetails() {
        let app = preview("job", working: true)
        let visit = app.staticTexts["On this visit"]
        let locations = app.staticTexts["Service addresses"]
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

        for title in ["Reschedule", "Add to Calendar", "Reassign technician", "Wrap up", "Follow-ups", "Customer view", "Copy job ID"] {
            let action = button(startingWith: title, in: app)
            XCTAssertTrue(action.waitForExistence(timeout: 3), "Missing secondary action: \(title)")
            // A long menu opens at half height and scrolls; reach lower rows the way a person would.
            if !action.isHittable { app.buttons["Reschedule"].swipeUp() }
            XCTAssertTrue(action.isHittable, "Secondary action is unreachable: \(title)")
        }
        capture(app, name: "Job More menu")

        if !app.buttons["Reschedule"].isHittable { app.buttons["Copy job ID"].swipeDown() }
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
        let directions = app.buttons["Directions"]
        let primary = app.buttons["On my way"]
        XCTAssertTrue(call.waitForExistence(timeout: 15))
        capture(app, name: "Job Overview with accessible text")
        XCTAssertGreaterThanOrEqual(text.frame.minY, call.frame.maxY)
        XCTAssertGreaterThanOrEqual(directions.frame.minY, text.frame.maxY)
        let content = app.scrollViews.containing(.button, identifier: "Directions").firstMatch
        for _ in 0..<3 where !directions.isHittable { content.swipeUp() }
        XCTAssertTrue(directions.isHittable, "Directions must remain reachable below the enlarged header")
        for _ in 0..<4 where !primary.isHittable { content.swipeUp() }
        XCTAssertTrue(primary.isHittable, "The primary action must remain reachable")
        XCTAssertGreaterThan(primary.frame.height, 50)
        capture(app, name: "Accessible contact actions after scrolling")
    }

    func testAccessiblePaymentActionScrollsWithTheJob() {
        continueAfterFailure = false
        let app = preview("job", accessibleText: true, working: true)
        let collect = button(startingWith: "Collect ", in: app)
        let content = app.scrollViews.firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 20))
        for _ in 0..<5 where !collect.isHittable { content.swipeUp() }
        XCTAssertTrue(collect.isHittable, "Collection must remain reachable")
        let initialY = collect.frame.minY
        content.swipeUp()
        XCTAssertTrue(!collect.exists || collect.frame.minY < initialY - 20,
                      "At large text the collection action must scroll away with the job")
    }

    func testAccessibleSectionChooserKeepsPhotosAndActivityReachable() {
        continueAfterFailure = false
        let app = preview("job", accessibleText: true, working: true)
        let chooser = app.buttons["job-section-chooser"]
        let content = app.scrollViews.firstMatch
        for _ in 0..<5 where !chooser.isHittable { content.swipeUp() }
        XCTAssertTrue(chooser.isHittable)
        XCTAssertTrue(chooser.label.contains("Overview"))
        chooser.tap()
        app.buttons["Photos"].tap()
        XCTAssertTrue(chooser.waitForExistence(timeout: 10))
        XCTAssertTrue(chooser.isHittable, "The chooser must remain reachable on Photos")
        XCTAssertTrue(chooser.label.contains("Photos"))
        chooser.tap()
        app.buttons["Activity"].tap()
        XCTAssertTrue(app.buttons["Notes"].waitForExistence(timeout: 10))
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
