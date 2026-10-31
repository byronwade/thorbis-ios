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
        // #186: the bar's field reads "Street, name, phone or number"; result rows lead with the street, the job title follows.
        let field = app.textFields["Street, name, phone or number"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.typeText("Kitchen")
        let results = app.otherElements["bar-search-results"]
        XCTAssertTrue(results.waitForExistence(timeout: 10))
        XCTAssertTrue(results.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Kitchen sink backup")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(results.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "AC not cooling")).firstMatch.exists)
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
        let create = app.buttons["header-create"]
        XCTAssertTrue(create.waitForExistence(timeout: 30))
        XCTAssertEqual(create.label, "Create")
        create.tap()
        let newJob = app.buttons["New job"]
        XCTAssertTrue(newJob.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["New estimate"].exists)
        XCTAssertTrue(app.buttons["New customer"].exists)
        newJob.tap()
        // #176: New job is the Book a job sheet. Who's calling comes first and nothing books without them.
        let customer = app.descendants(matching: .any)["book-job-caller"]
        XCTAssertTrue(customer.waitForExistence(timeout: 10))
        let commit = app.buttons["book-job-commit"]
        XCTAssertTrue(commit.exists)
        XCTAssertLessThan(customer.frame.minY, commit.frame.minY)
        XCTAssertFalse(commit.isEnabled)
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
