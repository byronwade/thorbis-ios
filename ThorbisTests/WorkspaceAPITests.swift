import XCTest
@testable import Thorbis

@MainActor
final class WorkspaceAPITests: XCTestCase {
    private let itemID = "11111111-1111-4111-8111-111111111111"

    func testStaffNoticeFeedRetainsUnreadUnknownAndHistoryCursor() async throws {
        let first = #"{"items":[{"id":"22222222-2222-4222-8222-222222222222","jobId":"33333333-3333-4333-8333-333333333333","title":"Job booked","meta":"Tomorrow","at":"2026-10-26T12:00:00Z","read":false}],"unreadState":"unknown","nextCursor":"22222222-2222-4222-8222-222222222222"}"#
        let second = #"{"items":[],"unreadState":"none"}"#
        let api = APIClient(session: URLProtocolFixture.session([.init(200, first), .init(200, second)]), baseURL: "https://app.thorbis.com")

        let page = try await api.staffNotices(limit: 25)
        let next = try await api.staffNotices(limit: 25, cursor: try XCTUnwrap(page.nextCursor))

        XCTAssertEqual(page.items.first?.title, "Job booked")
        XCTAssertEqual(page.unreadState, .unknown)
        XCTAssertEqual(next.unreadState, .none)
        let requests = URLProtocolFixture.recorded
        XCTAssertEqual(requests.map { $0.url?.path }, ["/v1/staff/notices", "/v1/staff/notices"])
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(requests[0].url), resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "limit" })?.value, "25")
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(requests[1].url), resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "cursor" })?.value, page.nextCursor)
    }

    func testStaffNoticeReadSweepPreservesOpaqueContinuation() async throws {
        let api = APIClient(session: URLProtocolFixture.session([.init(200, #"{"marked":4,"nextCursor":"opaque-sweep-token"}"#)]), baseURL: "https://app.thorbis.com")

        let result = try await api.markStaffNoticesRead(limit: 50, cursor: "prior-token")

        XCTAssertEqual(result.marked, 4)
        XCTAssertEqual(result.nextCursor, "opaque-sweep-token")
        let request = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(request.url?.path, "/v1/staff/notices/read")
        XCTAssertEqual(request.method, "POST")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: Any])
        XCTAssertEqual(body["limit"] as? Int, 50)
        XCTAssertEqual(body["cursor"] as? String, "prior-token")
    }

    func testRevenueReportUsesServerIntegerCentsAndTruncationFlag() async throws {
        let payload = #"{"freshness":"live","generatedAt":"2026-10-26T12:00:00Z","periodBasis":"utc-month","reportVersion":2,"months":[{"month":"2026-10","revenue":12345,"collected":2345}],"receivable":{"openInvoices":2,"balance":10000,"overdueInvoices":1,"overdueBalance":5000},"truncated":true}"#
        let api = APIClient(session: URLProtocolFixture.session([.init(200, payload)]), baseURL: "https://app.thorbis.com")

        let report = try await api.revenueReport()

        XCTAssertTrue(report.truncated)
        XCTAssertEqual(report.months.first?.revenue, 12345)
        XCTAssertEqual(report.receivable.balance, 10000)
        XCTAssertEqual(URLProtocolFixture.recorded.first?.url?.path, "/v1/reports/revenue")
    }

    func testPriceBookCollectionUsesGatedQueryAndTypedIntegerPrice() async throws {
        let payload = #"{"schemaVersion":1,"items":[{"id":"11111111-1111-4111-8111-111111111111","resourceId":"price_book_items","label":"Replace capacitor","subtitle":"material","fields":{"price_book_items.id":"11111111-1111-4111-8111-111111111111","price_book_items.current_revision":3,"price_book_items.description":"Replace capacitor","price_book_items.unit":"each","price_book_items.sell_price_amount":12500,"price_book_items.currency":"USD","price_book_items.tax_classification":"taxable","price_book_items.kind":"material"}}],"nextCursor":"11111111-1111-4111-8111-111111111111","planId":"plan","resourceId":"price_book_items","viewId":null,"purpose":"collection","localMode":"complete"}"#
        let api = APIClient(session: URLProtocolFixture.session([.init(200, payload)]), baseURL: "https://app.thorbis.com")

        let page = try await api.priceBookItems(limit: 50)

        XCTAssertEqual(page.items.first?.id, itemID)
        XCTAssertEqual(page.items.first?.sellPrice.amount, 12500)
        XCTAssertEqual(page.items.first?.revision, 3)
        XCTAssertEqual(page.nextCursor, itemID)
        let request = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(request.url?.path, "/v1/query")
        let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(query.first(where: { $0.name == "resourceId" })?.value, "price_book_items")
        XCTAssertEqual(query.first(where: { $0.name == "purpose" })?.value, "collection")
        XCTAssertEqual(query.first(where: { $0.name == "limit" })?.value, "50")
    }

    func testPriceBookDetailDecodesCurrentRevisionWithoutGuessing() async throws {
        let payload = #"{"item":{"id":"11111111-1111-4111-8111-111111111111","organizationId":"44444444-4444-4444-8444-444444444444","status":"active","currentRevision":3,"createdAt":"2026-10-26T00:00:00Z","updatedAt":"2026-10-26T00:00:00Z"},"revision":{"organizationId":"44444444-4444-4444-8444-444444444444","itemId":"11111111-1111-4111-8111-111111111111","revision":3,"description":"Replace capacitor","unit":"each","sellPrice":{"amount":12500,"currency":"USD"},"taxClassification":"taxable","kind":"material","createdAt":"2026-10-26T00:00:00Z"}}"#
        let api = APIClient(session: URLProtocolFixture.session([.init(200, payload)]), baseURL: "https://app.thorbis.com")

        let detail = try await api.priceBookItem(itemID)

        XCTAssertEqual(detail.item.currentRevision, detail.revision.revision)
        XCTAssertEqual(detail.revision.sellPrice.amount, 12500)
        XCTAssertEqual(URLProtocolFixture.recorded.first?.url?.path, "/v1/price-book/items/\(itemID)")
    }
}
