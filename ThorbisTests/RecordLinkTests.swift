import XCTest
@testable import Thorbis

final class RecordLinkTests: XCTestCase {
    private let id = "11111111-1111-4111-8111-111111111111"

    func testCustomEstimateAndInvoiceLinksRoundTrip() throws {
        for record in [RecordLink.customer(id), .estimate(id), .invoice(id)] {
            XCTAssertEqual(RecordLink(url: try XCTUnwrap(record.url)), record)
        }
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
