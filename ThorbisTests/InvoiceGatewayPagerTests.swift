import XCTest
@testable import Thorbis

@MainActor
final class InvoiceGatewayPagerTests: XCTestCase {
    private let a = "00000000-0000-4000-8000-00000000000a"
    private let b = "00000000-0000-4000-8000-00000000000b"
    private func item(_ id: String) -> String {
        #"{"sourceId":"invoices","resultType":"invoice","entityId":"\#(id)","title":"Sample"}"#
    }

    func testOnePageAtATimeAndNeverClaimsCompleteSearch() async {
        let api = APIClient(session: URLProtocolFixture.session([
            .init(200, #"{"items":[\#(item(a))],"nextCursor":"next","completeness":"complete"}"#),
            .init(200, #"{"items":[\#(item(b))],"completeness":"complete"}"#),
        ]), baseURL: "https://app.thorbis.com")
        api.savedCopyScope = UUID().uuidString
        let pager = InvoiceGatewayPager(api: api)
        await pager.start(customer: "Smith", isCurrent: { true })
        XCTAssertEqual(pager.items.map(\.entityId), [a])
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        XCTAssertTrue(pager.isPartial)
        await pager.loadNext(isCurrent: { true })
        XCTAssertEqual(pager.items.map(\.entityId), [a, b])
        XCTAssertEqual(URLProtocolFixture.recorded.count, 2)
        XCTAssertTrue(pager.isPartial, "The projection has not been qualified as exhaustive")
    }

    func testRepeatedCursorDoesNotPublishUnverifiedPage() async {
        let api = APIClient(session: URLProtocolFixture.session([
            .init(200, #"{"items":[\#(item(a))],"nextCursor":"next"}"#),
            .init(200, #"{"items":[\#(item(b))],"nextCursor":"next"}"#),
        ]), baseURL: "https://app.thorbis.com")
        api.savedCopyScope = UUID().uuidString
        let pager = InvoiceGatewayPager(api: api)
        await pager.start(customer: "Smith", isCurrent: { true })
        await pager.loadNext(isCurrent: { true })
        XCTAssertEqual(pager.items.map(\.entityId), [a])
        XCTAssertNotNil(pager.error)
        XCTAssertTrue(pager.isPartial)
    }

    func testRetiredSessionClearsRowsBeforeAnotherPage() async {
        let api = APIClient(session: URLProtocolFixture.session([
            .init(200, #"{"items":[\#(item(a))],"nextCursor":"next"}"#),
        ]), baseURL: "https://app.thorbis.com")
        api.savedCopyScope = UUID().uuidString
        let pager = InvoiceGatewayPager(api: api)
        await pager.start(customer: "Smith", isCurrent: { true })
        api.invalidateRequests()
        await pager.loadNext(isCurrent: { true })
        XCTAssertTrue(pager.items.isEmpty)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
    }

    func testCustomerInputCannotInjectSearchTokens() {
        XCTAssertEqual(InvoiceGatewayPager.customerQuery(#"Acme" type:job \ office"#),
                       #"type:invoice customer:"Acme\" type:job \\ office""#)
    }
}
