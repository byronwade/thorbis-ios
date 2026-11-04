import XCTest

@MainActor
final class CustomerPhotoHandoffUITests: XCTestCase {
    func testSelectedPhotosStayInCustomerModeUntilAuthenticatedHandBack() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job-media", "--paper-preview-media-dates", "--paper-preview-photo-handoff", "--paper-preview-owner-auth", "approved"]
        app.launch()
        let select = app.buttons["Select"]
        XCTAssertTrue(select.waitForExistence(timeout: 20)); select.tap()
        let first = app.buttons["job-media-photo-00000000-0000-4000-8000-000000009301"]
        let second = app.buttons["job-media-photo-00000000-0000-4000-8000-000000009302"]
        XCTAssertTrue(first.waitForExistence(timeout: 10)); first.tap()
        XCTAssertTrue(second.waitForExistence(timeout: 10)); second.tap()
        let present = app.buttons["job-media-show-customer"]
        XCTAssertTrue(present.waitForExistence(timeout: 5)); present.tap()
        let image = app.images["customer-photo-image"]
        XCTAssertTrue(image.waitForExistence(timeout: 20))
        XCTAssertEqual(image.label, "Photo 1 of 2")
        XCTAssertFalse(app.buttons["Before"].isHittable)
        XCTAssertFalse(app.buttons["Share"].isHittable)
        XCTAssertFalse(app.buttons["Remove"].isHittable)
        XCTAssertFalse(app.staticTexts["Outdoor unit"].isHittable)
        app.buttons["Next"].tap()
        let secondLabel = NSPredicate(format: "label == %@", "Photo 2 of 2")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: secondLabel, object: image)], timeout: 10), .completed)
        app.buttons["Previous"].tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Photo 1 of 2"), object: image)], timeout: 10), .completed)
        app.buttons["customer-mode-owner-exit"].tap()
        XCTAssertTrue(present.waitForExistence(timeout: 10))
    }
}
