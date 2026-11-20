import XCTest

@MainActor
final class InboxVisualUITests: XCTestCase {
    func testRecentNoticesRetainUnreadFilterAndOpenTheirJob() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "inbox", "--paper-preview-inbox-day-groups", "-thorbis.appearance", "dark"]
        app.launch()
        XCTAssertTrue(app.staticTexts.matching(identifier: "inbox-day-heading").firstMatch.waitForExistence(timeout: 20))
        // Paper 49N: one "Recent" card; each row carries its own day, and a bad date shows none.
        XCTAssertEqual(app.staticTexts.matching(identifier: "inbox-day-heading").firstMatch.label, "Recent")
        let invalid = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "A visit with an invalid date")).firstMatch
        XCTAssertTrue(invalid.exists)
        XCTAssertFalse(invalid.label.contains("not-a-date"))
        let notice = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "A visit is ready", "Unread")).firstMatch
        XCTAssertTrue(notice.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Inbox grouped by received date"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        // Unread is a chip in the one row under the search field.
        let unreadOnly = app.buttons["inbox-filter-unread"]
        XCTAssertTrue(unreadOnly.waitForExistence(timeout: 5))
        unreadOnly.tap()
        XCTAssertTrue(unreadOnly.isSelected)
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
