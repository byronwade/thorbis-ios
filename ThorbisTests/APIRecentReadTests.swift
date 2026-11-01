import XCTest
@testable import Thorbis

/// The 10-second repeat-read reuse must never answer a read that decides money, a signature or a price.
@MainActor
final class APIRecentReadTests: XCTestCase {
    func testMoneySignatureAndPriceReadsAreNeverReused() {
        for path in ["/v1/invoices/x", "/v1/invoices/x/payments", "/v1/estimates/x", "/v1/estimates/x/revisions/1",
                     "/v1/jobs/x/estimates", "/v1/jobs/x/invoices", "/v1/jobs/x/closeout", "/v1/public/document-actions/t",
                     "/v1/organization/merchant-readiness", "/v1/organization/permission-overrides/current"] {
            XCTAssertFalse(APIClient.reusesRecentRead(path), path)
        }
        XCTAssertFalse(APIClient.reusesRecentRead("/v1/query", query: [URLQueryItem(name: "resourceId", value: "price_book_items")]))
    }

    func testPlainJobAndCustomerReadsStillReuse() {
        XCTAssertTrue(APIClient.reusesRecentRead("/v1/jobs/x"))
        XCTAssertTrue(APIClient.reusesRecentRead("/v1/customers/x/locations"))
    }
}
