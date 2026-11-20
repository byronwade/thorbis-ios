import XCTest
@testable import Thorbis

final class MaterialsTests: XCTestCase {
    private func item(_ number: Int, _ description: String, unit: String = "each", kind: String = "material",
                      cents: Int = 1000) -> PriceBookListItem {
        PriceBookListItem(id: String(format: "00000000-0000-4000-8000-%012d", number), description: description,
                          unit: unit, kind: kind, taxClassification: "taxable",
                          sellPrice: FieldMoney(amount: cents, currency: "USD"), revision: 1, archivedAt: nil)
    }

    // MARK: Parser

    func testPaperListLines() {
        let lines = MaterialsListParser.parse("""
        2x R-410A refrigerant 25lb
        1 contactor relay 24v
        capacitor 45/5
        trip fee
        3 hrs labor
        """)
        XCTAssertEqual(lines.map(\.quantity), [2, 1, 1, 1, 3])
        XCTAssertEqual(lines.map(\.name), ["R-410A refrigerant 25lb", "contactor relay 24v", "capacitor 45/5", "trip fee", "labor"])
    }

    func testSpacedTimesKeepsSizeInName() {
        let line = MaterialsListParser.parseLine("2 x 45/5 capacitor")
        XCTAssertEqual(line?.quantity, 2)
        XCTAssertEqual(line?.name, "45/5 capacitor")
    }

    func testLeadingNumberThatIsPartOfTheNameIsNotAQuantity() {
        XCTAssertEqual(MaterialsListParser.parseLine("45/5 capacitor")?.quantity, 1)
        XCTAssertEqual(MaterialsListParser.parseLine("45/5 capacitor")?.name, "45/5 capacitor")
        XCTAssertEqual(MaterialsListParser.parseLine("2x4 lumber")?.quantity, 1)
        XCTAssertEqual(MaterialsListParser.parseLine("2x4 lumber")?.name, "2x4 lumber")
        XCTAssertEqual(MaterialsListParser.parseLine("10mm pipe")?.name, "10mm pipe")
    }

    func testTrailingQuantityAndUnits() {
        XCTAssertEqual(MaterialsListParser.parseLine("capacitor x3")?.quantity, 3)
        XCTAssertEqual(MaterialsListParser.parseLine("capacitor x3")?.name, "capacitor")
        XCTAssertEqual(MaterialsListParser.parseLine("filter \u{00D7} 4")?.quantity, 4)
        XCTAssertEqual(MaterialsListParser.parseLine("3hrs labor")?.name, "labor")
        XCTAssertEqual(MaterialsListParser.parseLine("2 xenon bulbs")?.name, "xenon bulbs")
        XCTAssertEqual(MaterialsListParser.parseLine("- 2 ea fuses")?.quantity, 2)
        XCTAssertEqual(MaterialsListParser.parseLine("- 2 ea fuses")?.name, "fuses")
    }

    func testBlankLinesAreSkippedAndQuantityIsBounded() {
        XCTAssertTrue(MaterialsListParser.parse("\n   \n\t\n").isEmpty)
        XCTAssertNil(MaterialsListParser.parseLine("   "))
        XCTAssertEqual(MaterialsListParser.parse("trip fee\n\n  \nfilter").count, 2)
        XCTAssertEqual(MaterialsListParser.parseLine("0 x filter")?.quantity, 1)
        XCTAssertEqual(MaterialsListParser.parseLine("5000 filters")?.quantity, MaterialsListParser.maximumQuantity)
    }

    // MARK: Matcher

    func testPaperListMatchesLikePaper32() {
        let index = PriceBookSearchIndex(items: [
            item(1, "R-410A Refrigerant, 25 lb", cents: 8200),
            item(2, "Contactor relay, 24V 1-pole", cents: 2800),
            item(3, "Contactor relay, 24V 2-pole", cents: 3400),
            item(4, "Trip fee", kind: "service", cents: 4000),
            item(5, "Labor", unit: "hour", kind: "labor", cents: 8500),
        ])
        let lines = MaterialsListParser.parse("2x R-410A refrigerant 25lb\n1 contactor relay 24v\ncapacitor 45/5\ntrip fee\n3 hrs labor")
        let matches = lines.map { MaterialsMatcher.classify($0.name, index: index) }
        XCTAssertEqual(matches.map(\.status), [.matched, .similar, .notFound, .matched, .matched])
        XCTAssertEqual(matches[0].item?.id, item(1, "").id)
        XCTAssertEqual(matches[1].candidates.count, 2)
        XCTAssertEqual(matches[3].item?.id, item(4, "").id)
        XCTAssertEqual(matches[4].item?.id, item(5, "").id)
    }

    func testWholeDescriptionWinsOverLongerItems() {
        let index = PriceBookSearchIndex(items: [item(1, "Trip fee"), item(2, "Trip fee after hours")])
        let match = MaterialsMatcher.classify("trip fee", index: index)
        XCTAssertEqual(match.status, .matched)
        XCTAssertEqual(match.item?.id, item(1, "").id)
    }

    func testLooseHitsGoToReview() {
        let index = PriceBookSearchIndex(items: [item(1, "Run capacitor 45/5 MFD")])
        // "capacitr" is a typo: found by search, never added without asking.
        let match = MaterialsMatcher.classify("capacitr", index: index)
        XCTAssertEqual(match.status, .similar)
        XCTAssertNil(match.item)
        XCTAssertEqual(match.candidates.count, 1)
    }

    func testCodeOnlyMatchesWhenInTheName() {
        let index = PriceBookSearchIndex(items: [item(1, "Fuse 30A FNQ-R-30"), item(2, "Filter 16x25x1")])
        XCTAssertEqual(MaterialsMatcher.classify("012345678905", index: index).status, .notFound)
        XCTAssertEqual(MaterialsMatcher.classify("", index: index).status, .notFound)
    }

    func testUnresolvedLinesAreLookedUpAgainWhenThePriceBookLoads() {
        let filter = item(1, "Filter 16x25x1")
        let empty = PriceBookSearchIndex(items: [])
        let waiting = StagedMaterial(source: "filter 16x25x1", quantity: 2, match: MaterialsMatcher.classify("filter 16x25x1", index: empty))
        XCTAssertEqual(waiting.status, .notFound)
        let loaded = MaterialsMatcher.reclassifyUnresolved([waiting], index: PriceBookSearchIndex(items: [filter]))
        XCTAssertEqual(loaded.first?.id, waiting.id)
        XCTAssertEqual(loaded.first?.quantity, 2)
        XCTAssertEqual(loaded.first?.item?.id, filter.id)
    }

    // MARK: Cart

    func testCommitTitles() {
        let refrigerant = item(1, "R-410A Refrigerant, 25 lb", cents: 8200)
        let relay = item(2, "Contactor relay, 24V", cents: 2800)
        XCTAssertEqual(MaterialsCart.commitTitle([]), "Add items")
        let ready = [
            StagedMaterial(source: "a", quantity: 1, match: MaterialsMatch(status: .matched, item: refrigerant, candidates: [refrigerant])),
            StagedMaterial(source: "b", quantity: 1, match: MaterialsMatch(status: .matched, item: relay, candidates: [relay])),
        ]
        XCTAssertTrue(MaterialsCart.commitTitle(ready).hasPrefix("Add 2 items \u{00B7} "))
        XCTAssertTrue(MaterialsCart.commitTitle(ready).contains("110"))
        let waiting = ready + [StagedMaterial(source: "c", quantity: 1, match: MaterialsMatch(status: .notFound, item: nil, candidates: []))]
        XCTAssertEqual(MaterialsCart.commitTitle(waiting), "Add 2 \u{00B7} resolve 1 to continue")
    }

    func testCommitAddsOneUnitAtATimeAndStopsAtRefusal() {
        let filter = item(1, "Filter")
        let fuse = item(2, "Fuse")
        let lines = [
            StagedMaterial(source: "filter", quantity: 3, match: MaterialsMatch(status: .matched, item: filter, candidates: [filter])),
            StagedMaterial(source: "fuse", quantity: 2, match: MaterialsMatch(status: .matched, item: fuse, candidates: [fuse])),
        ]
        var calls: [String] = []
        let result = MaterialsCart.commit(lines) { picked in
            calls.append(picked.id)
            return calls.count == 2 ? "The draft is full." : nil
        }
        XCTAssertEqual(calls, [filter.id, filter.id])
        XCTAssertEqual(result.unitsAdded, 1)
        XCTAssertEqual(result.refusal, "The draft is full.")
        XCTAssertEqual(result.remaining.map(\.source), ["filter", "fuse"])
        XCTAssertEqual(result.remaining.map(\.quantity), [2, 2])
    }

    func testCommitAddsEverythingAndKeepsUnresolved() {
        let filter = item(1, "Filter")
        let lines = [
            StagedMaterial(source: "filter", quantity: 2, match: MaterialsMatch(status: .matched, item: filter, candidates: [filter])),
            StagedMaterial(source: "mystery", quantity: 1, match: MaterialsMatch(status: .notFound, item: nil, candidates: [])),
        ]
        var count = 0
        let result = MaterialsCart.commit(lines) { _ in count += 1; return nil }
        XCTAssertEqual(count, 2)
        XCTAssertEqual(result.unitsAdded, 2)
        XCTAssertNil(result.refusal)
        XCTAssertEqual(result.remaining.map(\.source), ["mystery"])
    }
}
