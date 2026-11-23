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

    /// A role that may add a property and look at the customer's places (every built-in role that
    /// may add customers).
    private let allowed = NewCustomerSave.Access(canAdd: true, canCheck: true)

    private func run(_ request: NewCustomerRequest, referralSource: String? = nil, api: APIClient,
                     access: NewCustomerSave.Access? = nil) async throws -> NewCustomerSave.Outcome {
        try await NewCustomerSave.run(request, referralSource: referralSource, api: api, access: access ?? allowed,
                                      currentAuthority: { true })
    }

    private func add(_ owed: NewCustomerSave.Owed, api: APIClient, access: NewCustomerSave.Access? = nil) async throws -> NewCustomerSave.Outcome {
        try await NewCustomerSave.add(owed, api: api, access: access ?? allowed, currentAuthority: { true })
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

        let outcome = try await run(request, api: api)

        XCTAssertEqual(outcome.customer.id, customerID)
        XCTAssertNil(outcome.owed)
        XCTAssertEqual(calls(), ["POST /v1/customers", "POST /v1/customers/\(customerID)/locations"])
        XCTAssertEqual(try body(0)["address"], "412 Birchwood Ln", "The account keeps its own address too")
        XCTAssertEqual(try body(1), ["label": "Home", "kind": "service", "address": "412 Birchwood Ln"],
                       "customers.addLocation takes only the fields the web intake sends")
    }

    func testHowTheyFoundUsStillGoesWithTheCustomer() async throws {
        let api = client([.init(201, created), .init(201, property)])

        _ = try await run(request, referralSource: "Yard sign", api: api)

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

        let outcome = try await run(NewCustomerRequest(name: "Danielle Marlowe"), api: api)

        XCTAssertNil(outcome.owed)
        XCTAssertEqual(calls(), ["POST /v1/customers"])
    }

    func testARefusedCustomerIsNotSavedAndNoPropertyIsTried() async {
        let api = client([.init(400, #"{"title":"Invalid customer","status":400}"#)])

        do {
            _ = try await run(request, api: api)
            XCTFail("A refused customer must not read as saved")
        } catch {}

        XCTAssertEqual(calls(), ["POST /v1/customers"])
    }

    func testAFailedPropertyKeepsTheCustomerSaysSoAndTryAgainAddsOnlyTheProperty() async throws {
        let api = client([.init(201, created), .init(503, #"{"title":"Unavailable","status":503}"#)])

        let outcome = try await run(request, api: api)

        XCTAssertEqual(outcome.customer.id, customerID, "The customer is kept")
        let owed = try XCTUnwrap(outcome.owed)
        XCTAssertTrue(owed.uncertain, "A server failure may have made it")
        XCTAssertEqual(owed.reason, .failed)
        XCTAssertTrue(owed.retryable)
        XCTAssertEqual(owed.notice, "Danielle Marlowe is saved, but their address wasn\u{2019}t added as a property. Tap Try again, or add it on their record.")

        // Try again: the server's list first (it was not made), then the property; never a second customer.
        let retry = client([.init(200, #"{"items":[]}"#), .init(201, property)])
        let again = try await add(owed, api: retry)

        XCTAssertNil(again.owed)
        XCTAssertEqual(calls(), ["GET /v1/customers/\(customerID)/locations", "POST /v1/customers/\(customerID)/locations"])
        // The look is the server's own answer, never a copy saved on this phone before the lost try.
        XCTAssertEqual(URLProtocolFixture.recorded.first?.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(URLProtocolFixture.recorded.first?.header("Cache-Control"), "no-cache")
    }

    func testAPropertyThatArrivedDespiteNoAnswerIsNotAddedTwice() async throws {
        let api = client([.init(201, created), URLProtocolFixture.timedOut])

        let outcome = try await run(request, api: api)
        let owed = try XCTUnwrap(outcome.owed)
        XCTAssertTrue(owed.uncertain)

        let retry = client([.init(200, #"{"items":[\#(property)]}"#)])
        let again = try await add(owed, api: retry)

        XCTAssertNil(again.owed)
        XCTAssertEqual(calls(), ["GET /v1/customers/\(customerID)/locations"], "The property already there is kept")
    }

    func testARoleThatCantAddPropertiesIsToldWhoCan() async throws {
        let api = client([.init(201, created), .init(403, #"{"title":"Forbidden","status":403}"#)])

        let outcome = try await run(request, api: api)
        let owed = try XCTUnwrap(outcome.owed)

        XCTAssertEqual(owed.reason, .refused)
        XCTAssertFalse(owed.retryable, "Trying again can't help, so the sheets stop offering it")
        XCTAssertFalse(owed.uncertain, "A refusal made nothing, so a retry doesn't need to look first")
        XCTAssertEqual(owed.notice, "Danielle Marlowe is saved, but your role can\u{2019}t add their address as a property. Ask your office to add it.")

        // A press after the refusal sends nothing again and keeps saying so.
        let retry = client([.init(201, property)])
        let again = try await add(owed, api: retry)
        XCTAssertTrue(calls().isEmpty, "A refused property is never sent again")
        XCTAssertEqual(again.owed?.reason, .refused)
    }

    func testARoleWithoutCustomerEditIsNeverSentTheProperty() async throws {
        // customers.create needs customer.create; customers.addLocation needs customer.edit.
        let api = client([.init(201, created), .init(201, property)])

        let outcome = try await run(request, api: api, access: NewCustomerSave.Access(canAdd: false, canCheck: true))

        XCTAssertEqual(outcome.customer.id, customerID, "The customer is kept")
        XCTAssertEqual(calls(), ["POST /v1/customers"], "The server would refuse it, so it is not sent")
        XCTAssertEqual(outcome.owed?.reason, .refused)
        XCTAssertEqual(outcome.owed?.retryable, false)
    }

    func testAfterNoAnswerARoleThatCantLookIsNotSentASecondCopy() async throws {
        let api = client([.init(201, created), URLProtocolFixture.timedOut])
        let outcome = try await run(request, api: api)
        let owed = try XCTUnwrap(outcome.owed)
        XCTAssertTrue(owed.uncertain)

        let retry = client([.init(201, property)])
        let again = try await add(owed, api: retry, access: NewCustomerSave.Access(canAdd: true, canCheck: false))

        XCTAssertTrue(calls().isEmpty, "Without a look the property could be added twice")
        let unchecked = try XCTUnwrap(again.owed)
        XCTAssertEqual(unchecked.reason, .unchecked)
        XCTAssertFalse(unchecked.retryable)
        XCTAssertEqual(unchecked.notice, "Danielle Marlowe is saved, but their address may not have been added as a property. Ask your office to check their record.")
    }

    func testALookThatFailsSendsNothingAndCanBeTriedAgain() async throws {
        let api = client([.init(201, created), URLProtocolFixture.timedOut])
        let outcome = try await run(request, api: api)
        let owed = try XCTUnwrap(outcome.owed)

        let retry = client([URLProtocolFixture.offline])
        let again = try await add(owed, api: retry)

        XCTAssertEqual(calls(), ["GET /v1/customers/\(customerID)/locations"], "Not known whether it is there, so nothing is added")
        XCTAssertEqual(again.owed?.uncertain, true)
        XCTAssertEqual(again.owed?.retryable, true)
    }

    func testAPropertyThatNeverLeftThePhoneIsTriedAgainWithoutLookingFirst() async throws {
        let api = client([.init(201, created), URLProtocolFixture.offline])

        let outcome = try await run(request, api: api)
        let owed = try XCTUnwrap(outcome.owed)
        XCTAssertFalse(owed.uncertain)

        let retry = client([.init(201, property)])
        let again = try await add(owed, api: retry)

        XCTAssertNil(again.owed)
        XCTAssertEqual(calls(), ["POST /v1/customers/\(customerID)/locations"])
    }

    // MARK: Book job never picks the property just made as the job's site

    private func place(_ id: String) -> ServiceLocationRecord {
        ServiceLocationRecord(id: id, organizationId: organization, customerId: customerID, label: "Home", kind: "service",
                              address: "412 Birchwood Ln", notes: nil, coordinates: nil, gateCode: nil, alarmCode: nil,
                              dogOnSite: nil, parking: nil, createdAt: "2026-11-22T12:00:00Z", updatedAt: "2026-11-22T12:00:00Z")
    }

    func testANewCustomersOnlyPropertyIsNotPickedForTheirJob() {
        XCTAssertNil(NewJobSheet.chosenLocation(nil, among: [place(home)], justCreated: true),
                     "No location id goes onto the job for the property just made")
        XCTAssertEqual(NewJobSheet.chosenLocation(nil, among: [place(home)], justCreated: false), home,
                       "An existing customer's one place is still picked")
    }

    func testAPlaceHandedInStaysOnlyWhileItIsTheCustomers() {
        let other = "00000000-0000-4000-8000-000000007002"
        XCTAssertEqual(NewJobSheet.chosenLocation(other, among: [place(home), place(other)], justCreated: false), other)
        XCTAssertNil(NewJobSheet.chosenLocation(other, among: [place(home)], justCreated: true))
        XCTAssertNil(NewJobSheet.chosenLocation(nil, among: [place(home), place(other)], justCreated: false), "With several the CSR picks")
    }
}
