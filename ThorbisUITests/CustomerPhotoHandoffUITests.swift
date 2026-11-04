import XCTest

@MainActor
final class CustomerPhotoHandoffUITests: XCTestCase {
    func testViewOnlyTechnicianCanShowPhotosWithoutEditActions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job-media", "--paper-preview-photo-handoff", "--paper-preview-job-media-view-only"]
        app.launch()
        let select = app.buttons["Select"]
        XCTAssertTrue(select.waitForExistence(timeout: 20)); select.tap()
        let photo = app.buttons["job-media-photo-00000000-0000-4000-8000-000000009301"]
        XCTAssertTrue(photo.waitForExistence(timeout: 10)); photo.tap()
        XCTAssertFalse(app.buttons["Before"].isHittable)
        XCTAssertFalse(app.buttons["After"].isHittable)
        XCTAssertFalse(app.buttons["job-media-remove-picked"].isHittable)
        XCTAssertFalse(app.buttons["Share"].isHittable)
        app.buttons["job-media-show-customer"].tap()
        XCTAssertTrue(app.images["customer-photo-image"].waitForExistence(timeout: 20))
    }

    func testFailedPreparationKeepsSelectionAndCanRetry() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job-media", "--paper-preview-photo-handoff", "--paper-preview-photo-offline-once"]
        app.launch()
        let select = app.buttons["Select"]
        XCTAssertTrue(select.waitForExistence(timeout: 20)); select.tap()
        let photo = app.buttons["job-media-photo-00000000-0000-4000-8000-000000009301"]
        XCTAssertTrue(photo.waitForExistence(timeout: 10)); photo.tap()
        let present = app.buttons["job-media-show-customer"]
        present.tap()
        XCTAssertTrue(app.staticTexts["Couldn’t verify every selected photo. Check your connection, refresh this job and try again."].waitForExistence(timeout: 20))
        XCTAssertFalse(app.images["customer-photo-image"].exists)
        XCTAssertTrue(present.isHittable); present.tap()
        XCTAssertTrue(app.images["customer-photo-image"].waitForExistence(timeout: 20))
    }

    func testArchivedDuringDownloadIsNotShownToCustomer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job-media", "--paper-preview-photo-handoff", "--paper-preview-photo-archived-after-download"]
        app.launch()
        let select = app.buttons["Select"]
        XCTAssertTrue(select.waitForExistence(timeout: 20)); select.tap()
        let photo = app.buttons["job-media-photo-00000000-0000-4000-8000-000000009301"]
        XCTAssertTrue(photo.waitForExistence(timeout: 10)); photo.tap()
        app.buttons["job-media-show-customer"].tap()
        XCTAssertTrue(app.staticTexts["Couldn’t load this photo. Try again or hand the device back to your technician."].waitForExistence(timeout: 20))
        XCTAssertFalse(app.images["customer-photo-image"].exists)
        XCTAssertFalse(app.buttons["Share"].isHittable)
    }

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
        image.swipeLeft()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: secondLabel, object: image)], timeout: 10), .completed)
        app.buttons["customer-mode-owner-exit"].tap()
        XCTAssertTrue(present.waitForExistence(timeout: 10))
    }
}
