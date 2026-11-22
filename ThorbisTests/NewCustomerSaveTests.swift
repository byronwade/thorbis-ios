import XCTest
@testable import Thorbis

/// New customer and Book a job's new caller: the customer, then their address as their first
/// property. The customer is kept when only the property fails, and a retry never makes a second
/// customer or, after an answer that never came, a second property.
@MainActor
final class NewCustomerSaveTests: XCTestCase {
    private let organization = "00000000-0000-4000-8000-000000000002"
    private let customerID = "00000000-0000-4000-8000-000000000412"
    private let home = "00000000-0000-4000-8000-000000007001"

    private var created: String {
        #"{"id":"\#(customerID)","name":"Danielle Marlowe","archived":false,"createdAt":"2026-11-22T12:00:00Z","address":"412 Birchwood Ln"}"#
    }

    private var property: String {
        #"{"id":"\#(home)","organizationId":"\#(organization)","customerId":"\#(customerID)","label":"Home","kind":"service","address":"412 Birchwood Ln","createdAt":"2026-11-22T12:00:00Z","updatedAt":"2026-11-22T12:00:00Z"}"#
    }

    private let request = NewCustomerRequest(name: "Danielle Marlowe", phone: "(916) 555-0142",
                                             address: "412 Birchwood Ln", accountType: "residential")

    private func client(_ replies: [URLProtocolFixture.Reply]) -> APIClient {
        APIClient(session: URLProtocolFixture.session(replies), baseURL: "https://app.thorbis.com")
    }

    private func body(_ index: Int) throws -> [String: String] {
        let data = try XCTUnwrap(URLProtocolFixture.recorded[index].body)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
    }

    private func calls() -> [String] {
        URLProtocolFixture.recorded.map { "\($0.method ?? "") \($0.url?.path ?? "")" }
    }

    func testTheAddressBecomesTheirFirstPropertyAfterTheCustomer() async throws {
        let api = client([.init(201, created), .init(201, property)])

        let outcome = try await NewCustomerSave.run(request, api: api)

        XCTAssertEqual(outcome.customer.id, customerID)
        XCTAssertNil(outcome.owed)
        XCTAssertEqual(calls(), ["POST /v1/customers", "POST /v1/customers/\(customerID)/locations"])
        XCTAssertEqual(try body(0)["address"], "412 Birchwood Ln", "The account keeps its own address too")
        XCTAssertEqual(try body(1), ["label": "Home", "kind": "service", "address": "412 Birchwood Ln"],
                       "customers.addLocation takes only the fields the web intake sends")
    }

    func testHowTheyFoundUsStillGoesWithTheCustomer() async throws {
        let api = client([.init(201, created), .init(201, property)])

        _ = try await NewCustomerSave.run(request, referralSource: "Yard sign", api: api)

        XCTAssertEqual(try body(0)["referralSource"], "Yard sign")
        XCTAssertEqual(calls().count, 2)
    }

    func testAResidentialAccountsPropertyIsHomeAndACommercialOnesIsSite() {
        XCTAssertEqual(NewCustomerSave.property(address: "412 Birchwood Ln", accountType: "residential")?.label, "Home")
        XCTAssertEqual(NewCustomerSave.property(address: "412 Birchwood Ln", accountType: nil)?.label, "Home")
        XCTAssertEqual(NewCustomerSave.property(address: "200 Main St", accountType: "commercial")?.label, "Site")
        XCTAssertEqual(NewCustomerSave.property(address: "  200 Main St ", accountType: "commercial")?.address, "200 Main St")
        XCTAssertEqual(NewCustomerSave.property(address: "200 Main St", accountType: "commercial")?.kind, "service")
        XCTAssertNil(NewCustomerSave.property(address: nil, accountType: "residential"))
        XCTAssertNil(NewCustomerSave.property(address: "   ", accountType: "residential"))
    }

    func testWithoutAnAddressOnlyTheCustomerIsMade() async throws {
        let api = client([.init(201, created)])

        let outcome = try await NewCustomerSave.run(NewCustomerRequest(name: "Danielle Marlowe"), api: api)

        XCTAssertNil(outcome.owed)
        XCTAssertEqual(calls(), ["POST /v1/customers"])
    }

    func testARefusedCustomerIsNotSavedAndNoPropertyIsTried() async {
        let api = client([.init(400, #"{"title":"Invalid customer","status":400}"#)])

        do {
            _ = try await NewCustomerSave.run(request, api: api)
            XCTFail("A refused customer must not read as saved")
        } catch {}

        XCTAssertEqual(calls(), ["POST /v1/customers"])
    }

    func testAFailedPropertyKeepsTheCustomerSaysSoAndTryAgainAddsOnlyTheProperty() async throws {
        let api = client([.init(201, created), .init(503, #"{"title":"Unavailable","status":503}"#)])

        let outcome = try await NewCustomerSave.run(request, api: api)

        XCTAssertEqual(outcome.customer.id, customerID, "The customer is kept")
        let owed = try XCTUnwrap(outcome.owed)
        XCTAssertTrue(owed.uncertain, "A server failure may have made it")
        XCTAssertFalse(owed.refused)
        XCTAssertEqual(owed.notice, "Danielle Marlowe is saved, but their address wasn\u{2019}t added as a property. Tap Try again, or add it on their record.")

        // Try again: the server's list first (it was not made), then the property; never a second customer.
        let retry = client([.init(200, #"{"items":[]}"#), .init(201, property)])
        let again = try await NewCustomerSave.add(owed, api: retry)

        XCTAssertNil(again.owed)
        XCTAssertEqual(calls(), ["GET /v1/customers/\(customerID)/locations", "POST /v1/customers/\(customerID)/locations"])
    }

    func testAPropertyThatArrivedDespiteNoAnswerIsNotAddedTwice() async throws {
        let api = client([.init(201, created), URLProtocolFixture.timedOut])

        let outcome = try await NewCustomerSave.run(request, api: api)
        let owed = try XCTUnwrap(outcome.owed)
        XCTAssertTrue(owed.uncertain)

        let retry = client([.init(200, #"{"items":[\#(property)]}"#)])
        let again = try await NewCustomerSave.add(owed, api: retry)

        XCTAssertNil(again.owed)
        XCTAssertEqual(calls(), ["GET /v1/customers/\(customerID)/locations"], "The property already there is kept")
    }

    func testARoleThatCantAddPropertiesIsToldWhoCan() async throws {
        let api = client([.init(201, created), .init(403, #"{"title":"Forbidden","status":403}"#)])

        let outcome = try await NewCustomerSave.run(request, api: api)
        let owed = try XCTUnwrap(outcome.owed)

        XCTAssertTrue(owed.refused)
        XCTAssertFalse(owed.uncertain, "A refusal made nothing, so a retry doesn't need to look first")
        XCTAssertEqual(owed.notice, "Danielle Marlowe is saved, but your role can\u{2019}t add their address as a property. Ask your office to add it.")
    }

    func testAPropertyThatNeverLeftThePhoneIsTriedAgainWithoutLookingFirst() async throws {
        let api = client([.init(201, created), URLProtocolFixture.offline])

        let outcome = try await NewCustomerSave.run(request, api: api)
        let owed = try XCTUnwrap(outcome.owed)
        XCTAssertFalse(owed.uncertain)

        let retry = client([.init(201, property)])
        let again = try await NewCustomerSave.add(owed, api: retry)

        XCTAssertNil(again.owed)
        XCTAssertEqual(calls(), ["POST /v1/customers/\(customerID)/locations"])
    }
}
