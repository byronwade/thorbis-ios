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
            let activity = thorbisSection(app, "Activity")
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

    /// Off Overview the header is one line (title and status word); the customer, balance, Customer
    /// view and Call/Text/Directions live on Overview and come back with it.
    func testDocumentTabsKeepJobNameWithoutRepeatingOverviewActions() {
        let app = preview("job", working: true)
        XCTAssertTrue(app.buttons["Call"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["job-customer-view"].exists)
        XCTAssertTrue(thorbisSection(app, "Money").waitForExistence(timeout: 20))
        for tab in ["Money", "Activity"] {
            app.buttons[tab].tap()
            XCTAssertTrue(app.staticTexts["AC not cooling"].waitForExistence(timeout: 5), "\(tab) keeps the job's name")
            XCTAssertTrue(app.staticTexts["Job status, In progress"].exists || app.otherElements["Job status, In progress"].exists,
                          "\(tab) keeps the status as a word")
            XCTAssertFalse(app.buttons["Call"].exists, "\(tab) must not repeat Overview's contact actions")
            XCTAssertFalse(app.buttons["job-customer-link"].exists, "\(tab) must not repeat the customer line")
            XCTAssertFalse(app.buttons["job-customer-view"].exists, "\(tab) must not repeat the header's Customer view")
            XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Balance due")).firstMatch.exists,
                           "\(tab) must not repeat the balance")
            XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Step ")).firstMatch.exists)
        }
        thorbisSection(app, "Overview").tap()
        XCTAssertTrue(app.buttons["Call"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["job-customer-view"].exists)
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
        // Money's header is one line of title and status, but a long title still wraps in full.
        XCTAssertGreaterThan(title.frame.height, 45, "The complete job title should wrap instead of truncating")
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
            // The header door shares the name; check the menu's own row.
            let action = title == "Customer view" ? thorbisCustomerViewMenuItem(app) : button(startingWith: title, in: app)
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
        thorbisSection(app, "Activity").tap()
        let photos = app.buttons["activity-filter-photos"]
        for _ in 0..<5 where !photos.isHittable { content.swipeUp() }
        XCTAssertTrue(photos.isHittable)
        photos.tap()
        XCTAssertTrue(chooser.waitForExistence(timeout: 10))
        XCTAssertTrue(chooser.isHittable, "The chooser must remain reachable on Photos")
        XCTAssertTrue(chooser.label.contains("Activity"))
        XCTAssertTrue(app.buttons["activity-filter-notes"].isHittable, "Photos must be able to switch back to notes")
        app.buttons["activity-filter-notes"].tap()
        XCTAssertTrue(app.staticTexts["Note"].firstMatch.waitForExistence(timeout: 10) || app.staticTexts["No activity yet"].exists)
    }

    /// F9: the current-job chip never repeats Jobs' In progress row and never hides a list's last row.
    func testCurrentJobChipStaysOffJobsAndClearsTheLastRowOnMore() {
        continueAfterFailure = false
        let chipQuery = NSPredicate(format: "label BEGINSWITH %@", "Current job")
        let jobs = preview("jobs", working: true)
        XCTAssertTrue(jobs.staticTexts["In progress"].waitForExistence(timeout: 20))
        XCTAssertFalse(jobs.buttons.matching(chipQuery).firstMatch.exists, "Jobs already leads with the job in progress")
        jobs.terminate()

        let app = preview("more", working: true)
        let chip = app.buttons.matching(chipQuery).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 20))
        let signOut = app.buttons["Sign out"]
        for _ in 0..<8 { app.swipeUp() }
        capture(app, name: "More scrolled to the end under the current job")
        XCTAssertTrue(signOut.isHittable)
        XCTAssertLessThanOrEqual(signOut.frame.maxY, chip.frame.minY, "The last rows must scroll clear of the chip")
        let version = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Thorbis Field")).firstMatch
        XCTAssertTrue(version.exists)
        XCTAssertLessThanOrEqual(version.frame.maxY, chip.frame.minY, "The very last line must scroll clear of the chip")
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
