import XCTest

/// Text on a job opens the customer's conversation in the Inbox (web threadForPhone), not Messages.
@MainActor
final class CommsTextHandoffUITests: XCTestCase {
    func testTextReopensUnsavedConversationWhenStorageFails() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-inbox-storage-failure"]
        app.launch()
        let text = app.buttons["job-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 30), app.debugDescription)
        for _ in 0..<6 where !text.isHittable { app.swipeUp() }
        for _ in 0..<12 where !text.isHittable { app.swipeDown() }
        XCTAssertTrue(text.isHittable); text.tap()
        let field = app.descendants(matching: .any)["inbox-text-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 15)); field.tap(); field.typeText("Keep this text")
        XCTAssertTrue(app.staticTexts["inbox-text-storage-error"].waitForExistence(timeout: 10))
        app.buttons["inbox-text-close"].tap()
        XCTAssertTrue(text.waitForExistence(timeout: 10)); text.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 15), "The inbox must reopen the retained draft instead of handing off to Messages")
        XCTAssertTrue((field.value as? String)?.contains("Keep this text") == true)
    }

    func testFailedArchiveKeepsJobTextDraftVisible() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job", "--paper-preview-inbox-storage-failure"]
        app.launch()
        let text = app.buttons["job-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 30), app.debugDescription)
        for _ in 0..<6 where !text.isHittable { app.swipeUp() }
        for _ in 0..<12 where !text.isHittable { app.swipeDown() }
        XCTAssertTrue(text.isHittable); text.tap()
        let field = app.descendants(matching: .any)["inbox-text-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 15)); field.tap(); field.typeText("Keep this text")
        XCTAssertTrue(app.staticTexts["inbox-text-storage-error"].waitForExistence(timeout: 10))
        app.buttons["inbox-thread-menu"].tap()
        let archive = app.buttons["Archive"]
        XCTAssertTrue(archive.waitForExistence(timeout: 10)); archive.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 10), "A failed archive must leave the draft open")
        XCTAssertTrue((field.value as? String)?.contains("Keep this text") == true)
    }

    func testTextOnAJobOpensTheInboxConversation() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "job"]
        app.launch()
        let text = app.buttons["job-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 30), app.debugDescription)
        // The job screen can still be settling when Text first exists (it was found above the
        // fold and a swipe up then scrolled it away), so give it a moment, then look both ways.
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: text)
        _ = XCTWaiter.wait(for: [hittable], timeout: 5)
        for _ in 0..<6 where !(text.exists && text.isHittable) { app.swipeUp() }
        for _ in 0..<12 where !(text.exists && text.isHittable) { app.swipeDown() }
        XCTAssertTrue(text.isHittable, app.debugDescription)
        text.tap()
        let field = app.descendants(matching: .any)["inbox-text-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Drafts stay on this device"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Text from a job opens the Inbox"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
