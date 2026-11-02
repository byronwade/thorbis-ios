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
}
