import XCTest
@testable import Thorbis

@MainActor
final class SetupWizardTests: XCTestCase {
    func testCSVReaderHandlesQuotesCommasAndLineBreaks() {
        let text = "Name,Phone,Notes\r\n\"Smith, Ann\",555-0100,\"Gate code \"\"42\"\"\nBack door\"\n,,\nBob,555-0101,\n"
        XCTAssertEqual(CSVReader.rows(text), [
            ["Name", "Phone", "Notes"],
            ["Smith, Ann", "555-0100", "Gate code \"42\"\nBack door"],
            ["Bob", "555-0101", ""],
        ])
    }

    func testMappingGuessesCommonExportHeaders() {
        let mapping = CustomerImportMapping.guess(["First Name", "Last Name", "Mobile Phone", "E-mail", "Street Address", "City", "State", "Zip Code", "Customer Notes"])
        XCTAssertNil(mapping.name)
        XCTAssertEqual(mapping.firstName, 0)
        XCTAssertEqual(mapping.lastName, 1)
        XCTAssertEqual(mapping.phone, 2)
        XCTAssertEqual(mapping.email, 3)
        XCTAssertEqual(mapping.address, 4)
        XCTAssertEqual(mapping.city, 5)
        XCTAssertEqual(mapping.state, 6)
        XCTAssertEqual(mapping.zip, 7)
        XCTAssertEqual(mapping.notes, 8)
        XCTAssertTrue(mapping.canImport)
        XCTAssertEqual(CustomerImportMapping.guess(["Customer Name", "Phone"]).name, 0)
        XCTAssertFalse(CustomerImportMapping.guess(["Phone", "Email"]).canImport)
    }

    func testRowsBecomeTheServerShape() throws {
        let mapping = CustomerImportMapping.guess(["First Name", "Last Name", "Phone", "Email", "Address", "City", "State", "Zip"])
        let row = try XCTUnwrap(CustomerImportRow.from(["Ann", "Smith", "555-0100; 555-0101", "", "1 Oak St", "Austin", "TX", "78701"], mapping: mapping))
        XCTAssertEqual(row, CustomerImportRow(name: "Ann Smith", phones: ["555-0100", "555-0101"], emails: nil,
                                              addresses: ["1 Oak St, Austin, TX 78701"], notes: nil))
        XCTAssertNil(CustomerImportRow.from(["", "", "555-0100"], mapping: mapping))
        let json = String(data: try JSONEncoder().encode(row), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("emails"))
    }

    func testTradesRoundTripInListOrder() {
        let picked = SetupTrades.parse("Plumbing, Solar, HVAC")
        XCTAssertEqual(picked, ["Plumbing", "Solar", "HVAC"])
        XCTAssertEqual(SetupTrades.join(picked), "HVAC, Plumbing, Solar")
        XCTAssertEqual(SetupTrades.parse(nil), [])
    }

    func testFormationDateKeepsTheCalendarDay() throws {
        let date = try XCTUnwrap(SetupDates.parse("2019-03-04"))
        XCTAssertEqual(SetupDates.format(date), "2019-03-04")
        XCTAssertNil(SetupDates.parse("March 2019"))
    }

    func testResumeIsRememberedPerCompany() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "setup-wizard-tests"))
        defaults.removePersistentDomain(forName: "setup-wizard-tests")
        SetupProgress.save(.services, organizationID: "org_a", defaults: defaults)
        XCTAssertEqual(SetupProgress.load("org_a", defaults: defaults), .services)
        XCTAssertNil(SetupProgress.load("org_b", defaults: defaults))
        XCTAssertNil(SetupProgress.load(nil, defaults: defaults))
        SetupProgress.saveSkipped([.team, .payments], organizationID: "org_a", defaults: defaults)
        XCTAssertEqual(SetupProgress.skipped("org_a", defaults: defaults), [.team, .payments])
        XCTAssertEqual(SetupProgress.skipped("org_b", defaults: defaults), [])
    }

    func testOnlyTheCompanyStepHasRequiredFacts() {
        XCTAssertEqual(SetupStep.company.required, ["legal_name", "primary_phone", "business_address"])
        XCTAssertTrue(SetupStep.allCases.filter { $0 != .company }.allSatisfy { $0.required.isEmpty })
        let all = Set(SetupStep.allCases.flatMap(\.facts))
        XCTAssertTrue(all.isSuperset(of: ["legal_name", "business_address", "primary_phone", "industry", "entity_type", "email_sender_address"]))
    }
}
