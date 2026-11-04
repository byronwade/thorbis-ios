import XCTest
@testable import Thorbis

@MainActor
final class InvoiceGatewayPagerTests: XCTestCase {
    private let a = "00000000-0000-4000-8000-00000000000a"
    private let b = "00000000-0000-4000-8000-00000000000b"
    private let actor = "019f0000-0000-7000-8000-000000000011"
    private let org = "019f0000-0000-7000-8000-000000000001"
    private var sessionReplies: [URLProtocolFixture.Reply] {
        [
            .init(200, #"{"user":{"id":"019f0000-0000-7000-8000-000000000011","name":"Fixture","email":"fixture@example.invalid"},"session":{"userId":"019f0000-0000-7000-8000-000000000011","activeOrganizationId":"019f0000-0000-7000-8000-000000000001","expiresAt":"2099-10-27T12:00:00.000Z"}}"#),
            .init(200, #"[{"id":"019f0000-0000-7000-8000-000000000001","name":"Fixture"}]"#),
            .init(200, #"{"authority":{"actorId":"019f0000-0000-7000-8000-000000000011","organizationId":"019f0000-0000-7000-8000-000000000001","policyVersion":1,"generation":"fixture"},"capabilities":["invoice.view","customer.view"],"resources":[],"views":[]}"#),
            .init(200, #"{"organizationId":"019f0000-0000-7000-8000-000000000001","evaluatedAt":"2026-10-26T12:00:00Z","features":{"invoicing":{"enabled":true,"released":true,"entitled":true},"core_crm":{"enabled":true,"released":true,"entitled":true}}}"#),
        ]
    }
    private func prepare(_ replies: [URLProtocolFixture.Reply]) async -> (APIClient, SessionController, InvoiceGatewayPager) {
        let api = APIClient(session: URLProtocolFixture.session(sessionReplies + replies), baseURL: "https://app.thorbis.com")
        let session = SessionController(api: api, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        session.onVerifiedIdentity = { actor, org in
            if let actor, let org { api.savedCopyScope = SavedCopies.scope(actorID: actor, organizationID: org) }
            else { api.savedCopyScope = nil }
        }
        await session.restore()
        return (api, session, InvoiceGatewayPager(api: api, session: session))
    }
    private func item(_ id: String) -> String {
        #"{"sourceId":"invoices","resultType":"invoice","entityId":"\#(id)","title":"Sample"}"#
    }

    func testOnePageAtATimeAndNeverClaimsCompleteSearch() async {
        let (api, _, pager) = await prepare([
            .init(200, #"{"items":[\#(item(a))],"nextCursor":"next","completeness":"complete"}"#),
            .init(200, #"{"items":[\#(item(b))],"completeness":"complete"}"#),
        ])
        await pager.start(customer: "Smith", isCurrent: { true })
        XCTAssertEqual(pager.items.map(\.entityId), [a])
        XCTAssertEqual(URLProtocolFixture.recorded.count, 5)
        XCTAssertTrue(pager.isPartial)
        await pager.loadNext(isCurrent: { true })
        XCTAssertEqual(pager.items.map(\.entityId), [a, b])
        XCTAssertEqual(URLProtocolFixture.recorded.count, 6)
        XCTAssertTrue(pager.isPartial, "The projection has not been qualified as exhaustive")
    }

    func testRepeatedCursorDoesNotPublishUnverifiedPage() async {
        let (api, _, pager) = await prepare([
            .init(200, #"{"items":[\#(item(a))],"nextCursor":"next"}"#),
            .init(200, #"{"items":[\#(item(b))],"nextCursor":"next"}"#),
        ])
        await pager.start(customer: "Smith", isCurrent: { true })
        await pager.loadNext(isCurrent: { true })
        XCTAssertEqual(pager.items.map(\.entityId), [a])
        XCTAssertNotNil(pager.error)
        XCTAssertTrue(pager.isPartial)
    }

    func testRetiredSessionClearsRowsBeforeAnotherPage() async {
        let (api, _, pager) = await prepare([
            .init(200, #"{"items":[\#(item(a))],"nextCursor":"next"}"#),
        ])
        await pager.start(customer: "Smith", isCurrent: { true })
        api.invalidateRequests()
        await pager.loadNext(isCurrent: { true })
        XCTAssertTrue(pager.items.isEmpty)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 5)
    }

    func testSavedCopyIdentityChangeImmediatelyRetiresVisibleRows() async {
        let (api, _, pager) = await prepare([.init(200, #"{"items":[\#(item(a))]}"#)])
        await pager.start(customer: "Smith", isCurrent: { true })
        XCTAssertEqual(pager.items.count, 1)
        api.savedCopyScope = nil
        XCTAssertTrue(pager.items.isEmpty)
    }

    func testAuthorityRefreshImmediatelyRetiresVisibleRows() async {
        let revoked = #"{"authority":{"actorId":"019f0000-0000-7000-8000-000000000011","organizationId":"019f0000-0000-7000-8000-000000000001","policyVersion":1,"generation":"fixture"},"capabilities":["customer.view"],"resources":[],"views":[]}"#
        let (_, session, pager) = await prepare([
            .init(200, #"{"items":[\#(item(a))]}"#), sessionReplies[0], .init(200, revoked), sessionReplies[3]
        ])
        await pager.start(customer: "Smith", isCurrent: { true })
        XCTAssertEqual(pager.items.count, 1)
        await session.revalidate()
        XCTAssertTrue(pager.items.isEmpty)
    }

    func testOpeningHitRequiresLiveResourceAuthorization() async {
        let (_, _, pager) = await prepare([
            .init(200, #"{"items":[\#(item(a))]}"#), .init(403, #"{"title":"Denied","status":403}"#)
        ])
        await pager.start(customer: "Smith", isCurrent: { true })
        let opened = await pager.authorizedInvoice(id: a, isCurrent: { true })
        XCTAssertNil(opened)
        XCTAssertEqual(URLProtocolFixture.recorded.last?.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(URLProtocolFixture.recorded.last?.header("Cache-Control"), "no-cache")
        XCTAssertTrue(pager.items.isEmpty, "A denied resource must retire stale search rows")
    }

    func testUnsupportedQuoteAndUTF16LengthRemainPartialWithoutNetwork() async {
        let (_, _, pager) = await prepare([])
        await pager.start(customer: "\"Smith\"", isCurrent: { true })
        XCTAssertNotNil(pager.error)
        XCTAssertTrue(pager.isPartial)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 4)
        await pager.start(customer: String(repeating: "😀", count: 65), isCurrent: { true })
        XCTAssertNotNil(pager.error)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 4)
    }

    func testPhraseAtUTF16LimitCanRequestOnePage() async {
        let (_, _, pager) = await prepare([.init(200, #"{"items":[]}"#)])
        await pager.start(customer: String(repeating: "😀", count: 64), isCurrent: { true })
        XCTAssertNil(pager.error)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 5)
        XCTAssertTrue(pager.isPartial)
    }

    func testCustomerInputCannotInjectSearchTokens() {
        XCTAssertEqual(InvoiceGatewayPager.customerQuery(#"Acme" type:job \ office"#),
                       #"type:invoice customer:"Acme\" type:job \\ office""#)
    }
}
