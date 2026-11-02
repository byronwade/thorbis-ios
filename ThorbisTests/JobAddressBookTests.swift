import XCTest
@testable import Thorbis

@MainActor
final class JobAddressBookTests: XCTestCase {
    private let organization = "00000000-0000-4000-8000-000000000002"
    private let early = "00000000-0000-4000-8000-000000000003"
    private let current = "00000000-0000-4000-8000-000000000009"
    private let site = "00000000-0000-4000-8000-000000000007"

    private func job(_ id: String, customer: String) -> Job {
        Job(id: id, customerId: customer, title: "Repair", status: "in_progress", createdAt: nil, updatedAt: nil,
            allowedTransitions: nil, locationId: site)
    }

    /// The iPad sidebar's "On now" card puts the job you're on first, so its street is read first
    /// even when the day has more customers than one pass reads (it used to go in customer-id order).
    func testPlacesAreReadInTheOrderGivenSoTheJobYoureOnLeadsWithItsStreet() async throws {
        let location = #"{"items":[{"id":"\#(site)","organizationId":"\#(organization)","customerId":"\#(current)","label":"Home","kind":"service","address":"412 Birchwood Ln, Springfield","createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}]}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(200, location)]), baseURL: "https://app.thorbis.com")
        let book = JobAddressBook()
        let onNow = job("00000000-0000-4000-8000-000000000101", customer: current)

        await book.load([onNow, job("00000000-0000-4000-8000-000000000102", customer: early)], api: client,
                        organizationID: organization, identity: "me", limit: 1)

        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        XCTAssertTrue(URLProtocolFixture.recorded.first?.url?.absoluteString.contains(current) ?? false,
                      URLProtocolFixture.recorded.first?.url?.absoluteString ?? "no request")
        XCTAssertEqual(book.street(onNow), "412 Birchwood Ln")
    }

    /// Starting work does not change id or locationId, so the sidebar's `.task` identity has to
    /// include the job you're on or a later stop keeps its title.
    func testSidebarPlaceLoadRestartsWhenTheJobYoureOnChanges() {
        let first = job("00000000-0000-4000-8000-000000000101", customer: early)
        let later = job("00000000-0000-4000-8000-000000000102", customer: current)
        let day = [first, later]
        let generation = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let before = TabletRoot.addressLoadTaskID(jobs: day, currentJobID: first.id, generation: generation)
        let after = TabletRoot.addressLoadTaskID(jobs: day, currentJobID: later.id, generation: generation)
        XCTAssertNotEqual(before, after)
        XCTAssertTrue(after.contains(later.id))
    }

    /// After the first pass has used its customer cap, a later load that leads with the job you
    /// just started still reads that street.
    func testASecondPassReadsTheJobYouJustStartedWhenItSatPastTheCap() async throws {
        let laterSite = "00000000-0000-4000-8000-000000000008"
        let firstPlace = #"{"items":[{"id":"\#(site)","organizationId":"\#(organization)","customerId":"\#(early)","label":"Home","kind":"service","address":"10 Oak St, Springfield","createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}]}"#
        let laterPlace = #"{"items":[{"id":"\#(laterSite)","organizationId":"\#(organization)","customerId":"\#(current)","label":"Home","kind":"service","address":"412 Birchwood Ln, Springfield","createdAt":"2026-10-26T12:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}]}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(200, firstPlace), .init(200, laterPlace)]),
                               baseURL: "https://app.thorbis.com")
        let book = JobAddressBook()
        let first = job("00000000-0000-4000-8000-000000000101", customer: early)
        var later = job("00000000-0000-4000-8000-000000000102", customer: current)
        later.locationId = laterSite

        await book.load([first, later], api: client, organizationID: organization, identity: "me", limit: 1)
        XCTAssertEqual(book.street(first), "10 Oak St")
        XCTAssertNil(book.street(later))

        await book.load([later, first], api: client, organizationID: organization, identity: "me", limit: 1)
        XCTAssertEqual(book.street(later), "412 Birchwood Ln")
    }
}
