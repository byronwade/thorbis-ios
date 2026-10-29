import XCTest

@MainActor
final class JobMediaQueueUITests: XCTestCase {
    func testSavedScanRemainsJobBoundAfterNavigationAndRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let base = ["--paper-preview", "--paper-preview-screen", "job-media", "-thorbis.appearance", "light"]
        app.launchArguments = base + ["--paper-preview-reset-media", "--paper-preview-seed-media"]
        app.launch()
        defer {
            app.terminate()
            app.launchArguments = base + ["--paper-preview-reset-media"]
            app.launch()
            app.terminate()
        }
        let scan = app.descendants(matching: .any).matching(identifier: "pending-media-00000000-0000-4000-8000-000000009701").firstMatch
        let expectedCapture = "Captured " + Date(timeIntervalSince1970: 1_700_000_000).formatted(date: .abbreviated, time: .shortened)
        XCTAssertTrue(scan.waitForExistence(timeout: 20))
        XCTAssertEqual(scan.value as? String, expectedCapture)
        XCTAssertTrue(scan.label.contains("Field scan.pdf"))
        XCTAssertFalse(app.staticTexts["No photos yet"].exists)
        XCTAssertTrue(app.buttons["Add a document"].exists)
        XCTAssertTrue(app.buttons["Choose from library"].exists)
        app.buttons["Overview"].tap()
        app.buttons["Photos"].tap()
        XCTAssertTrue(scan.waitForExistence(timeout: 10))
        XCTAssertEqual(scan.value as? String, expectedCapture)
        app.terminate()
        app.launchArguments = base
        app.launch()
        XCTAssertTrue(scan.waitForExistence(timeout: 20))
        XCTAssertEqual(scan.value as? String, expectedCapture)
        XCTAssertTrue(scan.label.contains("Field scan.pdf"))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "pending-media-00000000-0000-4000-8000-000000009702").firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Other job scan.pdf"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Durable scanned PDF after relaunch"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testOlderPhotoRequiresNamedDestinationConfirmationAndSurvivesRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let base = ["--paper-preview", "--paper-preview-screen", "job-media", "-thorbis.appearance", "light"]
        app.launchArguments = base + ["--paper-preview-reset-media", "--paper-preview-seed-legacy"]
        app.launch()
        let recover = app.buttons["Recover older photos"]
        XCTAssertTrue(recover.waitForExistence(timeout: 20)); recover.tap()
        let candidate = app.buttons["legacy-recover-00000000-0000-4000-8000-000000009703"]
        XCTAssertTrue(candidate.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["legacy-recover-00000000-0000-4000-8000-000000009704"].exists)
        let destinationImage = XCTAttachment(screenshot: app.screenshot())
        destinationImage.name = "Verified legacy recovery destination"; destinationImage.lifetime = .keepAlways; add(destinationImage)
        candidate.tap()
        let confirm = app.buttons["Recover to this job"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "original account is unknown")).firstMatch.exists)
        let confirmationImage = XCTAttachment(screenshot: app.screenshot())
        confirmationImage.name = "Explicit legacy adoption confirmation"; confirmationImage.lifetime = .keepAlways; add(confirmationImage)
        confirm.tap()
        XCTAssertTrue(app.staticTexts.matching(identifier: "Recovered to this job").firstMatch.waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        let row = app.descendants(matching: .any).matching(identifier: "pending-media-00000000-0000-4000-8000-000000009703").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let expected = "Captured " + Date(timeIntervalSince1970: 1_700_000_000).formatted(date: .abbreviated, time: .shortened)
        XCTAssertEqual(row.value as? String, expected)
        app.terminate(); app.launchArguments = base; app.launch()
        XCTAssertTrue(row.waitForExistence(timeout: 20)); XCTAssertEqual(row.value as? String, expected)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Explicitly recovered older photo after relaunch"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.terminate(); app.launchArguments = base + ["--paper-preview-reset-media"]; app.launch(); app.terminate()
    }

    func testCleanupFailureNoticeRemainsOnSignedOutScreen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job-media", "--paper-preview-reset-media", "--paper-preview-media-cleanup-failure"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 20))
        let warning = app.descendants(matching: .any).matching(identifier: "login-media-cleanup-warning").firstMatch
        XCTAssertTrue(warning.exists); XCTAssertTrue(warning.label.contains("could not be removed"))
        XCTAssertFalse(warning.label.contains("actor")); XCTAssertFalse(warning.label.contains(".jpg"))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Signed-out cleanup failure notice"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.terminate(); app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job-media", "--paper-preview-reset-media"]; app.launch(); app.terminate()
    }

}
