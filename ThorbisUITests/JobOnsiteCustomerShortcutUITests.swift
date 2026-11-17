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
        // Paper 21K / F8: the job's one customer door is More › Customer view, on site included.
        XCTAssertTrue(app.staticTexts["job-title"].waitForExistence(timeout: 30))
        let shortcut = thorbisCustomerViewDoor(app)
        XCTAssertTrue(shortcut.waitForExistence(timeout: 10))
        XCTAssertTrue(shortcut.isHittable)
        XCTAssertGreaterThanOrEqual(shortcut.frame.height, 44)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Customer view")).count, 1, "On-site should have one customer-home action")
        shortcut.tap()
        XCTAssertTrue(app.staticTexts["customer-view-title"].waitForExistence(timeout: 20))
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
        // Back on the job, the door is in More again.
        XCTAssertTrue(app.buttons["Job actions"].waitForExistence(timeout: 20))
        XCTAssertTrue(thorbisCustomerViewDoor(app).waitForExistence(timeout: 10))
    }

    func testOtherJobStatesKeepCustomerViewInCustomerPanel() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-job-documents", "--paper-preview-owner-auth", "approved"]
        app.launch()
        XCTAssertTrue(app.staticTexts["job-title"].waitForExistence(timeout: 30))
        // A job not yet on its visit keeps the same door: More › Customer view.
        let door = thorbisCustomerViewDoor(app)
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        door.tap()
        XCTAssertTrue(app.staticTexts["customer-view-title"].waitForExistence(timeout: 20))
    }

    func testOnsiteShortcutIsUnavailableWithoutCustomerHandoffPermissions() {
        let app = open(["--paper-preview-no-customer-handoff"])
        XCTAssertTrue(app.staticTexts["job-title"].waitForExistence(timeout: 30))
        // Without a customer permission More either leaves the door out or shows it disabled.
        let door = thorbisCustomerViewDoor(app)
        XCTAssertFalse(door.exists && door.isEnabled, "Without a customer permission the door can't be used")
    }

    func testOnsiteShortcutAtLargestText() {
        continueAfterFailure = false
        let app = open(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.staticTexts["job-title"].waitForExistence(timeout: 30))
        let shortcut = thorbisCustomerViewDoor(app)
        XCTAssertTrue(shortcut.waitForExistence(timeout: 10))
        for _ in 0..<8 where !shortcut.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(shortcut.isHittable)
        XCTAssertGreaterThanOrEqual(shortcut.frame.height, 44)
        shortcut.tap()
        XCTAssertTrue(app.staticTexts["customer-view-title"].waitForExistence(timeout: 20))
    }
}
