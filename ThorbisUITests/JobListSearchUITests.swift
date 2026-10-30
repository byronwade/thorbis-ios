import XCTest

/// One search (the bar's), one create (the bar's + menu), and Schedule straight from a row.
@MainActor
final class JobListSearchUITests: XCTestCase {
    func testBarSearchFindsJobsAndClosingRestoresTheBoard() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "jobs"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Kitchen sink backup — Petrov"].waitForExistence(timeout: 30))
        // The list keeps no search field of its own.
        XCTAssertFalse(app.textFields["Search title or job number"].exists)
        app.buttons["bottom-bar-search"].tap()
        let field = app.textFields["Jobs, customers, invoices"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.typeText("Kitchen")
        let results = app.otherElements["bar-search-results"]
        XCTAssertTrue(results.waitForExistence(timeout: 10))
        XCTAssertTrue(results.staticTexts["Kitchen sink backup — Petrov"].waitForExistence(timeout: 10))
        XCTAssertFalse(results.staticTexts["AC not cooling"].exists)
        app.buttons["Close search"].tap()
        XCTAssertTrue(app.staticTexts["AC not cooling"].waitForExistence(timeout: 10))
        app.buttons["Filter jobs"].tap()
        XCTAssertTrue(app.staticTexts["Ordering"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Filters"].exists)
    }

    func testPlusOpensCreateMenuAndNewJobStartsWithCustomer() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "jobs"]
        app.launch()
        let create = app.buttons["bottom-bar-create"]
        XCTAssertTrue(create.waitForExistence(timeout: 30))
        XCTAssertEqual(create.label, "Create")
        create.tap()
        let newJob = app.buttons["New job"]
        XCTAssertTrue(newJob.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["New estimate"].exists)
        XCTAssertTrue(app.buttons["New customer"].exists)
        newJob.tap()
        let customer = app.buttons["Customer: Choose a customer"]
        XCTAssertTrue(customer.waitForExistence(timeout: 10))
        let title = app.textFields["Job title"]
        XCTAssertTrue(title.exists)
        // Customer comes before what the job is.
        XCTAssertLessThan(customer.frame.minY, title.frame.minY)
        XCTAssertTrue(app.buttons["Create job"].exists)
        XCTAssertFalse(app.buttons["Create job"].isEnabled)
    }

    func testUnscheduledRowOpensScheduleSheetDirectly() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "schedule-unscheduled"]
        app.launch()
        let row = app.buttons["schedule-row-00000000-0000-4000-8000-000000002232"]
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        XCTAssertEqual(row.label, "Schedule Garbage disposal jammed — Alvarez")
        row.tap()
        XCTAssertTrue(app.buttons["Save schedule"].waitForExistence(timeout: 10))
    }
}
