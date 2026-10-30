import XCTest
@testable import Thorbis

final class PriceBookSearchTests: XCTestCase {
    private func item(_ id: Int, _ description: String, kind: String = "material", unit: String = "each",
                      cents: Int = 10_000, archived: Bool = false, currency: String = "USD") -> PriceBookListItem {
        PriceBookListItem(id: String(format: "00000000-0000-4000-8000-%012d", id), description: description,
                          unit: unit, kind: kind, taxClassification: "taxable",
                          sellPrice: FieldMoney(amount: cents, currency: currency), revision: 1,
                          archivedAt: archived ? "2026-10-01T00:00:00Z" : nil)
    }

    private lazy var catalog: [PriceBookListItem] = [
        item(1, "Capacitor, 45/5 MFD dual run"),
        item(2, "Capacitor, 35/5 MFD dual run"),
        item(3, "Hard start kit with capacitor"),
        item(4, "Condenser coil cleaning", kind: "service"),
        item(5, "Licensed technician labor", kind: "labor", unit: "hour"),
        item(6, "Refrigerant R-410A", unit: "lb"),
        item(7, "Old capacitor", archived: true),
        item(8, "Capacitor priced in euros", currency: "EUR"),
        item(9, "Cap", kind: "service"),
    ]

    private func search(_ query: String, kind: PriceBookKindFilter = .all,
                        usage: [String: PriceBookUsage] = [:]) -> [String] {
        PriceBookSearchIndex(items: catalog).search(query, kind: kind, usage: usage).map(\.item.description)
    }

    func testWordsMatchInAnyOrderAsPrefixes() {
        XCTAssertEqual(search("cap 45").first, "Capacitor, 45/5 MFD dual run")
        XCTAssertEqual(search("dual cap 35"), ["Capacitor, 35/5 MFD dual run"])
    }

    func testOneTypoFromFourLettersStillFinds() {
        XCTAssertTrue(search("capacitr").contains("Capacitor, 45/5 MFD dual run"))
        XCTAssertTrue(search("condensor").contains("Condenser coil cleaning"))
        XCTAssertTrue(search("refrigrant").contains("Refrigerant R-410A"))
        XCTAssertTrue(search("capicit").contains("Capacitor, 45/5 MFD dual run"), "a typo inside the word still being typed")
    }

    func testShortWordsAndNumbersNeverTakeATypo() {
        XCTAssertTrue(search("cpa").isEmpty)
        XCTAssertTrue(search("capacitor 46").isEmpty)
        XCTAssertEqual(search("capacitor 4").first, "Capacitor, 45/5 MFD dual run", "the word being typed may be a number prefix")
        XCTAssertTrue(search("4 capacitor").isEmpty, "a finished number must match exactly")
    }

    func testEveryWordMustMatch() {
        XCTAssertTrue(search("capacitor zebra").isEmpty)
    }

    func testArchivedAndOtherCurrencyItemsNeverAppear() {
        let results = search("capacitor")
        XCTAssertFalse(results.contains("Old capacitor"))
        XCTAssertFalse(results.contains("Capacitor priced in euros"))
    }

    func testExactAndPrefixRankAboveContainsAndTypo() {
        XCTAssertEqual(search("cap").first, "Cap", "whole description first")
        let ranked = search("capacitor")
        XCTAssertEqual(Array(ranked.prefix(2)), ["Capacitor, 35/5 MFD dual run", "Capacitor, 45/5 MFD dual run"])
        XCTAssertEqual(ranked.last, "Hard start kit with capacitor")
    }

    func testFrequentRecentItemsRankFirstWithinATier() {
        let now = Date()
        let usage = ["00000000-0000-4000-8000-000000000001": PriceBookUsage(count: 5, lastUsed: now)]
        XCTAssertEqual(PriceBookSearchIndex(items: catalog).search("capacitor", usage: usage, now: now).first?.item.description,
                       "Capacitor, 45/5 MFD dual run")
    }

    func testKindChipFiltersAndKindWordsMatch() {
        XCTAssertEqual(search("", kind: .labor), ["Licensed technician labor"])
        XCTAssertEqual(search("coil", kind: .material), [])
        XCTAssertEqual(search("services coil"), ["Condenser coil cleaning"])
        XCTAssertEqual(search("hour"), ["Licensed technician labor"])
    }

    func testPunctuationAndAccentsAreIgnored() {
        XCTAssertEqual(search("r410a"), ["Refrigerant R-410A"], "neighbouring words match joined")
        XCTAssertTrue(search("r420a").isEmpty, "a model number never takes a typo")
        XCTAssertTrue(search("455 capacitor").isEmpty, "two sizes never join into one number")
        XCTAssertTrue(PriceBookSearchIndex(items: [item(20, "Pipe 110 mm")]).search("10mm pipe").isEmpty,
                      "a size never matches inside a larger one")
        XCTAssertEqual(PriceBookSearchIndex(items: [item(21, "Pipe 10 mm")]).search("10mm pipe").count, 1)
        let joinedBook = PriceBookSearchIndex(items: [item(22, "Refrigerant R410A")])
        XCTAssertEqual(joinedBook.search("R-410A").count, 1, "a dash typed into a model written without one")
        XCTAssertEqual(joinedBook.search("r 410a").count, 1)
        XCTAssertTrue(joinedBook.search("r 420a").isEmpty)
        XCTAssertEqual(search("R 410A"), ["Refrigerant R-410A"])
        XCTAssertEqual(search("CONDÉNSER").first, "Condenser coil cleaning")
    }

    func testHighlightsMarkWordStarts() throws {
        let result = try XCTUnwrap(PriceBookSearchIndex(items: catalog).search("kit cap").first)
        XCTAssertEqual(result.item.description, "Hard start kit with capacitor")
        XCTAssertEqual(result.highlights.map { String(result.item.description[$0]) }, ["kit", "cap"])
    }

    func testRecentListsMostUsedFirst() {
        let now = Date()
        let usage = [
            "00000000-0000-4000-8000-000000000004": PriceBookUsage(count: 2, lastUsed: now),
            "00000000-0000-4000-8000-000000000005": PriceBookUsage(count: 9, lastUsed: now.addingTimeInterval(-86_400)),
            "00000000-0000-4000-8000-000000000007": PriceBookUsage(count: 50, lastUsed: now),
        ]
        let recent = PriceBookSearchIndex(items: catalog).recent(usage: usage, now: now).map(\.description)
        XCTAssertEqual(recent, ["Licensed technician labor", "Condenser coil cleaning"], "archived items stay out")
    }

    func testUsageFadesByHalfEveryThirtyDays() {
        let now = Date()
        let usage = PriceBookUsage(count: 4, lastUsed: now.addingTimeInterval(-30 * 86_400))
        XCTAssertEqual(usage.frecency(now: now), 2, accuracy: 0.0001)
    }

    func testMoreThanFiftyMatchingItemsRemainSearchable() {
        let items = (1...73).map { item($0, String(format: "Valve %03d", $0)) }
        let index = PriceBookSearchIndex(items: items)
        XCTAssertEqual(index.search("valve").count, 73)
        XCTAssertEqual(index.search("valve").last?.item.description, "Valve 073")
        XCTAssertEqual(index.search("").count, 73)
    }

    func testVisiblePageExcludesRecentBeforeLimitingAndCountsMatchingCategory() {
        let services = (1...73).map { item($0, String(format: "Valve %03d", $0), kind: "service") }
        let material = item(99, "Valve material")
        let index = PriceBookSearchIndex(items: services + [material])
        let recentID = services[0].id
        let first = index.page("valve", kind: .service, excludingIDs: [recentID], limit: 50)
        XCTAssertEqual(first.total, 72)
        XCTAssertEqual(first.results.count, 50)
        XCTAssertEqual(first.results.first?.item.description, "Valve 002")
        XCTAssertEqual(first.results.last?.item.description, "Valve 051")
        let next = index.page("valve", kind: .service, excludingIDs: [recentID], limit: 50, offset: 50)
        XCTAssertEqual(next.results.count, 22)
        XCTAssertEqual(next.results.first?.item.description, "Valve 052")
        XCTAssertEqual(next.results.last?.item.description, "Valve 073")
        XCTAssertEqual(Set((first.results + next.results).map(\.id)).count, 72)
        let clamped = index.page("valve", kind: .service, excludingIDs: [recentID], limit: 50, offset: 500)
        XCTAssertEqual(clamped.offset, 50)
        XCTAssertEqual(index.page("valve", kind: .material, limit: 50).total, 1)
        XCTAssertEqual(index.page("unknown", limit: 50).total, 0)
    }

    func testRepeatedSearchChangesRespectFiltersUsageAndCatalogSnapshot() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let first = item(1, "Copper valve", cents: 100)
        let second = item(2, "Copper elbow", cents: 200)
        let service = item(3, "Copper service", kind: "service")
        let index = PriceBookSearchIndex(items: [first, second, service])
        let initial = index.page("copper", kind: .material, now: now, limit: 1)
        XCTAssertEqual(initial.total, 2)
        XCTAssertEqual(index.page("copper", kind: .material, now: now, limit: 1, offset: 1).results.first?.id,
                       second.id == initial.results.first?.id ? first.id : second.id)
        XCTAssertEqual(index.page("copper", kind: .service, now: now).results.map(\.id), [service.id])
        XCTAssertEqual(index.page("copper", kind: .material, now: now, excludingIDs: [first.id]).results.map(\.id), [second.id])
        let usage = [first.id: PriceBookUsage(count: 9, lastUsed: now)]
        XCTAssertEqual(index.page("copper", kind: .material, usage: usage, now: now).results.first?.id, first.id)
        XCTAssertEqual(index.page("unmatched", now: now).total, 0)

        let updated = PriceBookSearchIndex(items: [item(1, "Copper valve", cents: 999)])
        XCTAssertEqual(updated.page("copper", now: now).results.first?.item.sellPrice.amount, 999)
        XCTAssertEqual(index.page("copper", kind: .material, now: now).results.first(where: { $0.id == first.id })?.item.sellPrice.amount, 100)
    }

    func testLargeLoadedCatalogCanReachItsLastMatch() {
        let items = (1...10_000).map { item($0, String(format: "Valve %05d", $0)) }
        let index = PriceBookSearchIndex(items: items)
        let start = Date()
        let first = index.page("valve", limit: 50)
        let middle = index.page("valve", limit: 50, offset: 500)
        let last = index.page("valve", limit: 50, offset: 9_950)
        let elapsed = Date().timeIntervalSince(start)
        print("Price book 10,000-item search across three expansions: \(elapsed) seconds")
        XCTAssertEqual(first.total, 10_000)
        XCTAssertEqual(first.results.count, 50)
        XCTAssertEqual(middle.results.count, 50)
        XCTAssertEqual(last.results.count, 50)
        XCTAssertEqual(last.results.last?.item.description, "Valve 10000")
    }

    func testUsageStoreCountsPerOrganization() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "PriceBookSearchTests"))
        defaults.removePersistentDomain(forName: "PriceBookSearchTests")
        let store = PriceBookUsageStore(organizationID: "org-a", defaults: defaults)
        store.record("item")
        let usage = store.record("item")
        XCTAssertEqual(usage["item"]?.count, 2)
        XCTAssertTrue(PriceBookUsageStore(organizationID: "org-b", defaults: defaults).load().isEmpty)
    }

    func testEditDistance() {
        XCTAssertTrue(PriceBookSearchIndex.editDistanceAtMostOne("valve", "valve"))
        XCTAssertTrue(PriceBookSearchIndex.editDistanceAtMostOne("vlave", "valve"))
        XCTAssertTrue(PriceBookSearchIndex.editDistanceAtMostOne("valv", "valve"))
        XCTAssertTrue(PriceBookSearchIndex.editDistanceAtMostOne("valves", "valve"))
        XCTAssertTrue(PriceBookSearchIndex.editDistanceAtMostOne("calve", "valve"))
        XCTAssertFalse(PriceBookSearchIndex.editDistanceAtMostOne("vlaev", "valve"))
        XCTAssertFalse(PriceBookSearchIndex.editDistanceAtMostOne("val", "valve"))
    }
}
