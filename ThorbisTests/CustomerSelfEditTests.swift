import XCTest
@testable import Thorbis

final class CustomerSelfEditTests: XCTestCase {
    private func record(name: String = "Dana Customer", email: String? = "dana@example.com", phone: String? = "555-0100",
                        address: String? = "1 Main St", preferred: String? = nil) -> CustomerRecord {
        CustomerRecord(id: "00000000-0000-4000-8000-000000000001", organizationId: "org", name: name, locationId: nil,
                       email: email, phone: phone, address: address, accountType: "residential", industry: nil,
                       referralSource: nil, website: nil, preferredContact: preferred, billingTerms: "net_30",
                       creditLimit: 50000, taxExempt: false, taxExemptId: nil, archived: false,
                       archiveCycleAuditId: nil, createdAt: "2026-10-01T00:00:00Z", updatedAt: "2026-10-01T00:00:00Z")
    }

    private func contact(_ id: String = "c1", name: String = "Sam", phone: String? = "555-0101") -> CustomerContactRecord {
        CustomerContactRecord(id: id, organizationId: "org", customerId: "cust", name: name, role: nil, email: nil,
                              phone: phone, primary: false, createdAt: "2026-10-01T00:00:00Z", updatedAt: "2026-10-01T00:00:00Z")
    }

    private func location(_ id: String = "l1", kind: String = "service", address: String = "1 Main St") -> ServiceLocationRecord {
        ServiceLocationRecord(id: id, organizationId: "org", customerId: "cust", label: "Home", kind: kind, address: address,
                              notes: "Side gate", coordinates: nil, gateCode: "1234", alarmCode: nil, dogOnSite: nil,
                              parking: nil, createdAt: "2026-10-01T00:00:00Z", updatedAt: "2026-10-01T00:00:00Z")
    }

    private func json(_ value: some Encodable) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any] ?? [:]
    }

    func testNoEditsMeansNothingToSave() {
        let draft = CustomerSelfEditDraft(record: record(), contacts: [contact()], locations: [location()], smsConsent: nil)
        XCTAssertFalse(draft.hasChanges)
        XCTAssertTrue(draft.customerUpdate.isEmpty)
        XCTAssertTrue(draft.contactUpdates.isEmpty)
        XCTAssertNil(draft.newContact)
        XCTAssertTrue(draft.locationChanges.isEmpty)
    }

    func testOnlyChangedCustomerFieldsAreSentAndClearedOnesAreNull() throws {
        var draft = CustomerSelfEditDraft(record: record(), contacts: [], locations: [], smsConsent: nil)
        draft.email = "  dana.new@example.com "
        draft.phone = ""
        draft.preferredContact = "sms"
        let body = try json(draft.customerUpdate)
        XCTAssertEqual(body["email"] as? String, "dana.new@example.com")
        XCTAssertTrue(body["phone"] is NSNull)
        XCTAssertEqual(body["preferredContact"] as? String, "sms")
        XCTAssertNil(body["name"])
        XCTAssertNil(body["address"])
        // Billing terms, credit limit and tax fields are never part of the customer's edit.
        XCTAssertEqual(Set(body.keys), ["email", "phone", "preferredContact"])
    }

    func testOnlyServiceAddressesAreOfferedAndChangesAreTrimmed() {
        var draft = CustomerSelfEditDraft(record: record(), contacts: [],
                                          locations: [location("l1"), location("b1", kind: "billing")], smsConsent: nil)
        XCTAssertEqual(draft.locations.map(\.id), ["l1"])
        draft.locations[0].address = " 2 Oak Ave "
        XCTAssertEqual(draft.locationChanges.first?.address, "2 Oak Ave")
        XCTAssertTrue(draft.changeSummary.contains("Home: 2 Oak Ave"))
    }

    func testContactEditsAndNewContact() throws {
        var draft = CustomerSelfEditDraft(record: record(), contacts: [contact()], locations: [], smsConsent: nil)
        draft.contacts[0].phone = "555-0199"
        draft.newContactName = "Alex"
        draft.newContactEmail = "alex@example.com"
        let update = try XCTUnwrap(draft.contactUpdates.first)
        let body = try json(update.request)
        XCTAssertEqual(body["phone"] as? String, "555-0199")
        XCTAssertNil(body["name"])
        XCTAssertEqual(draft.newContact?.name, "Alex")
        XCTAssertEqual(draft.newContact?.email, "alex@example.com")
    }

    func testValidationBlocksEmptyNameAndBadEmail() {
        var draft = CustomerSelfEditDraft(record: record(), contacts: [], locations: [], smsConsent: nil)
        draft.name = "  "
        draft.email = "not-an-email"
        XCTAssertNotNil(draft.nameError)
        XCTAssertNotNil(draft.emailError)
        XCTAssertFalse(draft.isValid)
        draft.name = "Dana"
        draft.email = ""
        XCTAssertTrue(draft.isValid)
    }

    func testTextsChangeOnlyWhenTheAnswerMoves() {
        let consent = CustomerSmsConsent(decision: "grant", version: "v1", recordedAt: "2026-10-01T00:00:00Z")
        var draft = CustomerSelfEditDraft(record: record(), contacts: [], locations: [], smsConsent: consent)
        XCTAssertNil(draft.textsChange)
        draft.allowsTexts = false
        XCTAssertEqual(draft.textsChange, false)
        XCTAssertTrue(draft.changeSummary.contains("Asked to stop job texts"))
    }

    func testRebasingAfterTheCustomerSaveLeavesNothingToRepeat() {
        var draft = CustomerSelfEditDraft(record: record(), contacts: [], locations: [], smsConsent: nil)
        draft.name = "Dana Q. Customer"
        let rebased = draft.rebased(record: record(name: "Dana Q. Customer"))
        XCTAssertTrue(rebased.customerUpdate.isEmpty)
    }
}
