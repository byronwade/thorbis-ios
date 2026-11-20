import XCTest
@testable import Thorbis

final class EditCustomerTests: XCTestCase {
    private func record(name: String = "Danielle Marlowe", email: String? = "danielle@example.com",
                        phone: String? = "(916) 555-0148", address: String? = nil, referral: String? = nil,
                        preferred: String? = nil) -> CustomerRecord {
        CustomerRecord(id: "00000000-0000-4000-8000-000000000001", organizationId: "org", name: name, locationId: nil,
                       email: email, phone: phone, address: address, accountType: "residential", industry: nil,
                       referralSource: referral, website: nil, preferredContact: preferred, billingTerms: nil,
                       creditLimit: nil, taxExempt: nil, taxExemptId: nil, archived: false,
                       archiveCycleAuditId: nil, createdAt: "2022-03-01T00:00:00Z", updatedAt: "2026-10-01T00:00:00Z")
    }

    private func location(_ id: String = "l1", kind: String = "service", address: String = "412 Birchwood Ln",
                          notes: String? = "Gate code 4482#") -> ServiceLocationRecord {
        ServiceLocationRecord(id: id, organizationId: "org", customerId: "cust", label: "Home", kind: kind, address: address,
                              notes: notes, coordinates: FieldCoordinates(latitude: 38.5, longitude: -121.4),
                              gateCode: "4482", alarmCode: nil, dogOnSite: "Bella", parking: nil,
                              createdAt: "2026-10-01T00:00:00Z", updatedAt: "2026-10-01T00:00:00Z")
    }

    private func json(_ value: some Encodable) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any] ?? [:]
    }

    func testNoEditsSendNothing() throws {
        let draft = EditCustomerDraft(record: record(address: "412 Birchwood Ln"), locations: [location()])
        XCTAssertFalse(draft.hasChanges)
        XCTAssertTrue(draft.customerUpdate.isEmpty)
        XCTAssertTrue(try json(draft.customerUpdate).isEmpty)
        XCTAssertNil(draft.serviceLocationEdit)
        XCTAssertTrue(draft.billingSameAsService)
    }

    func testChangedAndClearedFieldsMapToTheUpdateBody() throws {
        var draft = EditCustomerDraft(record: record(referral: "Google", preferred: "phone"), locations: [])
        draft.name = "  Danielle Ruiz "
        draft.email = ""
        draft.referralSource = "Neighbor referral"
        draft.preferredContact = "sms"
        let body = try json(draft.customerUpdate)
        XCTAssertEqual(body["name"] as? String, "Danielle Ruiz")
        XCTAssertTrue(body["email"] is NSNull)
        XCTAssertEqual(body["referralSource"] as? String, "Neighbor referral")
        XCTAssertEqual(body["preferredContact"] as? String, "sms")
        XCTAssertNil(body["phone"])
        XCTAssertNil(body["address"])
    }

    func testClearingHowTheyFoundUsSendsNull() throws {
        var draft = EditCustomerDraft(record: record(referral: "Google"), locations: [])
        draft.referralSource = "   "
        XCTAssertTrue(try json(draft.customerUpdate)["referralSource"] is NSNull)
    }

    func testWithoutALocationTheServiceAddressIsTheCustomersAddress() throws {
        var draft = EditCustomerDraft(record: record(address: "412 Birchwood Ln"), locations: [])
        XCTAssertEqual(draft.serviceAddress, "412 Birchwood Ln")
        XCTAssertFalse(draft.offersBillingChoice)
        XCTAssertFalse(draft.holdsNotes)
        draft.serviceAddress = "9 Elm St"
        XCTAssertEqual(try json(draft.customerUpdate)["address"] as? String, "9 Elm St")
        XCTAssertNil(draft.serviceLocationEdit)
    }

    func testServiceLocationEditCarriesTheOtherSiteFieldsThrough() throws {
        let service = location()
        var draft = EditCustomerDraft(record: record(), locations: [service])
        draft.notes = "Prefers morning visits."
        let edit = try XCTUnwrap(draft.serviceLocationEdit)
        XCTAssertNil(edit.address)
        let body = try json(EditCustomerDraft.locationUpdate(edit, existing: service))
        XCTAssertEqual(body["notes"] as? String, "Prefers morning visits.")
        XCTAssertEqual(body["address"] as? String, "412 Birchwood Ln")
        XCTAssertEqual(body["gateCode"] as? String, "4482")
        XCTAssertEqual(body["dogOnSite"] as? String, "Bella")
        XCTAssertNotNil(body["coordinates"] as? [String: Any], "A notes-only edit keeps the map pin")
    }

    func testMovingTheServiceAddressDropsTheOldPin() throws {
        let service = location()
        var draft = EditCustomerDraft(record: record(), locations: [service])
        draft.serviceAddress = "9 Elm St"
        let edit = try XCTUnwrap(draft.serviceLocationEdit)
        let body = try json(EditCustomerDraft.locationUpdate(edit, existing: service))
        XCTAssertEqual(body["address"] as? String, "9 Elm St")
        XCTAssertTrue(body["coordinates"] is NSNull)
        XCTAssertEqual(body["notes"] as? String, "Gate code 4482#")
    }

    func testBillingFollowsTheServiceAddressWhenTheSame() throws {
        var draft = EditCustomerDraft(record: record(address: "412 Birchwood Ln"), locations: [location()])
        XCTAssertTrue(draft.billingSameAsService)
        draft.serviceAddress = "9 Elm St"
        XCTAssertEqual(try json(draft.customerUpdate)["address"] as? String, "9 Elm St")
    }

    func testEmptyBillingStaysEmptyWhenTheSame() throws {
        var draft = EditCustomerDraft(record: record(address: nil), locations: [location()])
        XCTAssertTrue(draft.billingSameAsService)
        draft.serviceAddress = "9 Elm St"
        XCTAssertNil(try json(draft.customerUpdate)["address"])
    }

    func testSeparateBillingAddressIsSaved() throws {
        var draft = EditCustomerDraft(record: record(address: nil), locations: [location()])
        draft.billingSameAsService = false
        draft.billingAddress = "PO Box 1180"
        XCTAssertEqual(try json(draft.customerUpdate)["address"] as? String, "PO Box 1180")
    }

    func testABillingLocationTakesTheBillingAddress() throws {
        let billing = location("b1", kind: "billing", address: "PO Box 1180", notes: nil)
        var draft = EditCustomerDraft(record: record(address: "Old"), locations: [location(), billing])
        XCTAssertFalse(draft.billingSameAsService)
        draft.billingAddress = "PO Box 2200"
        XCTAssertNil(try json(draft.customerUpdate)["address"], "The customer's own address is left alone")
        let edit = try XCTUnwrap(draft.billingLocationEdit)
        XCTAssertEqual(edit.id, "b1")
        XCTAssertEqual(edit.address, "PO Box 2200")
    }

    func testValidationNamesWhatIsMissing() {
        var draft = EditCustomerDraft(record: record(), locations: [location()])
        draft.name = " "
        draft.email = "danielle@"
        draft.serviceAddress = ""
        XCTAssertFalse(draft.isValid)
        XCTAssertNotNil(draft.nameError)
        XCTAssertNotNil(draft.emailError)
        XCTAssertEqual(draft.serviceAddressError, "Enter the service address.")
    }

    func testRebasedRecordMeansNothingLeftToSend() {
        var draft = EditCustomerDraft(record: record(), locations: [])
        draft.name = "Danielle Ruiz"
        XCTAssertTrue(draft.hasChanges)
        let saved = record(name: "Danielle Ruiz")
        XCTAssertFalse(draft.rebased(record: saved).hasChanges)
    }
}
