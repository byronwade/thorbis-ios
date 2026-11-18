import XCTest

/// The phone drawer: the menu circle on any screen of a place opens it, and every row carries a
/// `drawer-<id>` identifier (`drawer-jobs`, `drawer-inbox`, `drawer-search`). It lists Paper's rows
/// for the role and nothing else (Navigation 29N / 57N / 58N); a place Paper reaches from inside
/// another screen (Estimates and Invoices from Money, My scorecard from Reports…) opens from that
/// screen's `door-<id>` row or from Search. `openFromDrawer` scrolls the list until the row is reachable.
extension XCUIApplication {
    /// The menu circle at the top left of the place showing.
    var drawerMenu: XCUIElement { buttons["drawer-menu"] }

    /// Opens the drawer from the menu circle and waits for it to show.
    ///
    /// Never reads `isHittable` or calls `.tap()` on the circle: after rotation and at XXXL the
    /// control exists with an invalid activation point, and XCTest fails before a coordinate tap
    /// can run. A missed centre tap is retried, then the root edge-swipe opens the drawer.
    @discardableResult
    func openDrawer(timeout: TimeInterval = 30, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let menu = drawerMenu
        XCTAssertTrue(menu.waitForExistence(timeout: timeout), "No menu circle on this screen", file: file, line: line)
        let search = buttons["drawer-search"]
        if thorbisUsableFrame(of: search) != nil { return true }
        thorbisTapCentre(menu, fallback: CGVector(dx: 0.07, dy: 0.08))
        if search.waitForExistence(timeout: 2) { return true }
        thorbisTapCentre(menu, fallback: CGVector(dx: 0.07, dy: 0.08))
        if search.waitForExistence(timeout: 2) { return true }
        swipeInFromLeftEdge(atY: 0.35)
        let shown = search.waitForExistence(timeout: 5)
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
        for _ in 0..<6 where thorbisUsableFrame(of: row) == nil {
            guard list.exists else { return }
            list.swipeUp(velocity: .slow)
        }
    }

    /// Opens Settings from the drawer's gear (Paper 65: the gear opens Settings directly).
    func openSettingsFromDrawer(file: StaticString = #filePath, line: UInt = #line) {
        openDrawer(file: file, line: line)
        let gear = drawerRow("settings")
        XCTAssertTrue(gear.waitForExistence(timeout: 5), "No gear circle", file: file, line: line)
        thorbisTapCentre(gear)
        XCTAssertTrue(buttons["settings-account-data"].waitForExistence(timeout: 10), "Settings did not open from the gear", file: file, line: line)
    }

    /// Opens saved work's review: the gear opens Settings, where "Saved on this phone" is a row.
    func openSavedWorkFromDrawer(file: StaticString = #filePath, line: UInt = #line) {
        openSettingsFromDrawer(file: file, line: line)
        let saved = buttons["settings-saved-work"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5), "No saved work row in Settings", file: file, line: line)
        for _ in 0..<4 where !saved.isHittable { swipeUp(velocity: .slow) }
        saved.tap()
    }
}
