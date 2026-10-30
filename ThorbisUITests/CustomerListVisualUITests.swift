import XCTest

@MainActor
final class CustomerListVisualUITests: XCTestCase {
    func testCustomerRowNamesItsJobStatusAndOpensTheCustomer() {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "customers"]
        app.launch()

        let customer = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Danielle Marlowe", "Dispatched")).firstMatch
        XCTAssertTrue(customer.waitForExistence(timeout: 20))
        customer.tap()
        XCTAssertTrue(app.buttons["customer-next-visit"].waitForExistence(timeout: 10))
    }
}
