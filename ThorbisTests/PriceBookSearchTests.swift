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
