import XCTest

@MainActor
final class PaymentsLedgerUITests: XCTestCase {
    func testPagedLedgerFiltersAndOpensInvoice() throws {
        guard !XCUIApplication().usesTabletLayout else { throw XCTSkip("Phone navigation") }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "payments-ledger", "--paper-preview-role", "office"]
        app.launch()
        let first = app.buttons["payment-row-00000000-0000-4000-8000-000000009501"]
        let second = app.buttons["payment-row-00000000-0000-4000-8000-000000009502"]
        XCTAssertTrue(first.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(first.label.contains("Partially refunded"), first.label)
        let more = app.buttons["payments-load-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5)); more.tap()
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        let filter = app.buttons["payments-filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5)); filter.tap()
        let cash = app.buttons["Cash & check"]
        XCTAssertTrue(cash.waitForExistence(timeout: 5)); cash.tap()
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        XCTAssertFalse(first.exists, "A filtered ledger must not retain another filter's row")
        second.tap()
        XCTAssertTrue(app.staticTexts["invoice-detail-title"].waitForExistence(timeout: 10), app.debugDescription)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Payments invoice handoff"; shot.lifetime = .keepAlways; add(shot)
    }
}
