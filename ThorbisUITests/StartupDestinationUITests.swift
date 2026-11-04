import XCTest

@MainActor
final class StartupDestinationUITests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "schedule", "--paper-preview-role", "tech", "--startup-fixture"] + extra
        app.launch()
        return app
    }
    private func root(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    func testPreferenceAndRootSurviveAdaptiveSwitch() {
        let app = launch()
        XCTAssertTrue(root(app, "startup-phone-customers").waitForExistence(timeout: 30))
        app.buttons["Test open jobs"].tap()
        XCTAssertTrue(root(app, "startup-phone-jobs").waitForExistence(timeout: 10))
        app.buttons["Test switch width"].tap()
        XCTAssertTrue(root(app, "startup-tablet-Jobs").waitForExistence(timeout: 10))
        app.buttons["Test schedule shortcut"].tap()
        XCTAssertTrue(root(app, "startup-tablet-Schedule").waitForExistence(timeout: 10))
        app.buttons["Test switch width"].tap()
        XCTAssertTrue(root(app, "startup-phone-schedule").waitForExistence(timeout: 10))
        app.buttons["Test open jobs"].tap()
        app.buttons["Test switch width"].tap()
        XCTAssertTrue(root(app, "startup-tablet-Jobs").waitForExistence(timeout: 10))
    }
    func testScheduleShortcutOverridesPreferenceAtLaunch() {
        let app = launch(["--startup-fixture-schedule"])
        XCTAssertTrue(root(app, "startup-phone-schedule").waitForExistence(timeout: 30))
    }
    func testCustomerLinkOverridesPreferenceAtLaunch() {
        let app = launch(["--startup-fixture-link"])
        XCTAssertTrue(app.staticTexts["Danielle Marlowe"].waitForExistence(timeout: 30))
    }
    func testPendingShortcutWinsDuringAdaptiveSwitch() {
        let app = launch()
        XCTAssertTrue(root(app, "startup-phone-customers").waitForExistence(timeout: 30))
        app.buttons["Test shortcut and switch"].tap()
        XCTAssertTrue(root(app, "startup-tablet-Schedule").waitForExistence(timeout: 10))
        app.buttons["Test switch width"].tap()
        XCTAssertTrue(root(app, "startup-phone-schedule").waitForExistence(timeout: 10))
    }

    func testAutomaticUsesHomeWhenLayoutArrivesLater() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "schedule", "--paper-preview-role", "owner", "--startup-fixture", "--startup-fixture-automatic"]
        app.launch()
        XCTAssertTrue(root(app, "startup-tablet-Schedule").waitForExistence(timeout: 30))
        app.buttons["Test delayed Home"].tap()
        XCTAssertTrue(root(app, "startup-tablet-Home").waitForExistence(timeout: 10))
    }

    func testSettingsCanChangeTheStartScreen() {
        let app = launch()
        XCTAssertTrue(root(app, "startup-phone-customers").waitForExistence(timeout: 30))
        app.buttons["Test settings"].tap()
        let setting = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Open app to")).firstMatch
        for _ in 0..<5 where !setting.isHittable { app.swipeUp() }
        XCTAssertTrue(setting.waitForExistence(timeout: 10))
        setting.tap()
        let choice = app.buttons["Jobs"]
        XCTAssertTrue(choice.waitForExistence(timeout: 10))
        choice.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Open app to", "Jobs")).firstMatch.waitForExistence(timeout: 10))
    }

    func testCustomerLinkBeatsRememberedRootDuringAdaptiveSwitch() {
        let app = launch()
        XCTAssertTrue(root(app, "startup-phone-customers").waitForExistence(timeout: 30))
        app.buttons["Test link and switch"].tap()
        XCTAssertTrue(root(app, "startup-tablet-Customers").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Danielle Marlowe"].waitForExistence(timeout: 10))
    }

    func testSearchKeepsTabletPlaceDuringAdaptiveSwitch() {
        let app = launch()
        XCTAssertTrue(root(app, "startup-phone-customers").waitForExistence(timeout: 30))
        app.buttons["Test switch width"].tap()
        XCTAssertTrue(app.buttons["Test tablet jobs"].waitForExistence(timeout: 10))
        app.buttons["Test tablet jobs"].tap()
        XCTAssertTrue(root(app, "startup-tablet-Jobs").waitForExistence(timeout: 10))
        app.buttons["Test search and switch"].tap()
        XCTAssertTrue(root(app, "startup-phone-jobs").waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "pipe fixture")).firstMatch.waitForExistence(timeout: 10))
    }

}
