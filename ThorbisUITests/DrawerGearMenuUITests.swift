import XCTest

/// The drawer's gear and its menu (#227: the menu grows up from the gear so every row stays on
/// screen), and the closed drawer staying out of the accessibility tree.
@MainActor
final class DrawerGearMenuUITests: XCTestCase {
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

    /// The edge swipe still opens the drawer although its contents are not built while closed.
    func testEdgeSwipeOpensTheDrawer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "jobs"]
        app.launch()
        XCTAssertTrue(app.drawerMenu.waitForExistence(timeout: 30))
        XCTAssertFalse(app.scrollViews["drawer-rows"].exists)
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        XCTAssertTrue(app.buttons["drawer-search"].waitForExistence(timeout: 5), "The edge swipe opens the drawer")
        XCTAssertTrue(app.scrollViews["drawer-rows"].exists)
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
        XCTAssertTrue(app.drawerMenu.waitForExistence(timeout: 30))
        if landscape {
            XCUIDevice.shared.orientation = .landscapeLeft
            _ = XCTWaiter.wait(for: [XCTestExpectation(description: "rotation settles")], timeout: 2)
        }
        app.openDrawer()
        let gear = app.drawerRow("settings")
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        gear.tap()
        // "Saved on this phone" carries its count after a comma; the gear itself reads "Settings and
        // businesses", so the other rows are matched exactly.
        let rows = [app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Saved on this phone")).firstMatch]
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
}
