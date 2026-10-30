import XCTest

@MainActor
final class InboxVisualUITests: XCTestCase {
    func testGroupedNoticesRetainUnreadFilterAndOpenTheirJob() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "inbox", "--paper-preview-inbox-day-groups", "-thorbis.appearance", "dark"]
        app.launch()
        XCTAssertTrue(app.staticTexts.matching(identifier: "inbox-day-heading").firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Date unavailable"].waitForExistence(timeout: 10))
        let invalid = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "A visit with an invalid date")).firstMatch
        XCTAssertTrue(invalid.exists)
        XCTAssertFalse(invalid.label.contains("not-a-date"))
        let notice = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "A visit is ready", "Unread")).firstMatch
        XCTAssertTrue(notice.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Inbox grouped by received date"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Unread"].tap()
        XCTAssertTrue(notice.exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "A visit was updated")).firstMatch.exists)
        notice.tap()
        XCTAssertTrue(app.buttons["job-customer-link"].waitForExistence(timeout: 15))
    }

    func testUnreadNoticeNamesItsStateAndOpensItsJob() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "inbox"]
        app.launch()
        let notice = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "A visit is ready", "Unread")).firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 20))
        notice.tap()
        XCTAssertTrue(app.buttons["job-customer-link"].waitForExistence(timeout: 15))
    }
}
