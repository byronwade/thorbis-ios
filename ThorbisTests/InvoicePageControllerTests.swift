import XCTest
@testable import Thorbis

@MainActor
final class InvoicePageControllerTests: XCTestCase {
    private let a = "00000000-0000-4000-8000-00000000000b"
    private let b = "00000000-0000-4000-8000-00000000000a"
    private let org = "019f0000-0000-7000-8000-000000000001"
    private var sessionReplies: [URLProtocolFixture.Reply] { [
        .init(200, #"{"user":{"id":"019f0000-0000-7000-8000-000000000011","name":"Fixture","email":"fixture@example.invalid"},"session":{"userId":"019f0000-0000-7000-8000-000000000011","activeOrganizationId":"019f0000-0000-7000-8000-000000000001","expiresAt":"2099-10-27T12:00:00.000Z"}}"#),
        .init(200, #"[{"id":"019f0000-0000-7000-8000-000000000001","name":"Fixture"}]"#),
        .init(200, #"{"authority":{"actorId":"019f0000-0000-7000-8000-000000000011","organizationId":"019f0000-0000-7000-8000-000000000001","policyVersion":1,"generation":"fixture"},"capabilities":["invoice.view"],"resources":[],"views":[]}"#),
        .init(200, #"{"organizationId":"019f0000-0000-7000-8000-000000000001","evaluatedAt":"2026-10-26T12:00:00Z","features":{"invoicing":{"enabled":true,"released":true,"entitled":true}}}"#)
    ] }
    private func prepare(_ replies: [URLProtocolFixture.Reply]) async -> (APIClient, SessionController, InvoicePageController) {
        let api = APIClient(session: URLProtocolFixture.session(sessionReplies + replies), baseURL: "https://app.thorbis.com")
        let session = SessionController(api: api, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        session.onVerifiedIdentity = { actor, org in
            if let actor, let org { api.savedCopyScope = SavedCopies.scope(actorID: actor, organizationID: org) }
            else { api.savedCopyScope = nil }
        }
        await session.restore()
        return (api, session, InvoicePageController(api: api, session: session))
    }
    private func invoice(_ id: String, organization: String? = nil) -> String {
        #"{"id":"\#(id)","organizationId":"\#(organization ?? org)","customerId":"019f0000-0000-7000-8000-000000000004","createdByUserId":"019f0000-0000-7000-8000-000000000011","origin":"manual","sourceOperationKey":"fixture","status":"draft","lines":[],"linesRevision":1,"amountPaid":0,"currency":"USD","createdAt":"2026-10-26T11:00:00Z","updatedAt":"2026-10-26T12:00:00Z"}"#
    }
    func testFetchesNextPageOnlyOnRequest() async {
        let (_, _, pager) = await prepare([
            .init(200, #"{"items":[\#(invoice(a))],"nextCursor":"\#(a)"}"#),
            .init(200, #"{"items":[\#(invoice(b))]}"#)
        ])
        await pager.start(isCurrent: { true })
        XCTAssertEqual(pager.items.map(\.id), [a])
        XCTAssertTrue(pager.hasMore)
        XCTAssertFalse(pager.isExhausted)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 5)
        let firstQuery = URLComponents(url: URLProtocolFixture.recorded[4].url!, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(firstQuery?.first(where: { $0.name == "limit" })?.value, "50")
        await pager.loadNext(isCurrent: { true })
        XCTAssertEqual(pager.items.map(\.id), [a, b])
        XCTAssertFalse(pager.hasMore)
        XCTAssertTrue(pager.isExhausted)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 6)
        let nextQuery = URLComponents(url: URLProtocolFixture.recorded[5].url!, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(nextQuery?.first(where: { $0.name == "cursor" })?.value, a)
    }
    func testRepeatedCursorDoesNotPublishPage() async {
        let (_, _, pager) = await prepare([
            .init(200, #"{"items":[\#(invoice(a))],"nextCursor":"\#(a)"}"#),
            .init(200, #"{"items":[\#(invoice(b))],"nextCursor":"\#(a)"}"#)
        ])
        await pager.start(isCurrent: { true }); await pager.loadNext(isCurrent: { true })
        XCTAssertEqual(pager.items.map(\.id), [a]); XCTAssertNotNil(pager.error)
    }
    func testAscendingRowsAreRejected() async {
        let (_, _, pager) = await prepare([.init(200, #"{"items":[\#(invoice(b)),\#(invoice(a))]}"#)])
        await pager.start(isCurrent: { true })
        XCTAssertTrue(pager.items.isEmpty); XCTAssertNotNil(pager.error)
        XCTAssertFalse(pager.isExhausted)
    }
    func testForeignOrganizationDoesNotPublishPage() async {
        let (_, _, pager) = await prepare([.init(200, #"{"items":[\#(invoice(a, organization: "019f0000-0000-7000-8000-000000000099"))]}"#)])
        await pager.start(isCurrent: { true })
        XCTAssertTrue(pager.items.isEmpty); XCTAssertNotNil(pager.error)
    }
    func testDuplicateInvoiceDoesNotPublishPage() async {
        let (_, _, pager) = await prepare([
            .init(200, #"{"items":[\#(invoice(a))],"nextCursor":"\#(a)"}"#),
            .init(200, #"{"items":[\#(invoice(a.uppercased()))]}"#)
        ])
        await pager.start(isCurrent: { true }); await pager.loadNext(isCurrent: { true })
        XCTAssertEqual(pager.items.map(\.id), [a]); XCTAssertNotNil(pager.error)
    }
    func testAccessDenialRetiresPriorRows() async {
        let (_, _, pager) = await prepare([
            .init(200, #"{"items":[\#(invoice(a))],"nextCursor":"\#(a)"}"#),
            .init(403, #"{"title":"Denied","status":403}"#)
        ])
        await pager.start(isCurrent: { true }); await pager.loadNext(isCurrent: { true })
        XCTAssertTrue(pager.items.isEmpty); XCTAssertNotNil(pager.error)
    }
    func testTransientFailureKeepsRowsForRetry() async {
        let (_, _, pager) = await prepare([
            .init(200, #"{"items":[\#(invoice(a))],"nextCursor":"\#(a)"}"#),
            .init(503, #"{"title":"Unavailable","status":503}"#),
            .init(200, #"{"items":[\#(invoice(b))]}"#)
        ])
        await pager.start(isCurrent: { true }); await pager.loadNext(isCurrent: { true })
        XCTAssertEqual(pager.items.map(\.id), [a]); XCTAssertNotNil(pager.error)
        await pager.loadNext(isCurrent: { true })
        XCTAssertEqual(pager.items.map(\.id), [a, b]); XCTAssertNil(pager.error)
    }
    func testIdentityChangeImmediatelyRetiresRows() async {
        let (api, _, pager) = await prepare([.init(200, #"{"items":[\#(invoice(a))]}"#)])
        await pager.start(isCurrent: { true }); XCTAssertEqual(pager.items.count, 1)
        api.savedCopyScope = nil
        XCTAssertTrue(pager.items.isEmpty)
    }
    func testLatePageCannotPublishAfterSessionInvalidation() async throws {
        let gate = URLProtocolFixture.Gate(); defer { gate.release() }
        let (api, _, pager) = await prepare([.init(200, #"{"items":[\#(invoice(a))]}"#, gate: gate)])
        let task = Task { await pager.start(isCurrent: { true }) }
        for _ in 0..<100 where URLProtocolFixture.recorded.count < 5 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 5)
        api.invalidateRequests(); gate.release(); await task.value
        XCTAssertTrue(pager.items.isEmpty)
    }
    func testOnlineReaderNeverUsesSavedPageAfterAuthorityChanged() async throws {
        let oldPage = #"{"items":[\#(invoice(a))]}"#
        let narrowed = #"{"authority":{"actorId":"019f0000-0000-7000-8000-000000000011","organizationId":"019f0000-0000-7000-8000-000000000001","policyVersion":2,"generation":"narrowed"},"capabilities":["invoice.view"],"resources":[],"views":[]}"#
        let (api, session, pager) = await prepare([sessionReplies[0], .init(200, narrowed), sessionReplies[3], .init(503, #"{"title":"Unavailable","status":503}"#)])
        let scope = try XCTUnwrap(api.savedCopyScope)
        let key = SavedCopies.key(origin: try XCTUnwrap(api.normalizedOrigin), path: "/v1/invoices", query: [URLQueryItem(name: "limit", value: "50")])
        SavedCopyStore.shared.write(Data(oldPage.utf8), scope: scope, key: key)
        for _ in 0..<100 where SavedCopyStore.shared.read(scope: scope, key: key)?.data != Data(oldPage.utf8) { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(SavedCopyStore.shared.read(scope: scope, key: key)?.data, Data(oldPage.utf8))
        let oldRevision = session.authorityRevision
        await session.revalidate()
        XCTAssertNotEqual(session.authorityRevision, oldRevision)
        api.knownOffline = true
        await pager.start(isCurrent: { true })
        XCTAssertTrue(pager.items.isEmpty, "An unscoped old saved page is not proof of current invoice access")
        XCTAssertNotNil(pager.error)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 8)
        XCTAssertEqual(URLProtocolFixture.recorded.last?.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(URLProtocolFixture.recorded.last?.header("Cache-Control"), "no-cache")
    }
    func testOwnerContextChangeImmediatelyRetiresRows() async {
        let (_, _, pager) = await prepare([.init(200, #"{"items":[\#(invoice(a))]}"#)])
        await pager.start(isCurrent: { true }); XCTAssertEqual(pager.items.count, 1)
        pager.ownerContextChanged(isCurrent: { false })
        XCTAssertTrue(pager.items.isEmpty)
    }
}
