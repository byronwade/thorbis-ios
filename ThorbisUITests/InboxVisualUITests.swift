import XCTest

@MainActor
final class InboxVisualUITests: XCTestCase {
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
