import XCTest

@MainActor
final class CustomerHandBackLargeTextUITests: XCTestCase {
    func testHandBackButtonFitsItsFullLabelAtLargestText() {
        let app = openCustomerDocuments()
        let handBack = app.buttons["Hand back to the technician"]
        XCTAssertTrue(handBack.waitForExistence(timeout: 10))
        XCTAssertTrue(handBack.isHittable)
        XCTAssertGreaterThan(handBack.frame.height, 56, "The fixed-height button clips its long label at accessibility sizes.")
        let title = handBack.staticTexts["Hand back to the technician"]
        XCTAssertTrue(title.exists)
        XCTAssertGreaterThanOrEqual(title.frame.minX, handBack.frame.minX)
        XCTAssertLessThanOrEqual(title.frame.maxX, handBack.frame.maxX)
        XCTAssertGreaterThanOrEqual(title.frame.minY, handBack.frame.minY)
        XCTAssertLessThanOrEqual(title.frame.maxY, handBack.frame.maxY)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Customer hand-back at largest text"; screenshot.lifetime = .keepAlways; add(screenshot)
        handBack.tap()
        let unlock = app.buttons["Technician: unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 10))
        XCTAssertTrue(unlock.isHittable)
        XCTAssertGreaterThanOrEqual(unlock.frame.height, 56)
        XCTAssertTrue(app.buttons["Go back"].isHittable)
    }

    private func openCustomerDocuments() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-working-job", "--paper-preview-job-documents", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["Job actions"].waitForExistence(timeout: 15))
        app.buttons["Job actions"].tap(); app.buttons["Show to customer"].tap()
        XCTAssertTrue(app.staticTexts["Your job documents"].waitForExistence(timeout: 15))
        return app
    }
}
