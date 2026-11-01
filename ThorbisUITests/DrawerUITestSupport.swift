import XCTest

/// The phone drawer (simplified 2026-10-31): the menu circle on any screen of a place opens it, and
/// every row carries a `drawer-<id>` identifier (`drawer-jobs`, `drawer-inbox`, `drawer-search`).
/// Every place the role can reach is listed, grouped (Work, Money, Shop, On this phone); `openFromDrawer`
/// scrolls the list until the row is reachable.
extension XCUIApplication {
    /// The menu circle at the top left of the place showing.
    var drawerMenu: XCUIElement { buttons["drawer-menu"] }

    /// Opens the drawer from the menu circle and waits for it to show.
    @discardableResult
    func openDrawer(timeout: TimeInterval = 30, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let menu = drawerMenu
        XCTAssertTrue(menu.waitForExistence(timeout: timeout), "No menu circle on this screen", file: file, line: line)
        menu.tap()
        let shown = buttons["drawer-search"].waitForExistence(timeout: 5)
        XCTAssertTrue(shown, "The drawer did not open", file: file, line: line)
        return shown
    }

    /// A drawer row: a place (`jobs`, `inbox`, `estimates`), `local-fleet`, `saved-work`, `search`, `new` or `settings`.
    func drawerRow(_ id: String) -> XCUIElement { buttons["drawer-\(id)"] }

    /// Opens the drawer and picks a row in it, scrolling to it when it sits low in the list.
    func openFromDrawer(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        openDrawer(file: file, line: line)
        revealDrawerRow(id)
        let row = drawerRow(id)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "No drawer row \(id)", file: file, line: line)
        row.tap()
    }

    /// Cream sheet: every place is listed, grouped. A row low in the list can sit under the New job
    /// commit and the gear, so the list scrolls until the row is reachable.
    func revealDrawerRow(_ id: String) {
        let row = drawerRow(id)
        _ = row.waitForExistence(timeout: 2)
        let list = scrollViews["drawer-rows"]
        for _ in 0..<6 where !row.isHittable {
            guard list.exists else { return }
            list.swipeUp(velocity: .slow)
        }
    }

    /// Opens saved work's review from the gear (it left the drawer's list in the simplified drawer).
    func openSavedWorkFromDrawer(file: StaticString = #filePath, line: UInt = #line) {
        openDrawer(file: file, line: line)
        let gear = drawerRow("settings")
        XCTAssertTrue(gear.waitForExistence(timeout: 5), "No gear circle", file: file, line: line)
        gear.tap()
        let saved = buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND identifier != %@", "Saved on this phone", "drawer-saved-work")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5), "No saved work in the gear menu", file: file, line: line)
        saved.tap()
    }
}
