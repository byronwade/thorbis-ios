import XCTest

/// The iPhone bottom bar (Paper 18A), run with `--paper-preview-nav bottom`: the design preview
/// otherwise keeps the sidebar so the drawer tests stay valid.
@MainActor
final class TabBarUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try skipOnTablet(because: "iPad keeps its sidebar")
    }

    private func launch(_ screen: String, role: String = "tech", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-nav", "bottom", "--paper-preview-screen", screen,
                               "--paper-preview-role", role] + extra
        app.launch()
        return app
    }

    private func tab(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.buttons["tabbar-\(id)"] }

    private func assertTabs(_ app: XCUIApplication, _ ids: [String], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(tab(app, "more").waitForExistence(timeout: 30), "The bar shows", file: file, line: line)
        for id in ids { XCTAssertTrue(tab(app, id).exists, "Tab \(id)", file: file, line: line) }
        let all = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tabbar-'"))
        XCTAssertEqual(all.count, ids.count + 1, "Only the role's places and More", file: file, line: line)
        XCTAssertFalse(app.buttons["drawer-menu"].exists, "No menu circle while the bar is on", file: file, line: line)
    }

    func testTechnicianTabs() {
        let app = launch("my-day")
        assertTabs(app, ["schedule", "jobs", "customers", "inbox"])
        XCTAssertTrue(tab(app, "schedule").isSelected)
        tab(app, "jobs").tap()
        XCTAssertTrue(tab(app, "jobs").waitForSelected())
    }

    func testOfficeTabs() {
        let app = launch("my-day", role: "office")
        assertTabs(app, ["schedule", "jobs", "customers", "inbox"])
    }

    func testOwnerTabs() {
        let app = launch("schedule", role: "owner")
        assertTabs(app, ["home", "schedule", "jobs", "money"])
        XCTAssertTrue(tab(app, "home").isSelected, "Owners open on their Dashboard")
    }

    func testMoreOpensTheDrawer() {
        let app = launch("my-day")
        XCTAssertTrue(tab(app, "more").waitForExistence(timeout: 30))
        tab(app, "more").tap()
        XCTAssertTrue(app.buttons["drawer-search"].waitForExistence(timeout: 5), "More opens the full menu")
        XCTAssertTrue(app.buttons["drawer-timeClock"].exists)
        // A place from the drawer that is not a tab lights More.
        app.drawerRow("timeClock").tap()
        XCTAssertTrue(app.staticTexts["timeclock-root"].waitForExistence(timeout: 10))
        XCTAssertTrue(tab(app, "more").waitForSelected())
    }

    func testBarHidesOnAPushedJobAndReturnsAtTheRoot() {
        let app = launch("job")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == 'Back'")).firstMatch.waitForExistence(timeout: 30))
        XCTAssertFalse(tab(app, "more").exists, "No bar over the job page")
        app.buttons.matching(NSPredicate(format: "label == 'Back'")).firstMatch.tap()
        XCTAssertTrue(tab(app, "more").waitForExistence(timeout: 10), "The bar is back at the root")
    }

    func testBarHidesWhileASheetIsUp() {
        let app = launch("create-menu")
        XCTAssertTrue(app.staticTexts["Create"].waitForExistence(timeout: 30))
        XCTAssertFalse(tab(app, "more").exists, "No bar under the create menu")
    }

    func testRetappingTheActiveTabReturnsToTheTop() {
        let app = launch("my-day")
        let title = app.staticTexts["schedule-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        for _ in 0..<3 { app.swipeUp() }
        tab(app, "schedule").tap()
        XCTAssertTrue(title.waitForHittable(timeout: 5), "Back at the top of Schedule")
        // From a pushed page Back is the way out; the bar is not there to re-tap.
        tab(app, "jobs").tap()
        XCTAssertTrue(tab(app, "jobs").waitForSelected())
    }

    func testSettingSwitchesToTheSidebarAndBack() {
        let app = launch("customize-menu")
        let row = app.buttons["menu-navigation"]
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        XCTAssertEqual(row.value as? String, "Bottom bar")
        row.tap()
        let sidebar = app.buttons["navigation-sidebar"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
        XCTAssertTrue(sidebar.isSelected)
        // Back to the place: the menu circle returns and the bar is gone.
        let back = app.buttons.matching(NSPredicate(format: "label == 'Back'")).firstMatch
        back.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.value as? String, "Sidebar")
        app.buttons.matching(NSPredicate(format: "label == 'Back'")).firstMatch.tap()
        XCTAssertTrue(app.drawerMenu.waitForExistence(timeout: 10), "Sidebar: the menu circle is back")
        XCTAssertFalse(tab(app, "more").exists)
        // And back to the bar from Settings › Menu and start screen.
        app.openSettingsFromDrawer()
        app.buttons["settings-menu"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        app.buttons["navigation-bottomBar"].tap()
        XCTAssertTrue(app.buttons["navigation-bottomBar"].isSelected)
    }

    func testLargestTextShowsWordsUnderTheIcons() {
        let app = launch("my-day", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        assertTabs(app, ["schedule", "jobs", "customers", "inbox"])
        for id in ["schedule", "jobs", "customers", "inbox", "more"] {
            let item = tab(app, id)
            XCTAssertTrue(item.isHittable, "\(id) can be tapped")
            XCTAssertGreaterThanOrEqual(item.frame.height, 44)
            XCTAssertGreaterThanOrEqual(item.frame.width, 44)
        }
        let bar = tab(app, "more").frame
        XCTAssertLessThanOrEqual(bar.maxX, app.windows.firstMatch.frame.maxX, "The bar fits the screen")
        tab(app, "customers").tap()
        XCTAssertTrue(tab(app, "customers").waitForSelected())
    }
}

private extension XCUIElement {
    func waitForSelected(timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if exists && isSelected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    func waitForHittable(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if exists && isHittable { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }
}
