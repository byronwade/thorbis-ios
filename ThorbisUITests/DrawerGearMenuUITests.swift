import XCTest

/// The drawer's gear and its menu (#227: the menu grows up from the gear so every row stays on
/// screen), and the closed drawer staying out of the accessibility tree.
@MainActor
final class DrawerGearMenuUITests: XCTestCase {
    func testCurrentJobCanBeAddedAndRemovedFromFavorites() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let id = "00000000-0000-4000-8000-000000002214"
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-role", "office"]
        app.launch()
        _ = id
        // Paper 21: the job's bar is Back, Share and More; the favorite is a row of the Share circle's sheet, which
        // closes on each choice and reads the new state when opened again.
        XCTAssertTrue(app.buttons["Job actions"].waitForExistence(timeout: 30))
        var row = thorbisJobFavoriteRow(app)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        // Each choice closes the sheet; the closing sheet's row is still in the tree for a moment,
        // and reading it would report the old state. Wait it out, then open the sheet again.
        func choose(_ current: XCUIElement) -> XCUIElement {
            current.tap()
            XCTAssertTrue(current.waitForNonExistence(timeout: 5), "The Share sheet closes on each choice")
            return thorbisJobFavoriteRow(app)
        }
        if row.label == "Remove from favorites" { row = choose(row) }
        XCTAssertEqual(row.label, "Add to favorites")
        XCTAssertGreaterThanOrEqual(row.frame.height, 43.99)
        row = choose(row)
        XCTAssertEqual(row.label, "Remove from favorites")
        row = choose(row)
        XCTAssertEqual(row.label, "Add to favorites")
    }

    func testCurrentCustomerCanBeAddedAndRemovedFromFavorites() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let id = "00000000-0000-4000-8000-000000000412"
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer", "--paper-preview-role", "office"]
        app.launch()
        _ = id
        // Paper 48N: the customer's bar is back and ⋯ only; the favorite is a row of Customer actions.
        let actions = app.buttons["Customer actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 30))
        XCTAssertGreaterThanOrEqual(actions.frame.height, 43.99)
        let add = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Add to favorites")).firstMatch
        let remove = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Remove from favorites")).firstMatch
        actions.tap()
        if remove.waitForExistence(timeout: 3) { remove.tap(); actions.tap() }
        XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
        actions.tap()
        XCTAssertTrue(remove.waitForExistence(timeout: 5)); remove.tap()
        actions.tap()
        XCTAssertTrue(add.waitForExistence(timeout: 5))
    }

    func testTabletFavoriteJobCanBeOpenedAndRemoved() throws {
        guard XCUIApplication().usesTabletLayout else { throw XCTSkip("iPad sidebar only") }
        continueAfterFailure = false
        let app = XCUIApplication()
        let id = "00000000-0000-4000-8000-000000002214"
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-role", "office"]
        app.launch()
        XCTAssertTrue(app.buttons["Job actions"].waitForExistence(timeout: 30))
        let row = thorbisJobFavoriteRow(app)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        // Either choice closes More: add it, or leave it added.
        if row.label == "Add to favorites" { row.tap() } else { app.swipeDown(velocity: .fast) }
        app.showSidebar()
        let favorite = app.buttons["sidebar-favorite-record-\(id)"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 15)); favorite.tap()
        XCTAssertTrue(app.buttons["job-section-money"].waitForExistence(timeout: 15))
        app.showSidebar()
        XCTAssertTrue(favorite.waitForExistence(timeout: 15)); favorite.press(forDuration: 1)
        let remove = app.buttons["Remove from favorites"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5)); remove.tap()
        XCTAssertTrue(favorite.waitForNonExistence(timeout: 10))
    }

    // Paper v2 (Navigation 29N/57N/58N): the drawer lists no recent records, so the Recent →
    // Favorites path is gone from the drawer; favorites are still added from a record's own menu.

    func testTopNewMenuOpensPermittedCustomerCreate() throws {
        guard !XCUIApplication().usesTabletLayout else { throw XCTSkip("Phone drawer only") }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "jobs", "--paper-preview-role", "office"]
        app.launch(); app.openDrawer()
        let new = app.buttons["drawer-new-menu"]
        XCTAssertGreaterThanOrEqual(new.frame.height, 44)
        new.tap()
        let customer = app.buttons.matching(NSPredicate(format: "label == %@", "New customer")).firstMatch
        XCTAssertTrue(customer.waitForExistence(timeout: 5)); customer.tap()
        XCTAssertTrue(app.staticTexts["New customer"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.scrollViews["drawer-rows"].exists, "The drawer closes before the sheet opens")
    }

    /// Paper 65 and 29A: the gear opens Settings directly; the workspace name opens Switch
    /// workspace (the businesses and Add a business), with no Settings or Edit menu rows in it.
    func testGearOpensSettingsAndWorkspaceNameSwitchesWorkspace() throws {
        guard !XCUIApplication().usesTabletLayout else { throw XCTSkip("Phone drawer only") }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "jobs", "--paper-preview-role", "office",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); app.openDrawer()
        let workspace = app.buttons["drawer-workspace-menu"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(app.thorbisUsableFrame(of: workspace)?.height ?? 0, 44)
        app.thorbisTapCentre(workspace)
        let add = app.buttons.matching(NSPredicate(format: "label == %@", "Add a business")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5), "Switch workspace lists Add a business")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == %@", "Edit menu")).firstMatch.exists,
                       "The Edit menu sheet is gone; the menu is arranged in Settings")
        XCTAssertFalse(app.thorbisFrontButton(matching: NSPredicate(format: "label == %@ AND identifier != %@", "Settings", "drawer-settings")).exists,
                       "Settings is the gear's, not a row of the workspace menu")
        // Close the menu, then the gear opens Settings.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)).tap()
        let gear = app.drawerRow("settings")
        if !gear.waitForExistence(timeout: 3) { app.openDrawer() }
        XCTAssertGreaterThanOrEqual(app.thorbisUsableFrame(of: gear)?.height ?? 0, 44)
        app.thorbisTapCentre(gear)
        XCTAssertTrue(app.buttons["settings-account-data"].waitForExistence(timeout: 10), "The gear opens Settings directly")
        XCTAssertTrue(app.scrollViews["drawer-rows"].waitForNonExistence(timeout: 5),
                      "The drawer closes before Settings opens")
        // Menu editing lives in Settings › Menu and start screen.
        let menu = app.buttons["settings-menu"]
        for _ in 0..<5 where !(menu.exists && menu.isHittable) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(menu.isHittable)
    }

    func testOnlyPermittedWorkPlaceIsDirectlyReachable() throws {
        guard !XCUIApplication().usesTabletLayout else { throw XCTSkip("Phone drawer check") }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "schedule", "--paper-preview-role", "office",
                               "--paper-preview-sidebar-job-view-only", "--paper-preview-menu-suite", UUID().uuidString]
        app.launch(); app.openDrawer()
        let jobs = app.buttons["drawer-jobs"]
        XCTAssertTrue(jobs.waitForExistence(timeout: 15))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: jobs)], timeout: 15), .completed, "The Jobs row is reachable once the drawer has slid in")
        XCTAssertFalse(app.buttons["drawer-estimates"].exists)
        XCTAssertFalse(app.buttons["drawer-invoices"].exists)
        XCTAssertFalse(app.buttons["drawer-team"].exists)
        jobs.tap()
        XCTAssertTrue(app.staticTexts["Jobs"].waitForExistence(timeout: 10))
    }

    /// The menu is Paper's rows for the role (office, 57N): no Estimates, Invoices or Message drafts
    /// rows. Estimates and Invoices open from Money.
    func testMenuListsPapersRowsAndMoneyOpensEstimates() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "jobs", "--paper-preview-role", "office",
                               "--paper-preview-menu-suite", UUID().uuidString]
        app.launch()
        if app.usesTabletLayout { app.showSidebar() } else { app.openDrawer() }
        let prefix = app.usesTabletLayout ? "sidebar" : "drawer"
        if !app.usesTabletLayout {
            XCTAssertTrue(app.buttons["drawer-workspace-menu"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.buttons["drawer-new-menu"].exists, "Paper's + circle opens New")
            XCTAssertTrue(app.buttons["drawer-settings"].exists)
        }
        let schedule = app.buttons["\(prefix)-schedule"]
        let jobs = app.buttons["\(prefix)-jobs"]
        let money = app.buttons["\(prefix)-money"]
        XCTAssertTrue(jobs.waitForExistence(timeout: 15))
        XCTAssertTrue(money.exists)
        XCTAssertLessThan(schedule.frame.minY, jobs.frame.minY)
        XCTAssertLessThan(jobs.frame.minY, money.frame.minY)
        for gone in ["estimates", "invoices", "drafts", "billing", "attention", "scorecard", "local-team"] {
            XCTAssertFalse(app.buttons["\(prefix)-\(gone)"].exists, "\(gone) is not one of Paper's office rows")
        }
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Paper v2 drawer (office)"
        shot.lifetime = .keepAlways
        add(shot)
        money.tap()
        let estimates = app.buttons["door-estimates"]
        XCTAssertTrue(estimates.waitForExistence(timeout: 15), "Money links the Estimates list")
        XCTAssertTrue(app.buttons["door-invoices"].exists, "Money links the Invoices list")
        for _ in 0..<5 where !estimates.isHittable { app.swipeUp(velocity: .slow) }
        estimates.tap()
        XCTAssertTrue(app.staticTexts["Estimates"].waitForExistence(timeout: 10))
    }

    /// The seeded saved work belongs to this test: reset it so its banner never reaches later tests.
    private var cleanupArguments: [String]?

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        if let base = cleanupArguments {
            let app = XCUIApplication(); app.terminate()
            app.launchArguments = base + ["--paper-preview-reset-saved-work"]
            app.launch(); app.terminate()
        }
        super.tearDown()
    }

    /// Closed, the drawer sits built under the card: none of its rows may be reachable (VoiceOver
    /// would land on them behind the place showing, and "New job" would be announced twice).
    func testClosedDrawerIsOutOfTheAccessibilityTree() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "jobs"]
        app.launch()
        if app.usesTabletLayout { return assertClosedSidebarIsOutOfTheTree(app) }
        XCTAssertTrue(app.drawerMenu.waitForExistence(timeout: 30))
        XCTAssertFalse(app.drawerRow("new-menu").exists, "The closed drawer's New job must not be in the tree")
        XCTAssertFalse(app.drawerRow("settings").exists, "The closed drawer's gear must not be in the tree")
        XCTAssertFalse(app.drawerRow("search").exists)
        XCTAssertFalse(app.scrollViews["drawer-rows"].exists, "The closed drawer's (empty) scroll view must not be in the tree")
        app.openDrawer()
        XCTAssertTrue(app.drawerRow("new-menu").waitForExistence(timeout: 5))
        XCTAssertTrue(app.drawerRow("settings").exists)
        XCTAssertTrue(app.scrollViews["drawer-rows"].exists)
        // Closing takes everything out again once the drawer has slid shut.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        // The UIKit-hosted controls leave as the close starts (VoiceOver returns to the place then);
        // only the rows stay through the slide.
        XCTAssertFalse(app.drawerRow("new-menu").exists, "New job must leave the tree as the drawer starts closing")
        XCTAssertFalse(app.drawerRow("settings").exists, "The gear must leave the tree as the drawer starts closing")
        XCTAssertTrue(app.scrollViews["drawer-rows"].waitForNonExistence(timeout: 5))
    }

    /// iPad portrait: the sidebar slides over the columns. Hidden, none of its rows are in the tree;
    /// shown, they are; a tap on the dimmed columns takes them out again.
    private func assertClosedSidebarIsOutOfTheTree(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["sidebar-show"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["sidebar-settings"].exists, "The hidden sidebar's Settings must not be in the tree")
        XCTAssertFalse(app.buttons["sidebar-search"].exists)
        app.showSidebar()
        XCTAssertTrue(app.buttons["sidebar-settings"].exists)
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["sidebar-settings"].waitForNonExistence(timeout: 5), "Closing takes the sidebar out of the tree")
        XCTAssertFalse(app.buttons["sidebar-search"].exists)
    }

    /// The edge swipe still opens the drawer although its contents are not built while closed. On
    /// iPad the same swipe brings the hidden sidebar in.
    func testEdgeSwipeOpensTheDrawer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "jobs"]
        app.launch()
        if app.usesTabletLayout {
            XCTAssertTrue(app.buttons["sidebar-show"].waitForExistence(timeout: 30))
            XCTAssertFalse(app.buttons["sidebar-search"].exists)
            app.swipeInFromLeftEdge()
            XCTAssertTrue(app.buttons["sidebar-search"].waitForExistence(timeout: 5), "The edge swipe shows the sidebar")
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.buttons["sidebar-jobs"])], timeout: 5), .completed, "The sidebar's Jobs row is reachable once it has slid in")
            return
        }
        XCTAssertTrue(app.drawerMenu.waitForExistence(timeout: 30))
        XCTAssertFalse(app.scrollViews["drawer-rows"].exists)
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        XCTAssertTrue(app.buttons["drawer-search"].waitForExistence(timeout: 5), "The edge swipe opens the drawer")
        XCTAssertTrue(app.scrollViews["drawer-rows"].exists)
    }

    /// iPad: the hidden sidebar's edge-swipe strip starts below the top bar, so the Show sidebar
    /// button keeps its whole target. A tap on its leading few points used to land on the strip.
    func testTabletShowSidebarButtonTakesItsLeadingEdge() throws {
        guard XCUIApplication().usesTabletLayout else {
            throw XCTSkip("iPad layout only: the phone has no Show sidebar button.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "jobs"]
        app.launch()
        let show = app.buttons["sidebar-show"]
        XCTAssertTrue(show.waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["sidebar-search"].exists)
        XCTAssertLessThan(show.frame.minX, 18, "The button sits within the edge strip's width of the screen edge")
        // 3pt inside the button's leading edge: inside the old 18pt strip.
        show.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 3, dy: show.frame.height / 2)).tap()
        XCTAssertTrue(app.buttons["sidebar-search"].waitForExistence(timeout: 5), "The button's leading edge shows the sidebar")
        // The strip still works below the bar.
        app.buttons["Close sidebar"].firstMatch.tap()
        XCTAssertTrue(app.buttons["sidebar-search"].waitForNonExistence(timeout: 5))
        app.swipeInFromLeftEdge()
        XCTAssertTrue(app.buttons["sidebar-search"].waitForExistence(timeout: 5), "The edge swipe below the bar shows the sidebar")
    }

    func testGearMenuStaysOnScreenInPortrait() { assertGearMenuOnScreen(landscape: false) }

    func testGearMenuStaysOnScreenInLandscape() { assertGearMenuOnScreen(landscape: true) }

    private func assertGearMenuOnScreen(landscape: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        let session = UUID().uuidString
        let base = ["--paper-preview", "--paper-preview-screen", "schedule", "--paper-preview-saved-work-session", session]
        cleanupArguments = base
        app.launchArguments = base + ["--paper-preview-reset-saved-work", "--paper-preview-seed-saved-work"]
        app.launch()
        app.waitForShell()
        if landscape {
            XCUIDevice.shared.orientation = .landscapeLeft
            let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.frame.width > app.frame.height
            }, object: app)
            _ = XCTWaiter.wait(for: [rotated], timeout: 5)
        }
        if app.usesTabletLayout { return assertSidebarFootOnScreen(app, landscape: landscape) }
        // The workspace name's menu (Paper 29A) stays on screen: the businesses and Add a business.
        app.openDrawer()
        let workspace = app.buttons["drawer-workspace-menu"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 5))
        app.thorbisTapCentre(workspace)
        let addBusiness = app.thorbisFrontButton(matching: NSPredicate(format: "label == %@", "Add a business"))
        XCTAssertTrue(addBusiness.waitForExistence(timeout: 5))
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "menu fades in")], timeout: 1)
        let screen = app.windows.firstMatch.frame
        let dump = app.thorbisFrameDump(addBusiness, name: "workspace-menu")
        XCTContext.runActivity(named: dump) { _ in }
        XCTAssertNotNil(app.thorbisUsableFrame(of: addBusiness), "Add a business must be reachable. \(dump)")
        XCTAssertTrue(screen.contains(addBusiness.frame), "Add a business must be fully on screen: \(dump)")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = landscape ? "Workspace menu landscape" : "Workspace menu portrait"
        shot.lifetime = .keepAlways
        add(shot)
        // Saved work is a row in Settings, which the gear opens directly.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.openSettingsFromDrawer()
        let saved = app.buttons["settings-saved-work"]
        for _ in 0..<5 where !(saved.exists && saved.isHittable) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(saved.isHittable, "Saved on this phone is a row in Settings")
        XCTAssertTrue((saved.value as? String)?.contains("saved item") == true, String(describing: saved.value))
    }

    /// iPad: saved work, the business switcher (Add a business) and Settings (where the menu is
    /// arranged) live in the sidebar, and every one can be brought fully on screen in both orientations.
    private func assertSidebarFootOnScreen(_ app: XCUIApplication, landscape: Bool) {
        if landscape { XCTAssertGreaterThan(app.frame.width, app.frame.height, "Landscape must be exercised") }
        app.showSidebar()
        let saved = app.buttons["sidebar-saved-work"]
        XCTAssertTrue(saved.waitForExistence(timeout: 15), "Saved work shows in the sidebar")
        XCTAssertTrue((saved.value as? String)?.contains("saved item") == true, String(describing: saved.value))
        let rows = [saved, app.buttons["sidebar-settings"],
                    app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Business,")).firstMatch]
        let screen = app.windows.firstMatch.frame
        // In landscape saved work and Settings can start below the fold; the list scrolls them up.
        let column = app.buttons["sidebar-search"].frame.midX / screen.width
        for row in rows {
            XCTAssertTrue(row.exists, row.description)
            for _ in 0..<6 where !row.isHittable || !screen.contains(row.frame) {
                app.coordinate(withNormalizedOffset: CGVector(dx: column, dy: 0.7))
                    .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: column, dy: 0.4)))
            }
            XCTAssertTrue(row.isHittable, "\(row.label) must be reachable")
            XCTAssertTrue(screen.contains(row.frame), "\(row.label) must be fully on screen: \(row.frame) in \(screen)")
        }
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = landscape ? "Sidebar foot landscape" : "Sidebar foot portrait"
        shot.lifetime = .keepAlways
        add(shot)
        rows[1].tap()
        XCTAssertTrue(app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS %@", "Settings")).firstMatch.waitForExistence(timeout: 5)
                      || app.staticTexts["Settings"].waitForExistence(timeout: 5), "Settings opens from the sidebar")
    }
}
