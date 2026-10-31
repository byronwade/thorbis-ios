import XCTest

/// The phone drawer (simplified 2026-10-31): the menu circle on any screen of a place opens it, and
/// every row carries a `drawer-<id>` identifier (`drawer-jobs`, `drawer-inbox`, `drawer-search`).
/// Places beyond the role's primary rows sit behind `drawer-all-places`; `openFromDrawer` unfolds it.
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

    /// A drawer row: a place (`jobs`, `inbox`, `estimates`), `all-places`, `search`, `new` or `settings`.
    func drawerRow(_ id: String) -> XCUIElement { buttons["drawer-\(id)"] }

    /// Opens the drawer and picks a row in it, unfolding All places when the row lives there.
    func openFromDrawer(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        openDrawer(file: file, line: line)
        revealDrawerRow(id)
        let row = drawerRow(id)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "No drawer row \(id)", file: file, line: line)
        row.tap()
    }

    /// Unfolds All places when `id` is not among the rows showing. All places remembers its state,
    /// so this only taps it while folded.
    func revealDrawerRow(_ id: String) {
        guard !drawerRow(id).waitForExistence(timeout: 1) else { return }
        let more = drawerRow("all-places")
        guard more.exists, (more.value as? String) != "Expanded" else { return }
        more.tap()
        _ = drawerRow(id).waitForExistence(timeout: 3)
    }

    /// Opens saved work's review from the gear (it left the drawer's list in the simplified drawer).
    func openSavedWorkFromDrawer(file: StaticString = #filePath, line: UInt = #line) {
        openDrawer(file: file, line: line)
        let gear = drawerRow("settings")
        XCTAssertTrue(gear.waitForExistence(timeout: 5), "No gear circle", file: file, line: line)
        gear.tap()
        let saved = buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Saved on this phone")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5), "No saved work in the gear menu", file: file, line: line)
        saved.tap()
    }
}
