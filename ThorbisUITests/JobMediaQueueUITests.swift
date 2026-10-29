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
}
