import XCTest
@testable import Thorbis

/// A job that records no site of its own is shown at the customer's only address on file, said
/// with its caveat: the only service location, else the customer's own address. Never a guess
/// between several, and never another customer's or workspace's place.
@MainActor
final class JobFallbackAddressTests: XCTestCase {
    private let organization = "00000000-0000-4000-8000-000000000002"
    private let customer = "00000000-0000-4000-8000-000000000412"
    private let other = "00000000-0000-4000-8000-000000000413"
    private let home = "00000000-0000-4000-8000-000000007001"

    private func location(_ id: String, kind: String = "service", address: String = "412 Birchwood Ln, Springfield",
                          customer: String? = nil, organization: String? = nil,
                          coordinates: FieldCoordinates? = nil) -> ServiceLocationRecord {
        ServiceLocationRecord(id: id, organizationId: organization ?? self.organization, customerId: customer ?? self.customer,
                              label: "Home", kind: kind, address: address, notes: nil, coordinates: coordinates,
                              gateCode: nil, alarmCode: nil, dogOnSite: nil, parking: nil,
                              createdAt: "2026-11-22T12:00:00Z", updatedAt: "2026-11-22T12:00:00Z")
    }

    private func fallback(locationID: String? = nil, locations: [ServiceLocationRecord]?, customerAddress: String?) -> JobFallbackAddress? {
        JobFallbackAddress.make(locationID: locationID, customerID: customer, organizationID: organization,
                                locations: locations, customerAddress: customerAddress)
    }

    private func destination(_ url: URL?) -> String? {
        url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "daddr" }?.value }
    }

    func testWithNoServiceLocationTheCustomersOwnAddressIsTheStreetAndTheDirections() throws {
        let place = try XCTUnwrap(fallback(locations: [], customerAddress: "  731 Cassia Way, Springfield  "))
        XCTAssertEqual(place.address, "731 Cassia Way, Springfield")
        XCTAssertNil(place.coordinates)
        XCTAssertEqual(place.street, "731 Cassia Way")
        XCTAssertEqual(destination(place.directions), "731 Cassia Way, Springfield")
        XCTAssertEqual(JobFallbackAddress.caveat, "From the customer's only address on file")
    }

    func testABillingLocationIsNotAServiceLocation() {
        let billing = location(home, kind: "billing", address: "PO Box 12, Springfield")
        XCTAssertEqual(fallback(locations: [billing], customerAddress: "731 Cassia Way")?.address, "731 Cassia Way")
    }

    func testTheOnlyServiceLocationStandsInWithItsPin() {
        let pin = FieldCoordinates(latitude: 38.5, longitude: -121.4)
        let place = fallback(locations: [location(home, coordinates: pin), location("00000000-0000-4000-8000-000000007002", kind: "billing")],
                             customerAddress: "731 Cassia Way")
        XCTAssertEqual(place?.address, "412 Birchwood Ln, Springfield")
        XCTAssertEqual(place?.coordinates, pin)
        XCTAssertEqual(place?.street, "412 Birchwood Ln")
        XCTAssertEqual(destination(place?.directions), "38.5,-121.4")
    }

    func testSeveralServiceLocationsAreNeverGuessedBetween() {
        let two = [location(home), location("00000000-0000-4000-8000-000000007002", address: "88 Larch Ave")]
        XCTAssertNil(fallback(locations: two, customerAddress: "731 Cassia Way"))
    }

    func testAJobWithItsOwnSiteUnreadLocationsOrNoAddressGetNothing() {
        XCTAssertNil(fallback(locationID: home, locations: [], customerAddress: "731 Cassia Way"), "A job with its own site keeps it")
        XCTAssertNil(fallback(locations: nil, customerAddress: "731 Cassia Way"), "Unread locations might hold several places")
        XCTAssertNil(fallback(locations: [], customerAddress: nil))
        XCTAssertNil(fallback(locations: [], customerAddress: "   "))
    }

    func testAnotherCustomersOrWorkspacesPlaceIsIgnored() {
        let foreign = [location(home, address: "1 Elsewhere St", customer: other),
                       location("00000000-0000-4000-8000-000000007002", address: "2 Elsewhere St", organization: "00000000-0000-4000-8000-000000000003")]
        XCTAssertEqual(fallback(locations: foreign, customerAddress: "731 Cassia Way")?.address, "731 Cassia Way")
    }

    // MARK: The next stop's saved place

    func testANextStopWithoutASiteTakesTheFallbackAndSaysSo() {
        var stop = NextStopPlace(jobID: "job", organizationID: organization, customerID: customer, locationID: nil)
        stop.setPlace(from: [], customerAddress: "731 Cassia Way, Springfield")
        XCTAssertEqual(stop.firstLine, "731 Cassia Way")
        XCTAssertEqual(stop.caveat, JobFallbackAddress.caveat)
        XCTAssertEqual(destination(stop.directions), "731 Cassia Way, Springfield")

        // Read again once the customer has several places: nothing is guessed, and nothing is said.
        stop.setPlace(from: [location(home), location("00000000-0000-4000-8000-000000007002", address: "88 Larch Ave")],
                      customerAddress: "731 Cassia Way")
        XCTAssertNil(stop.address)
        XCTAssertNil(stop.caveat)
        XCTAssertNil(stop.directions)
    }

    func testANextStopWithItsOwnSiteNeverSaysTheCaveat() {
        var stop = NextStopPlace(jobID: "job", organizationID: organization, customerID: customer, locationID: home)
        stop.setPlace(from: [location(home)], customerAddress: "731 Cassia Way")
        XCTAssertEqual(stop.firstLine, "412 Birchwood Ln")
        XCTAssertNil(stop.caveat)
        stop.setPlace(from: [], customerAddress: "731 Cassia Way")
        XCTAssertNil(stop.address, "A job's own site is never replaced by the customer's address")
    }

    func testAStopSavedBeforeTheCaveatStillReads() throws {
        let json = #"{"jobID":"job","organizationID":"\#(organization)","customerID":"\#(customer)","address":"412 Birchwood Ln"}"#
        let stop = try JSONDecoder().decode(NextStopPlace.self, from: Data(json.utf8))
        XCTAssertEqual(stop.firstLine, "412 Birchwood Ln")
        XCTAssertNil(stop.caveat)
    }

    // MARK: Rows (JobAddressBook)

    private func job(_ id: String, locationID: String? = nil) -> Job {
        Job(id: id, customerId: customer, title: "AC recheck", status: "scheduled", createdAt: nil, updatedAt: nil,
            allowedTransitions: nil, locationId: locationID)
    }

    func testRowsWithoutASiteShowTheCustomersAddressWhereTheScreenAsks() async {
        let client = APIClient(session: URLProtocolFixture.session([.init(200, #"{"items":[]}"#)]), baseURL: "https://app.thorbis.com")
        let book = JobAddressBook()
        let row = job("00000000-0000-4000-8000-000000002224")

        await book.load([row], api: client, organizationID: organization, identity: "me",
                        customerAddresses: [customer: "731 Cassia Way, Springfield"])

        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        XCTAssertEqual(URLProtocolFixture.recorded.first?.url?.path, "/v1/customers/\(customer)/locations")
        XCTAssertEqual(book.street(row), "731 Cassia Way")
        XCTAssertEqual(book.caveat(row), JobFallbackAddress.caveat)
        XCTAssertEqual(destination(book.directions(row)), "731 Cassia Way, Springfield")
    }

    func testRowsWithASiteKeepItAndNeverSayTheCaveat() async {
        let page = #"{"items":[{"id":"\#(home)","organizationId":"\#(organization)","customerId":"\#(customer)","label":"Home","kind":"service","address":"412 Birchwood Ln, Springfield","createdAt":"2026-11-22T12:00:00Z","updatedAt":"2026-11-22T12:00:00Z"}]}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(200, page)]), baseURL: "https://app.thorbis.com")
        let book = JobAddressBook()
        let sited = job("00000000-0000-4000-8000-000000002214", locationID: home)

        await book.load([sited], api: client, organizationID: organization, identity: "me",
                        customerAddresses: [customer: "731 Cassia Way"])

        XCTAssertEqual(book.street(sited), "412 Birchwood Ln")
        XCTAssertNil(book.caveat(sited))
    }

    func testScreensThatDoNotAskReadNothingForRowsWithoutASite() async {
        let client = APIClient(session: URLProtocolFixture.session([.init(200, #"{"items":[]}"#)]), baseURL: "https://app.thorbis.com")
        let book = JobAddressBook()
        let row = job("00000000-0000-4000-8000-000000002224")

        await book.load([row], api: client, organizationID: organization, identity: "me")

        XCTAssertTrue(URLProtocolFixture.recorded.isEmpty)
        XCTAssertNil(book.street(row))
        XCTAssertNil(book.directions(row))
    }
}
