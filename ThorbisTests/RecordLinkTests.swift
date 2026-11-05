import XCTest
@testable import Thorbis

final class RecordLinkTests: XCTestCase {
    private let id = "11111111-1111-4111-8111-111111111111"

    func testCustomEstimateAndInvoiceLinksRoundTrip() throws {
        for record in [RecordLink.customer(id), .estimate(id), .invoice(id)] {
            XCTAssertEqual(RecordLink(url: try XCTUnwrap(record.url)), record)
        }
    }

    @MainActor func testFavoriteRoutesAreInternalAndRetainFinancialCapabilities() {
        let scope = ScopedRecordFavorites.Scope(actorID: "actor", organizationID: "org", origin: "https://app.thorbis.com",
            sessionGeneration: UUID(), authorityRevision: UUID(), apiGeneration: UUID(), savedCopyRevision: UUID())
        let estimate = RecordLink.favoriteEstimate(id, scope)
        let invoice = RecordLink.favoriteInvoice(id, scope)
        XCTAssertNil(estimate.url)
        XCTAssertNil(invoice.url)
        XCTAssertEqual(estimate.access.capability, "estimate.view")
        XCTAssertEqual(invoice.access.capability, "invoice.view")
        XCTAssertNotEqual(estimate, .favoriteEstimate(id, .init(actorID: "actor", organizationID: "org", origin: "https://app.thorbis.com",
            sessionGeneration: UUID(), authorityRevision: scope.authorityRevision, apiGeneration: scope.apiGeneration, savedCopyRevision: scope.savedCopyRevision)))
    }

    func testOnlyThorbisSchemeAndRealIdsOpen() throws {
        XCTAssertNil(RecordLink(url: try XCTUnwrap(URL(string: "https://customer/\(id)"))))
        XCTAssertNil(RecordLink(url: try XCTUnwrap(URL(string: "thorbis://customer/not-an-id"))))
        XCTAssertNil(RecordLink(url: try XCTUnwrap(URL(string: "thorbis://payout/\(id)"))))
        XCTAssertNil(RecordLink(url: try XCTUnwrap(URL(string: "thorbis://job/\(id)"))), "jobs stay with JobActivityLink")
    }

    func testPushPayloadNamesOneRecord() {
        XCTAssertEqual(RecordLink(push: ["invoiceId": id]), .invoice(id))
        XCTAssertEqual(RecordLink(push: ["estimateId": id]), .estimate(id))
        XCTAssertNil(RecordLink(push: ["invoiceId": "x"]))
        XCTAssertNil(RecordLink(push: [:]))
    }
}
