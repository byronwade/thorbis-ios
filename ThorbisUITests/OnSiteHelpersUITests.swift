import XCTest

/// "Mark arrived?" near the address, "Copy a past estimate", and "Maintenance plan" in a job's +.
@MainActor
final class OnSiteHelpersUITests: XCTestCase {
    private func launch(_ screen: String, _ extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", screen] + extra
        app.launch()
        return app
    }

    func testNearTheAddressTheJobOffersArrivedAndADismissStopsAsking() {
        let app = launch("job", ["--paper-preview-field-step", "driving", "--paper-preview-arrival-nudge"])
        let arrive = app.buttons["job-arrival-nudge-arrive"]
        XCTAssertTrue(arrive.waitForExistence(timeout: 20), "On the way and at the address: the offer shows")
        XCTAssertTrue(app.staticTexts["You\u{2019}re here. Mark arrived?"].exists)
        XCTAssertGreaterThanOrEqual(arrive.frame.height, 43.5)
        let dismiss = app.buttons["job-arrival-nudge-dismiss"]
        XCTAssertGreaterThanOrEqual(dismiss.frame.width, 43.5)
        dismiss.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: arrive)],
                                      timeout: 5), .completed)
    }

    func testAwayFromTheAddressNothingIsOffered() {
        let app = launch("job", ["--paper-preview-field-step", "driving"])
        XCTAssertTrue(app.staticTexts["job-title"].waitForExistence(timeout: 20) || app.buttons["Job actions"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["job-arrival-nudge-arrive"].waitForExistence(timeout: 3))
    }

    func testANewEstimateStartsFromAPastOne() {
        let app = launch("new-estimate")
        let copy = app.buttons["estimate-copy-past"]
        XCTAssertTrue(copy.waitForExistence(timeout: 20)); copy.tap()
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'estimate-copy-0'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10)); first.tap()
        let note = app.staticTexts["estimate-copied-note"]
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        XCTAssertTrue(note.label.hasPrefix("Check prices before sending."), note.label)
        XCTAssertFalse(copy.exists, "Offered only while the estimate has no items")
    }

    func testAJobsAddSheetOffersAPlanOnlyToANonMember() {
        let offered = launch("job-add", ["--paper-preview-not-a-member"])
        let row = offered.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Maintenance plan'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20)); row.tap()
        XCTAssertTrue(offered.staticTexts["Choose a plan"].waitForExistence(timeout: 10), "The same plan picker as the customer page")
        offered.terminate()

        let member = launch("job-add")
        XCTAssertTrue(member.otherElements["job-add-sheet"].waitForExistence(timeout: 20) || member.buttons["job-add-close"].waitForExistence(timeout: 5))
        XCTAssertFalse(member.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Maintenance plan'")).firstMatch.exists)
    }
}
