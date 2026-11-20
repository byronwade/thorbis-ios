import XCTest

@MainActor
final class JobOverviewUITests: XCTestCase {
    /// Waits until an Activity filter chip (`activity-filter-<name>`) reads as the chosen one.
    private func waitForChosen(_ chip: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: chip)],
                       timeout: timeout) == .completed
    }

    /// Paper 21 and 21A: three sections (Overview, Money, Activity); photos are Activity's Photos
    /// chip, one tap from Activity, and the other sections stay one tap away from the photos.
    func testPhotosAreOneChipFromActivityAndTheSectionsStayReachable() {
        continueAfterFailure = false
        let app = preview("job", working: true)
        let money = app.buttons["job-section-money"]
        XCTAssertTrue(money.waitForExistence(timeout: 15)); money.tap()
        XCTAssertFalse(app.buttons["job-section-photos"].exists, "Paper's job has three sections")
        for section in ["overview", "money", "activity"] {
            let button = app.buttons["job-section-\(section)"]
            XCTAssertGreaterThanOrEqual(button.frame.width, 43.5, section)
            XCTAssertGreaterThanOrEqual(button.frame.height, 43.5, section)
        }
        let activity = app.buttons["job-section-activity"]
        XCTAssertTrue(activity.isHittable); activity.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: activity)], timeout: 5), .completed)
        let all = app.buttons["activity-filter-all"]
        let photos = app.buttons["activity-filter-photos"]
        XCTAssertTrue(photos.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForChosen(all), "Activity opens on All")
        XCTAssertGreaterThanOrEqual(photos.frame.height, 43.5)
        photos.tap()
        XCTAssertTrue(waitForChosen(photos))
        capture(app, name: "Job Activity photos")
        // Over the photos the chips and the sections stay in reach.
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        XCTAssertTrue(all.isHittable); all.tap()
        XCTAssertTrue(waitForChosen(all))
        photos.tap()
        XCTAssertTrue(waitForChosen(photos))
        XCTAssertTrue(money.isHittable); money.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: money)], timeout: 5), .completed)
    }

    func testPhotosChipIsReachableAtLargeText() {
        continueAfterFailure = false
        let app = preview("job", accessibleText: true, working: true)
        let chooser = app.buttons["job-section-chooser"]
        XCTAssertTrue(chooser.waitForExistence(timeout: 15)); chooser.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND identifier != %@", "Activity", "job-section-chooser")).firstMatch.tap()
        let photos = app.buttons["activity-filter-photos"]
        let content = app.scrollViews.firstMatch
        XCTAssertTrue(photos.waitForExistence(timeout: 10))
        for _ in 0..<8 where !photos.isHittable { content.swipeUp() }
        XCTAssertTrue(photos.isHittable); photos.tap()
        XCTAssertTrue(waitForChosen(photos, timeout: 10))
        XCTAssertTrue(chooser.waitForExistence(timeout: 10))
        XCTAssertTrue(chooser.label.contains("Activity"), chooser.label)
        capture(app, name: "Job Photos large text chooser")
    }

    /// Leaving the photos for another section and coming back opens Activity on the filter that
    /// was chosen before the photos, not on the photo grid.
    func testReturningFromPhotosKeepsThePreviousActivityFilter() {
        continueAfterFailure = false
        let app = preview("job", working: true)
        let activity = app.buttons["job-section-activity"]
        XCTAssertTrue(activity.waitForExistence(timeout: 15)); activity.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: activity)], timeout: 5), .completed)
        let notes = app.buttons["activity-filter-notes"]
        let photos = app.buttons["activity-filter-photos"]
        let content = app.scrollViews.firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 10))
        for _ in 0..<6 where !notes.isHittable { content.swipeUp() }
        XCTAssertTrue(notes.isHittable); notes.tap()
        XCTAssertTrue(waitForChosen(notes))
        photos.tap()
        XCTAssertTrue(waitForChosen(photos))
        let money = app.buttons["job-section-money"]
        XCTAssertTrue(money.isHittable); money.tap()
        XCTAssertTrue(activity.isHittable)
        activity.tap()
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForChosen(notes), "Activity reopens on the filter chosen before the photos")
    }

    func testLongInvoiceBalanceKeepsEveryJobSectionTappable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job", "--paper-preview-extreme-invoice"]
        app.launch()
        var previous: XCUIElement?
        for section in ["overview", "money", "activity"] {
            let button = app.buttons["job-section-\(section)"]
            XCTAssertTrue(button.waitForExistence(timeout: 15), section)
            for _ in 0..<5 where !button.isHittable { app.swipeUp() }
            XCTAssertTrue(button.isHittable, section)
            XCTAssertGreaterThanOrEqual(button.frame.width, 43.5, section)
            XCTAssertGreaterThanOrEqual(button.frame.height, 43.5, section)
            // #403: tabs keep whole words and flow onto a second line when four don't fit, so a tab may
            // sit beside the previous one or start the next line below it; either way they never overlap.
            if let previous {
                let before = previous.frame, here = button.frame
                let beside = before.maxX <= here.minX + 0.5
                let below = before.maxY <= here.minY + 0.5
                XCTAssertTrue(beside || below, "\(section) overlaps the previous section: \(before) vs \(here)")
            }
            previous = button
        }
        let money = app.buttons["job-section-money"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "due"), object: money)], timeout: 15), .completed,
                       "The full balance remains spoken")
        XCTAssertTrue(money.label.contains("9,999,999,620.00"), money.label)
    }
    /// iPad: the job is the detail column's first screen (picked from the list beside it, so nothing
    /// to go back to). A screen pushed from it — the customer — offers the same Back circle, which
    /// returns to the job, and a swipe in from the detail column's own leading edge (beside the
    /// list, far from the screen edge UIKit's swipe listens on) goes back too. At the screen's edge
    /// the swipe brings the sidebar in (DrawerGearMenuUITests).
    private func assertBackInTheDetailColumn() {
        for useSwipe in [false, true] {
            assertBackInTheDetailColumn(useSwipe: useSwipe)
        }
    }

    private func assertBackInTheDetailColumn(useSwipe: Bool) {
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
        if useSwipe {
            // The detail column's leading edge: its bar starts there, beside the list.
            let bars = app.navigationBars.allElementsBoundByIndex.filter { $0.frame.minX > app.frame.width * 0.3 }
            let edge = bars.first?.frame.minX ?? back.frame.minX - 16
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: edge + 4, dy: app.frame.height * 0.55))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 400, dy: 0)))
        } else {
            back.tap()
        }
        let how = useSwipe ? "The detail column's edge swipe" : "Back"
        XCTAssertTrue(app.buttons["Customer actions"].waitForNonExistence(timeout: 5), "\(how) should pop the customer")
        XCTAssertTrue(actions.waitForExistence(timeout: 5), "\(how) returns to the job")
        if useSwipe {
            // The pop reached the layout's path: back on the column's first screen, the screen-edge
            // swipe brings the sidebar in again.
            app.swipeInFromLeftEdge()
            XCTAssertTrue(app.buttons["sidebar-search"].waitForExistence(timeout: 5), "Back on the first screen, the edge swipe shows the sidebar")
        }
        app.terminate()
    }

    func testJobHeaderKeepsTitleClearOfNavigationAndBalanceOpensInvoice() {
        let app = preview("job", working: true)
        // Paper F4: on the visit the job's title (`job-title`) is the bar's centred title, between
        // Back and the bar's circles.
        let title = app.staticTexts["job-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        let bar = app.navigationBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        assertTitleClearOfBarControls(title, in: app)
        // Paper 21: Overview carries no balance; Money is one tap away on the sections.
        capture(app, name: "Job header before invoice")
        thorbisTapStableButton(app, "job-section-money")
        let invoices = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Invoices")).firstMatch
        XCTAssertTrue(invoices.waitForExistence(timeout: 10), "Tapping the balance should open invoice content")
        XCTAssertTrue(app.buttons["job-section-money"].isSelected)
    }

    /// Switching section from the pinned tabs at the bottom of the job opens the new section at its
    /// top and the app keeps answering. (Due on site, far down the page, used to hang the app: see
    /// testJobHeaderKeepsTitleClearOfNavigationAndBalanceOpensInvoice.)
    func testSwitchingSectionWhileScrolledKeepsTheAppResponsive() {
        let app = preview("job", working: true)
        XCTAssertTrue(app.staticTexts["job-title"].waitForExistence(timeout: 20))
        for _ in 0..<8 { app.swipeUp(velocity: .slow) }
        let money = app.buttons["job-section-money"]
        XCTAssertTrue(money.waitForExistence(timeout: 5))
        money.tap()
        let invoices = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Invoices")).firstMatch
        XCTAssertTrue(invoices.waitForExistence(timeout: 10), "Money shows after switching while scrolled")
        app.buttons["job-section-overview"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["job-title"].waitForExistence(timeout: 10), "The app still answers")
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
            // Paper 21: the bar is Back, Share and More.
            XCTAssertTrue(app.navigationBars.firstMatch.buttons["Share job"].exists)
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
        // Paper 21: the work is the bar's one commit; the balance lives on Money.
        let work = app.buttons["job-commit"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        XCTAssertTrue(work.waitForExistence(timeout: 20))
        XCTAssertTrue(title.isHittable)
        assertTitleClearOfBarControls(title, in: app)
        XCTAssertTrue(work.isHittable)
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
            // Paper 21B: Activity's filter chips, "All" first.
            XCTAssertTrue(app.buttons["activity-filter-all"].waitForExistence(timeout: 10))
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
        // Paper F4: out on the visit, field mode leads with the capture tiles.
        let app = preview("job", working: true, field: true)
        XCTAssertTrue(app.buttons["job-tool-note"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["job-tool-photo"].exists)
        // Paper 21O: the account's addresses and the record's own dates are More › At this address.
        app.buttons["Job actions"].tap()
        let lead = button(startingWith: "Full job details", in: app)
        XCTAssertTrue(lead.waitForExistence(timeout: 5)); lead.tap()
        XCTAssertTrue(app.buttons["job-section-money"].waitForExistence(timeout: 10), "Full job details opens Job details")
        app.buttons["Job actions"].tap()
        let address = button(startingWith: "At this address", in: app)
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        revealMenuRow(address, in: app)
        address.tap()
        let locations = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Service addresses")).firstMatch
        XCTAssertTrue(locations.waitForExistence(timeout: 20))
        let details = app.buttons["More job details"]
        for _ in 0..<12 where !details.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(details.frame.height, 44, "The whole details row toggles")
        details.tap()
        // The job number lives in the header's eyebrow; the details fold out when it was booked.
        let booked = app.staticTexts["Booked"]
        XCTAssertTrue(booked.waitForExistence(timeout: 5))
        for _ in 0..<6 where !booked.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(booked.isHittable)
    }

    /// Scrolls until `element` is clear of the job's bottom bar. A row that has scrolled under the
    /// bar still reports `isHittable` (its hit point is on screen), so a tap on it lands on the bar's
    /// commit instead (iPad: the swipes can leave "More job details" right behind it). Paper F4: a
    /// job under way has no circles in its bar, so the bar is measured from its commit.
    private func revealAboveJobBar(_ element: XCUIElement, in app: XCUIApplication) {
        let commit = app.buttons["job-commit"]
        func barTop() -> CGFloat { commit.exists ? commit.frame.minY - 12 : app.frame.maxY }
        for _ in 0..<12 where !(element.isHittable && element.frame.maxY <= barTop()) {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertLessThanOrEqual(element.frame.maxY, barTop(), "\(element.label) should scroll clear of the job's bar")
    }

    /// Paper 23, 24 and 21B: Money and Activity keep the job's header (its name, the status chip
    /// and the other chips) over the sections. Overview's own cards (the customer, the balance,
    /// Customer view, the capture tiles) and the visit's steps stay on Overview and come back with
    /// it. (Paper F4: a job under way has no Call/Text/Directions circles; its Photo tile stands
    /// for Overview's own actions.)
    func testDocumentTabsKeepTheJobHeaderWithoutRepeatingOverviewCards() {
        let app = preview("job", working: true)
        // Paper 21: a job under way leads Overview with its field-mode card.
        XCTAssertTrue(app.buttons["job-field-mode-card"].waitForExistence(timeout: 20))
        XCTAssertTrue(thorbisSection(app, "Money").waitForExistence(timeout: 20))
        for tab in ["Money", "Activity"] {
            thorbisSection(app, tab).tap()
            let name = app.staticTexts.matching(NSPredicate(format: "label == %@ OR label == %@", "AC not cooling", "412 Birchwood Ln")).firstMatch
            XCTAssertTrue(name.waitForExistence(timeout: 5), "\(tab) keeps the job's name")
            // The header's status chip: a menu button when the status can move, a word otherwise.
            let status = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Job status,")).firstMatch
            XCTAssertTrue(status.waitForExistence(timeout: 5), "\(tab) keeps the header's status chip")
            XCTAssertFalse(app.buttons["job-field-mode-card"].exists, "\(tab) must not repeat Overview's field-mode card")
            XCTAssertFalse(app.buttons["job-customer-link"].exists, "\(tab) must not repeat the customer line")
            XCTAssertFalse(app.otherElements["job-field-steps"].exists, "\(tab) must not show field mode's steps")
        }
        thorbisSection(app, "Overview").tap()
        XCTAssertTrue(app.buttons["job-field-mode-card"].waitForExistence(timeout: 5))
        // Resume opens field mode: the steps and the capture tiles, no sections.
        app.buttons["job-field-mode-card"].tap()
        XCTAssertTrue(app.buttons["job-tool-photo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["job-section-money"].exists, "Field mode has no sections")
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
        // A job not yet under way: its 34 Bold title is in the page's header on every section. (On
        // the visit, Paper F4 moves the title into the bar, one line.)
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job-estimates",
                               "--paper-preview-long-job-title"]
        app.launch()
        let titles = app.staticTexts.matching(NSPredicate(format: "label == %@", "Diagnose the upstairs air conditioner and replace the damaged compressor at the back of the property"))
        XCTAssertTrue(titles.firstMatch.waitForExistence(timeout: 20))
        // On iPad the list beside the detail carries the title too: the header is the copy that
        // wraps the most.
        let title = titles.allElementsBoundByIndex.max { $0.frame.height < $1.frame.height } ?? titles.firstMatch
        // Money's header is one line of title and status, but a long title still wraps in full.
        // Three lines on a phone; the iPad's wider detail column needs two.
        XCTAssertGreaterThan(title.frame.height, app.usesTabletLayout ? 30 : 45, "The complete job title should wrap instead of truncating")
        XCTAssertTrue(app.buttons["Job actions"].exists)
    }

    /// Paper 21K trims More to its eight rows; every action it no longer carries stays one tap from
    /// its door on Job details: the clock chip (Reschedule), the person chip (Reassign technician),
    /// the Share circle (Add to Calendar, Customer view, Copy job ID). More keeps Wrap up's closeout
    /// checklist while the bar is not carrying it.
    func testEverySecondaryActionKeepsADoorAndSchedulingOpens() {
        continueAfterFailure = false
        let app = preview("job", working: true)
        // The financial step appears only after the job's paper finishes loading.
        XCTAssertTrue(thorbisJobBalanceLoaded(app, "$340.00").waitForExistence(timeout: 20))
        let more = app.buttons["Job actions"]
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        more.tap()
        for title in ["Time and profit", "At this address", "Wrap up,"] {
            let action = button(startingWith: title, in: app)
            XCTAssertTrue(action.waitForExistence(timeout: 5), "Missing More row: \(title)")
            revealMenuRow(action, in: app)
            XCTAssertTrue(action.isHittable, "More row is unreachable: \(title)")
        }
        for title in ["Reschedule", "Add to Calendar", "Customer view", "Copy job ID"] {
            XCTAssertFalse(button(startingWith: title, in: app).exists, "\(title) moved out of More (Paper 21K)")
        }
        capture(app, name: "Job More menu")
        closeSheet(app)

        // The Share circle's sheet.
        let share = app.buttons["job-share"]
        XCTAssertTrue(share.waitForExistence(timeout: 5)); share.tap()
        XCTAssertTrue(app.buttons["Copy job ID"].waitForExistence(timeout: 5), "The Share sheet opens")
        for title in ["Share job", "Customer view", "Add to Calendar", "Copy job ID"] {
            // The circle itself is also "Share job": the sheet's row is the last match.
            let action = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND identifier != %@", title, "job-share")).firstMatch
            XCTAssertTrue(action.waitForExistence(timeout: 5), "Missing Share row: \(title)")
            revealMenuRow(action, in: app)
            XCTAssertTrue(action.isHittable, "Share row is unreachable: \(title)")
        }
        capture(app, name: "Job Share sheet")
        closeSheet(app)

        // The person chip assigns.
        let assignee = app.buttons["job-assignee"]
        XCTAssertTrue(assignee.waitForExistence(timeout: 5))
        XCTAssertTrue(assignee.label.hasPrefix("Reassign technician"), assignee.label)

        // The clock chip reschedules.
        let when = app.buttons["job-when"]
        XCTAssertTrue(when.waitForExistence(timeout: 5)); reveal(when, in: app)
        when.tap()
        let reschedule = app.buttons["Reschedule"]
        XCTAssertTrue(reschedule.waitForExistence(timeout: 5))
        reschedule.tap()
        XCTAssertTrue(app.buttons["Save schedule"].waitForExistence(timeout: 5))
        // Paper 25: the schedule sheet closes from its Close circle.
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(more.waitForExistence(timeout: 5))
    }

    func testInProgressJobKeepsItsPaymentStepAndWrapUpChecklist() {
        continueAfterFailure = false
        let app = preview("job", working: true)

        // Paper 24: on site, the payment step is Collect payment in the invoice's card on Money.
        let collect = collectPill(in: app)
        XCTAssertTrue(collect.isHittable)
        capture(app, name: "In-progress Job Money")
        for _ in 0..<6 where !app.buttons["Job actions"].isHittable { app.swipeDown() }
        app.buttons["Job actions"].tap()
        // The menu's row ("Wrap up, Closeout checklist"), not the bar's commit ("Wrap up · 3 left").
        let wrap = button(startingWith: "Wrap up,", in: app)
        XCTAssertTrue(wrap.waitForExistence(timeout: 5))
        revealMenuRow(wrap, in: app)
        XCTAssertTrue(wrap.isHittable, "Wrap up must be in reach in the menu sheet")
        wrap.tap()
        // Paper F5: a job under way wraps up under the visit's steps, its checklist titled "Finish checklist".
        XCTAssertTrue(app.staticTexts["Finish checklist"].waitForExistence(timeout: 5))
    }

    func testInProgressJobPaymentStepOpensItsInvoice() {
        continueAfterFailure = false
        let app = preview("job", working: true)
        let collect = collectPill(in: app)
        XCTAssertTrue(collect.isHittable)
        collect.tap()
        let invoice = app.descendants(matching: .any)["collect-payment-invoice"]
        XCTAssertTrue(invoice.waitForExistence(timeout: 10))
        XCTAssertTrue(invoice.label.contains("INV-2209"), invoice.label)
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
        // Paper 24: Collect payment is in the invoice's card on Money (the sections are one chooser at this size).
        let collect = collectPill(in: app)
        // The job's own scroll view (on iPad the list column beside it scrolls too).
        let content = app.usesTabletLayout ? app.scrollViews.containing(NSPredicate(format: "label BEGINSWITH %@", "Collect ")).firstMatch
                                           : app.scrollViews.firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 20))
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
        // Paper 21B: Activity's filters are a row of chips (`activity-filter-<name>`).
        let photos = app.buttons["activity-filter-photos"]
        let notes = app.buttons["activity-filter-notes"]
        XCTAssertTrue(photos.waitForExistence(timeout: 10))
        for _ in 0..<5 where !photos.isHittable { content.swipeUp() }
        XCTAssertTrue(photos.isHittable)
        photos.tap()
        XCTAssertTrue(waitForChosen(photos, timeout: 10))
        XCTAssertTrue(chooser.waitForExistence(timeout: 10))
        XCTAssertTrue(chooser.isHittable, "The chooser must remain reachable on Photos")
        XCTAssertTrue(chooser.label.contains("Activity"), chooser.label)
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        for _ in 0..<5 where !notes.isHittable { content.swipeUp() }
        XCTAssertTrue(notes.isHittable, "Photos must be able to switch back to notes")
        notes.tap()
        // Leaving Photos puts the job's header back above the feed, and the feed builds its rows as
        // they scroll in: bring the chips back before reading which one is chosen.
        for _ in 0..<6 where !notes.exists { content.swipeUp() }
        XCTAssertTrue(waitForChosen(notes))
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
        // Paper v2: the drawer (29N) lists places only, no recent records; still no floating chip.
        let app = preview("more", working: true)
        XCTAssertTrue(app.scrollViews["drawer-rows"].waitForExistence(timeout: 20))
        capture(app, name: "Drawer, Paper v2")
        XCTAssertFalse(app.buttons.matching(chipQuery).firstMatch.exists, "No floating current-job chip")
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

    /// Brings a row of the open menu sheet into reach. Short, slow drags inside the sheet, up for a
    /// row below the fold and down for one scrolled past the top, so no row is stepped over and a
    /// long swipe never flings the sheet away. The first drag up also grows a half-height sheet.
    private func revealMenuRow(_ row: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<16 where !row.isHittable {
            drag(app, up: row.frame.midY > app.frame.height * 0.3)
        }
    }

    /// On the visit the job's title is the bar's centred title (Paper F2 to F4): inside the bar,
    /// never under Back or the bar's circles.
    private func assertTitleClearOfBarControls(_ title: XCUIElement, in app: XCUIApplication) {
        let actions = app.buttons["Job actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        XCTAssertFalse(title.frame.intersects(actions.frame), "The job title must not sit behind navigation controls")
        let back = app.navigationBars.buttons["Back"].firstMatch
        if back.exists {
            XCTAssertFalse(title.frame.intersects(back.frame), "The job title must not sit behind Back")
        }
    }

    /// A row in the open `ThorbisMenu` popover (the last match: the popover sits above the page).
    private func menuRow(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        let rows = app.buttons.matching(NSPredicate(format: "label == %@", title))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), "\(title) is not in the menu")
        return rows.element(boundBy: max(0, rows.count - 1))
    }

    /// The Money cluster sits below what to know at the address; scroll the sheet until it is reachable.
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable || element.frame.maxY > app.frame.height - 140 {
            app.swipeUp(velocity: .slow)
        }
    }

    /// `field` opens the job in field mode (Paper F2 to F8); otherwise the preview opens Job details.
    private func preview(_ screen: String, accessibleText: Bool = false, working: Bool = false, field: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", screen]
        if working { app.launchArguments += ["--paper-preview-working-job"] }
        if field { app.launchArguments += ["--paper-preview-field-mode"] }
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

    /// Paper 24: the job's payment step is "Collect payment" in the invoice's card on Money. Opens
    /// Money (from the chooser at accessibility sizes) and brings the pill clear of the job's bar.
    private func collectPill(in app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(app.staticTexts["job-title"].waitForExistence(timeout: 20))
        let chooser = app.buttons["job-section-chooser"]
        if chooser.waitForExistence(timeout: 2) {
            for _ in 0..<5 where !chooser.isHittable { app.swipeUp(velocity: .slow) }
            chooser.tap()
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND identifier != %@", "Money", "job-section-chooser")).firstMatch.tap()
        } else {
            thorbisTapStableButton(app, "job-section-money")
        }
        let collect = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "job-invoice-collect-")).firstMatch
        for _ in 0..<8 where !collect.exists { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(collect.waitForExistence(timeout: 15), "The invoice's card must offer Collect payment")
        app.scrollClearOfFoot(collect)
        return collect
    }

    /// Closes an open menu sheet (its Close pill, else a swipe down) and waits for the page to answer.
    private func closeSheet(_ app: XCUIApplication) {
        let close = app.buttons.matching(NSPredicate(format: "label == %@", "Close")).firstMatch
        if close.exists && close.isHittable { close.tap() } else { app.swipeDown(velocity: .fast) }
        let back = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.buttons["Job actions"])
        XCTAssertEqual(XCTWaiter.wait(for: [back], timeout: 10), .completed, "The sheet closes")
    }

    private func button(startingWith title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }
}
