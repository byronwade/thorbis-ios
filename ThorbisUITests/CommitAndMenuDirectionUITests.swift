import XCTest

/// Commits are never pre-disabled (pressed early, they say what's missing under the field), and
/// anchored popovers low on the screen grow up into the room above them instead of squeezing below.
@MainActor
final class CommitAndMenuDirectionUITests: XCTestCase {
    // MARK: Commits

    func testPriceBookCommitIsPressableAndSaysWhatIsMissing() {
        continueAfterFailure = false
        let app = launchPriceBookEditor()
        let commit = app.buttons["price-book-item-commit"]
        XCTAssertTrue(commit.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(commit.isEnabled, "Add to price book is never pre-disabled")
        commit.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Add the name customers see")).firstMatch
            .waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Add a price, like 125.00."].exists, app.debugDescription)
        attach(app, "Price book commit pressed blank")
    }

    func testEquipmentCommitIsPressableAndSaysWhatIsMissing() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "equipment-editor"]
        app.launch()
        let commit = app.buttons["equipment-commit"]
        XCTAssertTrue(commit.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(commit.isEnabled, "Add equipment is never pre-disabled")
        commit.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Say what it is")).firstMatch
            .waitForExistence(timeout: 5), app.debugDescription)
        attach(app, "Equipment commit pressed blank")
    }

    // MARK: Popover direction

    /// Kind and Tax sit in the lower half of the price book editor: their menus open upward and
    /// every row stays on screen.
    func testLowerHalfSelectsOpenUpward() {
        continueAfterFailure = false
        let app = launchPriceBookEditor()
        for (label, option) in [("Kind,", "Material"), ("Tax,", "Not taxable")] {
            let select = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
            XCTAssertTrue(select.waitForExistence(timeout: 30), app.debugDescription)
            XCTAssertGreaterThan(select.frame.midY, app.windows.firstMatch.frame.midY, "\(label) sits in the lower half")
            select.tap()
            let row = app.buttons[option]
            assertMenuRow(row, opensAbove: select, in: app)
            attach(app, "\(label.dropLast()) menu open")
            row.tap()
            XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        }
    }

    /// The invite's Role select sits in the upper half: its menu opens downward, fully on screen.
    func testInviteRoleSelectStaysOnScreen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "team", "--paper-preview-sheet", "team-invite"]
        app.launch()
        let select = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Role,")).firstMatch
        XCTAssertTrue(select.waitForExistence(timeout: 30), app.debugDescription)
        // The email field takes focus as the sheet appears; open the select once its keyboard is up
        // (the iPad's form sheet takes longer to present, so the keyboard can arrive after a quick tap).
        let up = Date().addingTimeInterval(5)
        while !app.keyboardShowing && Date() < up { usleep(200_000) }
        select.tap()
        let row = app.buttons["Office manager"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: row)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(row.frame), "\(row.frame)")
        // The email field has focus on appear; opening the select puts the keyboard away so the
        // menu's last rows aren't hidden behind it.
        XCTAssertTrue(app.waitForKeyboardToHide(timeout: 5), "The keyboard goes away when a menu opens")
        attach(app, "Role menu open")
    }

    /// A location row's ••• low on the customer page opens its menu upward.
    func testLowerRowOverflowMenuOpensUpward() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customer", "--paper-preview-many-locations"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Danielle Marlowe"].waitForExistence(timeout: 30))
        let window = app.windows.firstMatch.frame
        let newJob = app.buttons["customer-new-job-action"]
        let menus = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Options for "))
        func lowerMenu() -> XCUIElement? {
            let floor = newJob.exists ? newJob.frame.minY - 8 : window.maxY - 60
            return menus.allElementsBoundByIndex.first { $0.isHittable && $0.frame.midY > window.midY && $0.frame.maxY < floor }
        }
        for _ in 0..<20 where lowerMenu() == nil {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)))
        }
        guard let overflow = lowerMenu() else { return XCTFail("No location ••• in the lower half: \(app.debugDescription)") }
        overflow.tap()
        assertMenuRow(app.buttons["Edit location"], opensAbove: overflow, in: app)
        assertMenuRow(app.buttons["Remove location"], opensAbove: overflow, in: app)
        attach(app, "Location row menu open")
    }

    // MARK: Helpers

    private func launchPriceBookEditor() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "price-book", "--paper-preview-pricebook-admin",
                               "--paper-preview-sheet", "price-book-new"]
        app.launch()
        return app
    }

    private func assertMenuRow(_ row: XCUIElement, opensAbove anchor: XCUIElement, in app: XCUIApplication,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: row)
        waitForExpectations(timeout: 5)
        XCTAssertLessThanOrEqual(row.frame.maxY, anchor.frame.minY + 1,
                                 "\(row.label) should sit above its control: \(row.frame) vs \(anchor.frame)", file: file, line: line)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(row.frame), "\(row.label) must be fully on screen", file: file, line: line)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
