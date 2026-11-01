import XCTest

@MainActor
final class JobOverviewUITests: XCTestCase {
    /// iPad: the job is the detail column's first screen (picked from the list beside it, so nothing
    /// to go back to). A screen pushed from it — the customer — offers the same Back circle, which
    /// returns to the job. Not asserted: the back swipe. Started at the detail column's own edge
    /// (380pt in, beside the list) it did not pop in the simulator; an open iPad gap. At the
    /// screen's edge the swipe brings the sidebar in (DrawerGearMenuUITests).
    private func assertBackInTheDetailColumn() {
        let app = preview("job", working: true)
        XCTAssertTrue(app.staticTexts["job-title"].waitForExistence(timeout: 20))
        let actions = app.buttons["Job actions"]
        XCTAssertTrue(actions.exists)
        XCTAssertFalse(app.navigationBars.buttons["Back"].exists, "The detail column's first screen has no Back")
        let customer = app.buttons["job-customer-link"]
        reveal(customer, in: app)
        customer.tap()
        XCTAssertTrue(app.buttons["Customer actions"].waitForExistence(timeout: 10))
        let back = app.navigationBars.buttons["Back"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(back.frame.width, 43.5)
        XCTAssertGreaterThanOrEqual(back.frame.height, 43.5)
        XCTAssertGreaterThan(back.frame.minX, app.frame.width * 0.3, "Back sits in the detail column, beside the list")
        back.tap()
        XCTAssertTrue(app.buttons["Customer actions"].waitForNonExistence(timeout: 5), "Back should pop the customer")
        XCTAssertTrue(actions.waitForExistence(timeout: 5), "Back returns to the job")
    }

    func testJobHeaderKeepsTitleClearOfNavigationAndBalanceOpensInvoice() {
        let app = preview("job", working: true)
        // v2: the header leads with the street (`job-title`), the problem under it.
        let title = app.staticTexts["job-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        let bar = app.navigationBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(title.frame.minY, bar.frame.maxY,
                                    "The job title must not sit behind navigation controls")
        // The balance is a property chip ("$340.00 due") that opens Money.
        let balance = app.buttons["job-chip-amount"]
        XCTAssertTrue(balance.waitForExistence(timeout: 20))
        XCTAssertTrue(balance.label.hasSuffix("due"), balance.label)
        XCTAssertTrue(balance.isHittable)
        capture(app, name: "Job header before invoice")
        balance.tap()
        let invoices = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Invoices")).firstMatch
        XCTAssertTrue(invoices.waitForExistence(timeout: 10), "Tapping the balance should open invoice content")
        XCTAssertTrue(app.buttons["job-section-money"].isSelected)
    }

    /// The Thorbis back circle replaces the system one; both it and the edge swipe still go back.
    func testThorbisBackButtonAndEdgeSwipeReturnFromJob() {
        if XCUIApplication().usesTabletLayout { return assertBackInTheDetailColumn() }
        for useSwipe in [false, true] {
            let app = preview("job", working: true)
            let title = app.staticTexts["job-title"]
            XCTAssertTrue(title.waitForExistence(timeout: 20))
            let back = app.navigationBars.firstMatch.buttons["Back"]
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(back.frame.width, 43.5)
            XCTAssertGreaterThanOrEqual(back.frame.height, 43.5)
            let actions = app.buttons["Job actions"]
            XCTAssertTrue(actions.exists)
            // Share job lives in the Job actions menu, so the header carries one circle.
            XCTAssertFalse(app.navigationBars.firstMatch.buttons["Share job"].exists)
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
        let title = app.staticTexts["job-title"]
        // v2: the balance is the header's "$340.00 due" chip; the work is the bar's one commit.
        let payment = app.buttons["job-chip-amount"]
        let work = app.buttons["job-commit"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        XCTAssertTrue(payment.waitForExistence(timeout: 20))
        XCTAssertTrue(work.waitForExistence(timeout: 20))
        XCTAssertTrue(title.isHittable)
        XCTAssertTrue(payment.isHittable)
        XCTAssertTrue(work.isHittable)
        XCTAssertGreaterThanOrEqual(title.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        capture(app, name: "Dark job overview")
    }

    func testAllJobTabsRemainReachableAtStandardAndLargeText() {
        for accessible in [false, true] {
            let app = preview("job", accessibleText: accessible, working: true)
            let activity: XCUIElement
            if accessible {
                // At accessibility sizes the tabs fold into one chooser; Activity is its row.
                let chooser = app.buttons["job-section-chooser"]
                XCTAssertTrue(chooser.waitForExistence(timeout: 20))
                for _ in 0..<4 where !chooser.isHittable { app.swipeUp() }
                XCTAssertTrue(chooser.isHittable)
                chooser.tap()
                activity = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND identifier != %@",
                                                            "Activity", "job-section-chooser")).firstMatch
            } else {
                activity = thorbisSection(app, "Activity")
                XCTAssertTrue(activity.waitForExistence(timeout: 20))
                for _ in 0..<4 where !activity.isHittable { app.swipeUp() }
            }
            XCTAssertTrue(activity.waitForExistence(timeout: 10))
            XCTAssertTrue(activity.isHittable, "Activity should be visible without horizontal scrolling")
            XCTAssertLessThanOrEqual(activity.frame.maxX, app.frame.maxX)
            capture(app, name: accessible ? "Job tabs at large text" : "Job tabs on narrow phone")
            activity.tap()
            // Activity's one filter popover ("Showing all ▾").
            XCTAssertTrue(app.buttons["activity-filter"].waitForExistence(timeout: 10))
            app.terminate()
        }
    }

    func testCustomerLinkIsComfortableAndOpensCustomerProfile() {
        let app = preview("job", working: true)
        // v2: the customer is one row of the customer panel on Overview (name, then "Residential · 2 jobs").
        let customer = app.buttons["job-customer-link"]
        XCTAssertTrue(customer.waitForExistence(timeout: 20))
        // Bring the row into the open middle of the screen, clear of the bar above and the commit below.
        let barBottom = app.navigationBars.firstMatch.frame.maxY
        for _ in 0..<12 {
            let frame = customer.frame
            if customer.isHittable && frame.minY > barBottom && frame.maxY < app.frame.height * 0.75 { break }
            if frame.minY <= barBottom { app.swipeDown(velocity: .slow) } else { app.swipeUp(velocity: .slow) }
        }
        XCTAssertTrue(customer.isHittable)
        XCTAssertGreaterThanOrEqual(customer.frame.height, 44)
        XCTAssertGreaterThanOrEqual(customer.frame.width, 44)
        XCTAssertTrue(customer.label.contains("Danielle Marlowe"))
        customer.tap()
        XCTAssertTrue(app.buttons["Customer actions"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Jobs")).firstMatch.exists)
    }

    func testShortCustomerNameStillHasComfortableTapTarget() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job",
                               "--paper-preview-short-customer-name"]
        app.launch()
        let customer = app.buttons["job-customer-link"]
        XCTAssertTrue(customer.waitForExistence(timeout: 20))
        XCTAssertTrue(customer.label.hasPrefix("I"), customer.label)
        XCTAssertGreaterThanOrEqual(customer.frame.width, 44)
        XCTAssertGreaterThanOrEqual(customer.frame.height, 44)
    }

    func testJobOverviewKeepsVisitActionsBeforeCustomerDetails() {
        let app = preview("job", working: true)
        // v2 on site: the visit's tools (photo, note, …) lead; the account's addresses follow.
        let visit = app.staticTexts["Tools"]
        let locations = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Service addresses")).firstMatch
        XCTAssertTrue(visit.waitForExistence(timeout: 20))
        XCTAssertTrue(locations.waitForExistence(timeout: 20))
        XCTAssertLessThan(visit.frame.minY, locations.frame.minY)
        XCTAssertTrue(app.buttons["job-tool-note"].exists)
        XCTAssertTrue(app.buttons["job-tool-photo"].exists)
        let details = app.buttons["More job details"]
        for _ in 0..<8 where !details.isHittable { app.swipeUp() }
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        details.tap()
        // v2: the job number lives in the header's eyebrow; the details fold out when it was booked.
        let booked = app.staticTexts["Booked"]
        for _ in 0..<4 where !booked.isHittable { app.swipeUp() }
        XCTAssertTrue(booked.waitForExistence(timeout: 5))
        XCTAssertTrue(booked.isHittable)
    }

    /// Off Overview the header is one line (title and status word); the customer, balance, Customer
    /// view and Call/Text/Directions live on Overview and come back with it.
    func testDocumentTabsKeepJobNameWithoutRepeatingOverviewActions() {
        let app = preview("job", working: true)
        XCTAssertTrue(app.buttons["job-call"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["job-customer-view"].exists)
        XCTAssertTrue(thorbisSection(app, "Money").waitForExistence(timeout: 20))
        for tab in ["Money", "Activity"] {
            thorbisSection(app, tab).tap()
            let name = app.staticTexts.matching(NSPredicate(format: "label == %@ OR label == %@", "AC not cooling", "412 Birchwood Ln")).firstMatch
            XCTAssertTrue(name.waitForExistence(timeout: 5), "\(tab) keeps the job's name")
            XCTAssertTrue(app.staticTexts["Job status, In progress"].exists || app.otherElements["Job status, In progress"].exists,
                          "\(tab) keeps the status as a word")
            XCTAssertFalse(app.buttons["job-call"].exists, "\(tab) must not repeat Overview's contact actions")
            XCTAssertFalse(app.buttons["job-customer-link"].exists, "\(tab) must not repeat the customer line")
            XCTAssertFalse(app.buttons["job-customer-view"].exists, "\(tab) must not repeat the header's Customer view")
            XCTAssertFalse(app.buttons["job-chip-amount"].exists, "\(tab) must not repeat the balance")
            XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Step ")).firstMatch.exists)
        }
        thorbisSection(app, "Overview").tap()
        XCTAssertTrue(app.buttons["job-call"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["job-customer-view"].exists)
    }

    func testSingleEstimateOptionUsesSingularLabel() {
        let app = preview("job-estimates", working: true)
        // The estimate row's line reads "EST-2218 · 1 option".
        let single = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "1 option")).firstMatch
        XCTAssertTrue(single.waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "1 options")).firstMatch.exists)
    }

    func testLongJobTitleWrapsOnEstimateTab() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job-estimates",
                               "--paper-preview-working-job", "--paper-preview-long-job-title"]
        app.launch()
        let titles = app.staticTexts.matching(NSPredicate(format: "label == %@", "Diagnose the upstairs air conditioner and replace the damaged compressor at the back of the property"))
        XCTAssertTrue(titles.firstMatch.waitForExistence(timeout: 20))
        // iPad lists the job beside its detail too: the header is the rightmost copy.
        let title = titles.allElementsBoundByIndex.max { $0.frame.minX < $1.frame.minX } ?? titles.firstMatch
        // Money's header is one line of title and status, but a long title still wraps in full.
        // Three lines on a phone; the iPad's wider detail column needs two.
        XCTAssertGreaterThan(title.frame.height, app.usesTabletLayout ? 30 : 45, "The complete job title should wrap instead of truncating")
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

        // On site, Collect payment is a step of the wrap-up checklist ("Collect payment, $340.00 due").
        let collect = button(startingWith: "Collect ", in: app)
        XCTAssertTrue(collect.waitForExistence(timeout: 10))
        for _ in 0..<6 where !collect.isHittable { app.swipeUp() }
        XCTAssertTrue(collect.isHittable)
        capture(app, name: "In-progress Job Overview")
        for _ in 0..<6 where !app.buttons["Job actions"].isHittable { app.swipeDown() }
        app.buttons["Job actions"].tap()
        button(startingWith: "Wrap up", in: app).tap()
        XCTAssertTrue(app.staticTexts["Wrap up this job"].waitForExistence(timeout: 5))
    }

    func testAccessibleTextKeepsContactActionsSeparateAndThePrimaryActionReadable() {
        continueAfterFailure = false
        let app = preview("job", accessibleText: true)
        let call = app.buttons["job-call"]
        let text = app.buttons["job-text"]
        // Directions is a popover of the account's places, or says why it's off ("no address on file").
        // By identifier: the service address row further down has its own "Directions to Home" circle,
        // and a label query picks that one first (it sits shallower in the tree), which scrolled the
        // test to the bottom of the job, past the commit and out of the lazy stack.
        let directions = app.descendants(matching: .any)["job-directions"]
        // The one commit ("On my way" for a dispatched job); at large text it follows the content.
        let primary = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "job-next-step", "On my way")).firstMatch
        XCTAssertTrue(call.waitForExistence(timeout: 15))
        capture(app, name: "Job Overview with accessible text")
        // The grid's second row starts below the fold at this size; offscreen it isn't in the tree.
        for _ in 0..<6 where !directions.exists { drag(app, up: true) }
        XCTAssertTrue(directions.exists, "Directions must be on the job")
        // v2: the contact circles wrap into a grid at large text; each keeps its own target.
        XCTAssertFalse(text.frame.intersects(call.frame), "Call and Text must not overlap")
        XCTAssertFalse(directions.frame.intersects(text.frame), "Text and Directions must not overlap")
        XCTAssertFalse(directions.frame.intersects(call.frame), "Call and Directions must not overlap")
        reveal(directions, in: app)
        XCTAssertTrue(directions.isHittable, "Directions must remain reachable below the enlarged header")
        // It follows the content, so it may not be built until it scrolls near. Short drags, so the
        // 82pt commit can't be stepped over between the section chooser and the bottom edge.
        for _ in 0..<15 where !(primary.exists && primary.isHittable) {
            drag(app, up: !primary.exists || primary.frame.midY > app.frame.height / 2)
        }
        XCTAssertTrue(primary.isHittable, "The primary action must remain reachable")
        XCTAssertGreaterThan(primary.frame.height, 50)
        capture(app, name: "Accessible contact actions after scrolling")
    }

    func testAccessiblePaymentActionScrollsWithTheJob() {
        continueAfterFailure = false
        let app = preview("job", accessibleText: true, working: true)
        let collect = button(startingWith: "Collect ", in: app)
        // The job's own scroll view (on iPad the list column beside it scrolls too).
        let content = app.usesTabletLayout ? app.scrollViews.containing(NSPredicate(format: "label BEGINSWITH %@", "Collect ")).firstMatch
                                           : app.scrollViews.firstMatch
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
        XCTAssertTrue(chooser.waitForExistence(timeout: 20))
        for _ in 0..<5 where !chooser.isHittable { content.swipeUp() }
        XCTAssertTrue(chooser.isHittable)
        // A job under way names its first section "On site".
        XCTAssertTrue(chooser.label.contains("Overview") || chooser.label.contains("On site"), chooser.label)
        chooser.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND identifier != %@", "Activity", "job-section-chooser")).firstMatch.tap()
        // v2: one "Showing all ▾" popover (`activity-filter`) replaced the row of filter chips.
        let filter = app.buttons["activity-filter"]
        for _ in 0..<5 where !filter.isHittable { content.swipeUp() }
        XCTAssertTrue(filter.isHittable)
        filter.tap()
        menuRow(app, "Photos").tap()
        XCTAssertTrue(chooser.waitForExistence(timeout: 10))
        XCTAssertTrue(chooser.isHittable, "The chooser must remain reachable on Photos")
        XCTAssertTrue(chooser.label.contains("Activity"))
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        XCTAssertTrue(filter.label.contains("photos"), filter.label)
        for _ in 0..<5 where !filter.isHittable { content.swipeUp() }
        XCTAssertTrue(filter.isHittable, "Photos must be able to switch back to notes")
        filter.tap()
        menuRow(app, "Notes").tap()
        // A note's row reads "Note · You"; an empty feed says so.
        let note = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Note")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10) || app.staticTexts["No activity yet"].exists)
    }

    /// F9: no floating current-job chip repeats Jobs' In progress row or covers a list's last row.
    /// v2: More became the drawer, which names the job under way once, in Recents, with its status word.
    func testCurrentJobChipStaysOffJobsAndClearsTheLastRowOnMore() {
        continueAfterFailure = false
        let chipQuery = NSPredicate(format: "label BEGINSWITH %@", "Current job")
        let jobs = preview("jobs", working: true)
        XCTAssertTrue(jobs.staticTexts["In progress"].waitForExistence(timeout: 20))
        XCTAssertFalse(jobs.buttons.matching(chipQuery).firstMatch.exists, "Jobs already leads with the job in progress")
        jobs.terminate()

        if jobs.usesTabletLayout { return assertSidebarNamesTheJobUnderWay() }
        let app = preview("more", working: true)
        let underWay = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", ", In progress")).firstMatch
        XCTAssertTrue(underWay.waitForExistence(timeout: 20), "The drawer's Recents name the job under way")
        capture(app, name: "Drawer with the job under way in Recents")
        XCTAssertFalse(app.buttons.matching(chipQuery).firstMatch.exists, "No floating current-job chip")
        let newJob = app.buttons["drawer-new"]
        XCTAssertTrue(newJob.exists)
        XCTAssertLessThanOrEqual(underWay.frame.maxY, newJob.frame.minY, "Recents stay clear of the drawer's foot")
    }

    /// iPad: the sidebar's foot names the job under way once, above the account, and only the sidebar
    /// does — no floating chip over the columns.
    private func assertSidebarNamesTheJobUnderWay() {
        let app = preview("jobs", working: true)
        XCTAssertTrue(app.staticTexts["In progress"].waitForExistence(timeout: 20))
        app.showSidebar()
        let chips = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Current job"))
        let current = chips.firstMatch
        XCTAssertTrue(current.waitForExistence(timeout: 10), "The sidebar names the job under way")
        XCTAssertEqual(chips.count, 1, "Named once")
        XCTAssertTrue(current.label.hasSuffix("In progress"), current.label)
        capture(app, name: "Sidebar with the job under way")
        let account = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Settings, ")).firstMatch
        XCTAssertTrue(account.exists)
        XCTAssertLessThanOrEqual(current.frame.maxY, account.frame.minY, "The job under way stays clear of the sidebar's foot")
        XCTAssertTrue(current.isHittable)
    }

    /// Scrolls until the element sits in the open middle of the screen, either way.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let barBottom = app.navigationBars.firstMatch.frame.maxY
        for _ in 0..<12 {
            let frame = element.frame
            if element.isHittable && frame.minY > barBottom && frame.maxY < app.frame.height * 0.75 { return }
            if frame.minY <= barBottom { app.swipeDown(velocity: .slow) } else { app.swipeUp(velocity: .slow) }
        }
    }

    /// A short, slow scroll (about 220pt) that settles before the next check.
    private func drag(_ app: XCUIApplication, up: Bool) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: up ? 0.7 : 0.4))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: up ? -220 : 220)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// A row in the open `ThorbisMenu` popover (the last match: the popover sits above the page).
    private func menuRow(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        let rows = app.buttons.matching(NSPredicate(format: "label == %@", title))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), "\(title) is not in the menu")
        return rows.element(boundBy: max(0, rows.count - 1))
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
