import XCTest
@testable import Thorbis

@MainActor
final class PriceBookCatalogTests: XCTestCase {
    func testRefreshLoadsAllPagesAndDeduplicatesIDs() async throws {
        let org = UUID().uuidString.lowercased()
        defer { removeOwnCache(org) }
        let api = client([.init(200, try page([(1,"Drain inspection"),(2,"Valve replacement")], cursor: id(9000))),
                          .init(200, try page([(2,"Valve replacement"),(3,"Later page service")]))])
        let catalog = PriceBookCatalog()
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: UUID(), force: true)
        XCTAssertEqual(catalog.items.map(\.id), [id(1),id(2),id(3)])
        XCTAssertEqual(catalog.index.search("later page").map(\.id), [id(3)])
        XCTAssertEqual(URLProtocolFixture.recorded.count, 2)
        XCTAssertFalse(catalog.loading)
        XCTAssertNil(catalog.error)
    }

    func testLatePriorOrganizationRefreshCannotReplaceCurrentCatalog() async throws {
        let a = UUID().uuidString.lowercased(), b = UUID().uuidString.lowercased()
        defer { removeOwnCache(a); removeOwnCache(b) }
        let gate = URLProtocolFixture.Gate()
        defer { gate.release() }
        let api = client([.init(200, try page([(1,"Old workspace")]), gate: gate), .init(200, try page([(2,"Current workspace")]))])
        let catalog = PriceBookCatalog()
        let old = Task { await catalog.refresh(api: api, organizationID: a, sessionGeneration: UUID(), force: true) }
        try await waitForRequests(1)
        await catalog.refresh(api: api, organizationID: b, sessionGeneration: UUID(), force: true)
        gate.release()
        await old.value
        XCTAssertEqual(catalog.organizationID, b)
        XCTAssertEqual(catalog.items.map(\.id), [id(2)])
        XCTAssertFalse(catalog.loading)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL(a).path))
    }

    func testLatePriorGenerationRefreshCannotReplaceCurrentCatalogForSameOrganization() async throws {
        let org = UUID().uuidString.lowercased()
        defer { removeOwnCache(org) }
        let gate = URLProtocolFixture.Gate()
        defer { gate.release() }
        let api = client([.init(200, try page([(1,"Previous session")]), gate: gate), .init(200, try page([(2,"Current session")]))])
        let catalog = PriceBookCatalog()
        let old = Task { await catalog.refresh(api: api, organizationID: org, sessionGeneration: UUID(), force: true) }
        try await waitForRequests(1)
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: UUID(), force: true)
        gate.release()
        await old.value
        XCTAssertEqual(catalog.items.map(\.id), [id(2)])
        XCTAssertFalse(catalog.loading)
        XCTAssertNil(catalog.error)
        let saved = try Data(contentsOf: cacheURL(org))
        XCTAssertTrue(String(decoding: saved, as: UTF8.self).contains("Current session"))
        XCTAssertFalse(String(decoding: saved, as: UTF8.self).contains("Previous session"))
    }

    func testReturningToSameScopeCannotPublishAnOlderRequest() async throws {
        let a = UUID().uuidString.lowercased(), b = UUID().uuidString.lowercased(), generation = UUID()
        defer { removeOwnCache(a); removeOwnCache(b) }
        let gate = URLProtocolFixture.Gate()
        defer { gate.release() }
        let api = client([.init(200, try page([(1,"First A read")]), gate: gate),
                          .init(200, try page([(2,"B read")])), .init(200, try page([(3,"New A read")]))])
        let catalog = PriceBookCatalog()
        let old = Task { await catalog.refresh(api: api, organizationID: a, sessionGeneration: generation, force: true) }
        try await waitForRequests(1)
        await catalog.refresh(api: api, organizationID: b, sessionGeneration: generation, force: true)
        await catalog.refresh(api: api, organizationID: a, sessionGeneration: generation, force: true)
        gate.release()
        await old.value
        XCTAssertEqual(catalog.items.map(\.id), [id(3)])
        XCTAssertFalse(catalog.loading)
        XCTAssertTrue(String(decoding: try Data(contentsOf: cacheURL(a)), as: UTF8.self).contains("New A read"))
    }

    func testLeavingWorkspaceWhileReadIsPendingCannotResurrectItsCatalog() async throws {
        let org = UUID().uuidString.lowercased()
        defer { removeOwnCache(org) }
        let gate = URLProtocolFixture.Gate()
        defer { gate.release() }
        let api = client([.init(200, try page([(1,"Left workspace")]), gate: gate)])
        let catalog = PriceBookCatalog()
        let old = Task { await catalog.refresh(api: api, organizationID: org, sessionGeneration: UUID(), force: true) }
        try await waitForRequests(1)
        await catalog.refresh(api: api, organizationID: nil, sessionGeneration: UUID(), force: true)
        gate.release()
        await old.value
        XCTAssertNil(catalog.organizationID)
        XCTAssertTrue(catalog.items.isEmpty)
        XCTAssertFalse(catalog.loading)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL(org).path))
    }

    func testUnfinishedRefreshKeepsTheLastCompleteCatalogAndCache() async throws {
        let org = UUID().uuidString.lowercased()
        defer { removeOwnCache(org) }
        var replies: [URLProtocolFixture.Reply] = [.init(200, try page([(1,"Previous complete catalog")]))]
        for n in 0..<PriceBookCatalog.maximumPages {
            replies.append(.init(200, try page([(100+n,"Unfinished page \(n)")], cursor: id(9000+n))))
        }
        let api = client(replies)
        let catalog = PriceBookCatalog()
        let generation = UUID()
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, force: true)
        let saved = try Data(contentsOf: cacheURL(org))
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, force: true)
        XCTAssertEqual(catalog.items.map(\.id), [id(1)])
        XCTAssertNotNil(catalog.error)
        XCTAssertFalse(catalog.loading)
        XCTAssertEqual(try Data(contentsOf: cacheURL(org)), saved)
    }

    private func client(_ replies: [URLProtocolFixture.Reply]) -> APIClient {
        APIClient(session: URLProtocolFixture.session(replies), baseURL: "https://app.thorbis.com")
    }
    private func id(_ n: Int) -> String { String(format: "00000000-0000-4000-8000-%012d", n) }
    private func page(_ rows: [(Int,String)], cursor: String? = nil) throws -> String {
        let items: [[String: Any]] = rows.map { n, title in
            let uuid = id(n)
            return ["id": uuid, "resourceId": "price_book_items", "label": title,
                    "fields": ["price_book_items.id": uuid, "price_book_items.current_revision": 4,
                               "price_book_items.description": title, "price_book_items.unit": "flat",
                               "price_book_items.sell_price_amount": 10000, "price_book_items.currency": "USD",
                               "price_book_items.tax_classification": "taxable", "price_book_items.kind": "service"]]
        }
        let value: [String: Any] = ["schemaVersion": 1, "resourceId": "price_book_items", "purpose": "collection",
                                   "localMode": "complete", "items": items, "nextCursor": cursor as Any? ?? NSNull(),
                                   "planId": "test", "viewId": NSNull()]
        return String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
    }
    private func waitForRequests(_ count: Int) async throws {
        for _ in 0..<300 {
            if URLProtocolFixture.recorded.count >= count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Expected request count \(count), got \(URLProtocolFixture.recorded.count)")
    }
    private func cacheURL(_ org: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PriceBook", isDirectory: true).appendingPathComponent("\(org).json")
    }
    private func removeOwnCache(_ org: String) { try? FileManager.default.removeItem(at: cacheURL(org)) }
}
