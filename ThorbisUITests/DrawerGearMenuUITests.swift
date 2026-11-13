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
        let star = app.buttons["record-favorite-job-\(id)"]
        XCTAssertTrue(star.waitForExistence(timeout: 30))
        if star.label == "Remove from favorites" { star.tap() }
        XCTAssertEqual(star.label, "Add to favorites")
        XCTAssertGreaterThanOrEqual(star.frame.height, 43.99)
        star.tap()
        XCTAssertEqual(star.label, "Remove from favorites")
        star.tap()
        XCTAssertEqual(star.label, "Add to favorites")
    }

    func testCurrentCustomerCanBeAddedAndRemovedFromFavorites() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let id = "00000000-0000-4000-8000-000000000412"
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer", "--paper-preview-role", "office"]
        app.launch()
        let star = app.buttons["record-favorite-customer-\(id)"]
        XCTAssertTrue(star.waitForExistence(timeout: 30))
        if star.label == "Remove from favorites" { star.tap() }
        XCTAssertEqual(star.label, "Add to favorites")
        XCTAssertGreaterThanOrEqual(star.frame.height, 43.99)
        star.tap(); XCTAssertEqual(star.label, "Remove from favorites")
        star.tap(); XCTAssertEqual(star.label, "Add to favorites")
    }

    func testTabletFavoriteJobCanBeOpenedAndRemoved() throws {
        guard XCUIApplication().usesTabletLayout else { throw XCTSkip("iPad sidebar only") }
        continueAfterFailure = false
        let app = XCUIApplication()
        let id = "00000000-0000-4000-8000-000000002214"
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-role", "office"]
        app.launch()
        let star = app.buttons["record-favorite-job-\(id)"]
        XCTAssertTrue(star.waitForExistence(timeout: 30))
        if star.label == "Add to favorites" { star.tap() }
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

    func testRecentJobCanBeAddedOpenedAndRemovedFromFavorites() throws {
        guard !XCUIApplication().usesTabletLayout else { throw XCTSkip("Phone Recent surface") }
        continueAfterFailure = false
        let app = XCUIApplication()
        let id = "00000000-0000-4000-8000-000000002214"
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "jobs", "--paper-preview-role", "office", "--paper-preview-drawer-open"]
        app.launch()
        XCTAssertTrue(app.buttons["drawer-search"].waitForExistence(timeout: 30))
        let recent = app.buttons["drawer-recent-\(id)"]
        for _ in 0..<8 where !recent.isHittable { app.scrollViews["drawer-rows"].swipeUp() }
        XCTAssertTrue(recent.waitForExistence(timeout: 10)); recent.press(forDuration: 1)
        let existing = app.buttons["Remove from favorites"]
        if existing.waitForExistence(timeout: 1) { existing.tap(); recent.press(forDuration: 1) }
        let add = app.buttons["Add to favorites"]
        XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
        let favorite = app.buttons["drawer-favorite-record-\(id)"]
        for _ in 0..<8 where !favorite.isHittable { app.scrollViews["drawer-rows"].swipeDown() }
        XCTAssertTrue(favorite.waitForExistence(timeout: 15))
        favorite.tap()
        XCTAssertTrue(app.buttons["job-section-money"].waitForExistence(timeout: 15))
        // The existing pushed-screen drawer gap is covered separately; return to the root for cleanup.
        app.buttons["Back"].firstMatch.tap()
        app.openDrawer()
        XCTAssertTrue(favorite.waitForExistence(timeout: 15)); favorite.press(forDuration: 1)
        let remove = app.buttons["Remove from favorites"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5)); remove.tap()
        XCTAssertTrue(favorite.waitForNonExistence(timeout: 10))
    }

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

    func testTopWorkspaceMenuOpensSettings() throws {
        guard !XCUIApplication().usesTabletLayout else { throw XCTSkip("Phone drawer only") }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "jobs", "--paper-preview-role", "office",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); app.openDrawer()
        let workspace = app.buttons["drawer-workspace-menu"]
        XCTAssertGreaterThanOrEqual(workspace.frame.height, 44)
        workspace.tap()
        let settings = app.buttons.matching(NSPredicate(format: "label == %@", "Settings")).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5)); settings.tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.scrollViews["drawer-rows"].exists)
    }

    func testWorkspaceDisclosureRevealsPlacesWithoutOpeningAnotherScreen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "jobs", "--paper-preview-role", "office",
                               "--paper-preview-menu-suite", UUID().uuidString]
        app.launch()
        if app.usesTabletLayout { app.showSidebar() } else { app.openDrawer() }
        let prefix = app.usesTabletLayout ? "sidebar" : "drawer"
        let disclosure = app.buttons["\(prefix)-workspace-work"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 15))
        if disclosure.value as? String == "Collapsed" { disclosure.tap() }
        XCTAssertEqual(disclosure.value as? String, "Expanded")
        disclosure.tap()
        XCTAssertEqual(disclosure.value as? String, "Collapsed")
        XCTAssertFalse(app.buttons["\(prefix)-estimates"].exists)
        disclosure.tap()
        XCTAssertEqual(disclosure.value as? String, "Expanded")
        XCTAssertTrue(app.buttons["\(prefix)-estimates"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["\(prefix)-invoices"].exists)
        XCTAssertTrue(app.buttons["\(prefix)-jobs"].exists)
    }

    func testWorkspaceLabelTogglesPlacesWithoutLeavingMenu() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "jobs", "--paper-preview-role", "office",
                               "--paper-preview-menu-suite", UUID().uuidString]
        app.launch()
        if app.usesTabletLayout { app.showSidebar() } else { app.openDrawer() }
        let prefix = app.usesTabletLayout ? "sidebar" : "drawer"
        let group = app.buttons["\(prefix)-workspace-work"]
        XCTAssertTrue(group.waitForExistence(timeout: 15))
        if group.value as? String == "Collapsed" { group.tap() }
        XCTAssertGreaterThanOrEqual(group.frame.height, 44)
        XCTAssertEqual(group.value as? String, "Expanded")
        group.tap()
        XCTAssertEqual(group.value as? String, "Collapsed")
        XCTAssertFalse(app.buttons["\(prefix)-jobs"].exists)
        group.tap()
        XCTAssertEqual(group.value as? String, "Expanded")
        XCTAssertTrue(app.buttons["\(prefix)-jobs"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["\(prefix)-estimates"].exists)
        XCTAssertTrue(app.buttons["\(prefix)-invoices"].exists)
    }

    func testWorkPreferenceSurvivesRelaunchAndJobsCanBeOpened() throws {
        guard !XCUIApplication().usesTabletLayout else { throw XCTSkip("Phone drawer persistence") }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "schedule", "--paper-preview-role", "office",
                               "--paper-preview-menu-suite", UUID().uuidString]
        app.launch()
        app.openDrawer()
        let prefix = "drawer"
        let group = app.buttons["\(prefix)-workspace-work"]
        XCTAssertTrue(group.waitForExistence(timeout: 15))
        XCTAssertEqual(group.value as? String, "Expanded", "Work is open with fresh preferences")
        group.tap()
        XCTAssertEqual(group.value as? String, "Collapsed")
        app.buttons["drawer-schedule"].tap()
        app.openDrawer()
        XCTAssertEqual(group.value as? String, "Collapsed", "The chosen state survives closing the menu")
        app.terminate()
        app.launch()
        app.openDrawer()
        XCTAssertEqual(group.value as? String, "Collapsed", "The chosen state survives restarting the app")
        group.tap()
        XCTAssertEqual(group.value as? String, "Expanded")
        let jobs = app.buttons["\(prefix)-jobs"]
        XCTAssertTrue(jobs.waitForExistence(timeout: 5))
        jobs.tap()
        XCTAssertTrue(app.staticTexts["Jobs"].waitForExistence(timeout: 10))
    }

    func testWebAlignedPlacesAndDeviceOnlyDraftLabel() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "jobs", "--paper-preview-role", "office",
                               "--paper-preview-menu-suite", UUID().uuidString]
        app.launch()
        if app.usesTabletLayout { app.showSidebar() } else { app.openDrawer() }
        let prefix = app.usesTabletLayout ? "sidebar" : "drawer"
        let work = app.buttons["\(prefix)-workspace-work"]
        XCTAssertTrue(work.waitForExistence(timeout: 15))
        if work.value as? String == "Collapsed" { work.tap() }
        if !app.usesTabletLayout {
            XCTAssertTrue(app.buttons["drawer-workspace-menu"].exists)
            XCTAssertTrue(app.buttons["drawer-new-menu"].exists)
            XCTAssertTrue(app.buttons["drawer-new"].exists, "The direct New job shortcut remains available")
            XCTAssertTrue(app.buttons["drawer-settings"].exists)
        }
        let jobs = app.buttons["\(prefix)-jobs"]
        let estimates = app.buttons["\(prefix)-estimates"]
        let invoices = app.buttons["\(prefix)-invoices"]
        XCTAssertTrue(jobs.waitForExistence(timeout: 15))
        XCTAssertTrue(estimates.exists)
        XCTAssertTrue(invoices.exists)
        XCTAssertLessThan(jobs.frame.minY, estimates.frame.minY)
        XCTAssertLessThan(estimates.frame.minY, invoices.frame.minY)
        XCTAssertTrue(work.exists)
        XCTAssertEqual(work.value as? String, "Expanded")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Web-aligned sidebar"
        shot.lifetime = .keepAlways
        add(shot)
        let other = app.buttons["\(prefix)-workspace-other"]
        if other.exists {
            if !app.usesTabletLayout { app.revealDrawerRow("workspace-other") }
            other.tap()
        }
        let drafts = app.buttons["\(prefix)-drafts"]
        XCTAssertTrue(drafts.exists)
        XCTAssertTrue(drafts.label.contains(app.usesTabletLayout ? "On this iPad" : "On this phone"), drafts.label)
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
        XCTAssertFalse(app.drawerRow("new").exists, "The closed drawer's New job must not be in the tree")
        XCTAssertFalse(app.drawerRow("settings").exists, "The closed drawer's gear must not be in the tree")
        XCTAssertFalse(app.drawerRow("search").exists)
        XCTAssertFalse(app.scrollViews["drawer-rows"].exists, "The closed drawer's (empty) scroll view must not be in the tree")
        app.openDrawer()
        XCTAssertTrue(app.drawerRow("new").waitForExistence(timeout: 5))
        XCTAssertTrue(app.drawerRow("settings").exists)
        XCTAssertTrue(app.scrollViews["drawer-rows"].exists)
        // Closing takes everything out again once the drawer has slid shut.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        // The UIKit-hosted controls leave as the close starts (VoiceOver returns to the place then);
        // only the rows stay through the slide.
        XCTAssertFalse(app.drawerRow("new").exists, "New job must leave the tree as the drawer starts closing")
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
            XCTAssertTrue(app.buttons["sidebar-jobs"].isHittable)
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
            _ = XCTWaiter.wait(for: [XCTestExpectation(description: "rotation settles")], timeout: 2)
        }
        if app.usesTabletLayout { return assertSidebarFootOnScreen(app, landscape: landscape) }
        app.openDrawer()
        let gear = app.drawerRow("settings")
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        gear.tap()
        // "Saved on this phone" carries its count after a comma; the gear itself reads "Settings and
        // businesses", so the other rows are matched exactly. The drawer's own "Saved on this phone"
        // row (under On this phone) sits behind the open menu, so it is left out.
        let rows = [app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND identifier != %@", "Saved on this phone", "drawer-saved-work")).firstMatch]
            + ["Add a business", "Settings", "Edit menu"].map { app.buttons.matching(NSPredicate(format: "label == %@", $0)).firstMatch }
        XCTAssertTrue(rows[0].waitForExistence(timeout: 5), "Saved work shows in the gear menu")
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "menu fades in")], timeout: 1)
        let screen = app.windows.firstMatch.frame
        for row in rows {
            XCTAssertTrue(row.exists, row.description)
            XCTAssertTrue(row.isHittable, "\(row.label) must be reachable")
            XCTAssertTrue(screen.contains(row.frame), "\(row.label) must be fully on screen: \(row.frame) in \(screen)")
        }
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = landscape ? "Gear menu landscape" : "Gear menu portrait"
        shot.lifetime = .keepAlways
        add(shot)
        rows[2].tap()
        XCTAssertTrue(app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS %@", "Settings")).firstMatch.waitForExistence(timeout: 5)
                      || app.staticTexts["Settings"].waitForExistence(timeout: 5), "Settings opens from the menu")
    }

    /// iPad: the gear's rows live in the sidebar — saved work, the business switcher (Add a business)
    /// and Settings (Customize menu) — and every one can be brought fully on screen in both orientations.
    private func assertSidebarFootOnScreen(_ app: XCUIApplication, landscape: Bool) {
        if landscape { XCTAssertGreaterThan(app.frame.width, app.frame.height, "Landscape must be exercised") }
        app.showSidebar()
        let saved = app.buttons["sidebar-saved-work"]
        XCTAssertTrue(saved.waitForExistence(timeout: 15), "Saved work shows in the sidebar")
        XCTAssertTrue((saved.value as? String)?.contains("saved item") == true, String(describing: saved.value))
        let rows = [saved, app.buttons["sidebar-settings"],
                    app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Business,")).firstMatch]
        let screen = app.windows.firstMatch.frame
        // Cream sheet: the sidebar lists every place under Work, Money, Shop and On this iPad, so in
        // landscape saved work and Settings can start below the fold; the list scrolls them up.
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
