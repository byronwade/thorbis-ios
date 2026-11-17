import XCTest

@MainActor
final class JobOnsiteCustomerShortcutUITests: XCTestCase {
    private func open(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job", "--paper-preview-job-documents", "--paper-preview-scroll-toolkit", "--paper-preview-owner-auth", "approved"] + extra
        app.launch()
        return app
    }

    func testOnsiteShortcutOpensOnlyThisJobsCustomerDocuments() {
        continueAfterFailure = false
        let app = open()
        let shortcut = app.buttons["job-onsite-show-customer"]
        XCTAssertTrue(shortcut.waitForExistence(timeout: 30))
        app.scrollClearOfFoot(shortcut)
        XCTAssertTrue(shortcut.isHittable)
        XCTAssertGreaterThanOrEqual(shortcut.frame.height, 44)
        XCTAssertFalse(app.buttons["job-customer-view"].exists, "On-site should have one customer-home action")
        shortcut.tap()
        XCTAssertTrue(app.staticTexts["Your job documents"].waitForExistence(timeout: 20))
        for id in ["00000000-0000-4000-8000-000000002218", "00000000-0000-4000-8000-000000002238"] {
            XCTAssertTrue(app.buttons["customer-estimate-\(id)"].exists)
        }
        for id in ["00000000-0000-4000-8000-000000002209", "00000000-0000-4000-8000-000000002240"] {
            XCTAssertTrue(app.buttons["customer-invoice-\(id)"].exists)
        }
        XCTAssertFalse(app.buttons["customer-invoice-00000000-0000-4000-8000-000000002241"].exists)
        let handBack = app.buttons["Hand back to the technician"]
        XCTAssertTrue(handBack.exists)
        handBack.tap()
        XCTAssertTrue(shortcut.waitForExistence(timeout: 20))
    }

    func testOtherJobStatesKeepCustomerViewInCustomerPanel() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-job-documents", "--paper-preview-owner-auth", "approved"]
        app.launch()
        XCTAssertTrue(app.staticTexts["job-title"].waitForExistence(timeout: 30))
        let door = app.buttons["job-customer-view"]
        for _ in 0..<10 where !door.exists { app.swipeUp() }
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        app.scrollClearOfFoot(door)
        door.tap()
        XCTAssertTrue(app.staticTexts["Your job documents"].waitForExistence(timeout: 20))
    }

    func testOnsiteShortcutIsUnavailableWithoutCustomerHandoffPermissions() {
        let app = open(["--paper-preview-no-customer-handoff"])
        XCTAssertTrue(app.descendants(matching: .any)["job-toolkit"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["job-onsite-show-customer"].exists)
    }

    func testOnsiteShortcutAtLargestText() {
        continueAfterFailure = false
        let app = open(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let shortcut = app.buttons["job-onsite-show-customer"]
        XCTAssertTrue(app.staticTexts["job-title"].waitForExistence(timeout: 30))
        for _ in 0..<8 where !shortcut.exists { app.swipeUp() }
        XCTAssertTrue(shortcut.waitForExistence(timeout: 10))
        app.scrollClearOfFoot(shortcut)
        for _ in 0..<8 where !shortcut.isHittable { app.swipeUp() }
        XCTAssertTrue(shortcut.isHittable)
        XCTAssertGreaterThanOrEqual(shortcut.frame.height, 44)
        shortcut.tap()
        XCTAssertTrue(app.staticTexts["Your job documents"].waitForExistence(timeout: 20))
    }
}
