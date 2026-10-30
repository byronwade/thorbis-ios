import XCTest
@testable import Thorbis

final class PriceBookPresentationTests: XCTestCase {
    func testLongDemoDescriptionHasCompactTitleAndReadableDetails() {
        let raw = "PEX copper crimp ring pack: 1-in. Ten rings for matching-size PEX; tool calibration remains required. [thorbis-plumbing-demo-v1:material-049]"
        XCTAssertEqual(PriceBookPresentation.title(raw), "PEX copper crimp ring pack: 1-in.")
        XCTAssertEqual(PriceBookPresentation.readableDescription(raw), "PEX copper crimp ring pack: 1-in. Ten rings for matching-size PEX; tool calibration remains required.")
        XCTAssertTrue(raw.hasSuffix("[thorbis-plumbing-demo-v1:material-049]"))
    }

    func testArbitraryBracketedTextIsNotRemoved() {
        let raw = "Replace valve. [Customer requested brass fittings]"
        XCTAssertEqual(PriceBookPresentation.readableDescription(raw), raw)
        XCTAssertEqual(PriceBookPresentation.title(raw), raw)
    }

    func testDecimalAndShortNamesAreNotSplit() {
        XCTAssertEqual(PriceBookPresentation.title("Pipe 1.25 inch, type L"), "Pipe 1.25 inch, type L")
        XCTAssertEqual(PriceBookPresentation.title("Coil cleaning"), "Coil cleaning")
        XCTAssertEqual(PriceBookPresentation.title("Dr. Smith's preferred valve"), "Dr. Smith's preferred valve")
    }

    func testOtherMarkersAndLongParagraphsRemainInDetails() {
        let raw = "Replace the valve\nKeep the original shutoff.\n[thorbis-plumbing-demo-v1:custom-049]"
        XCTAssertEqual(PriceBookPresentation.title(raw), "Replace the valve")
        XCTAssertEqual(PriceBookPresentation.readableDescription(raw), raw)
    }

    func testMarkerOnlyUsesAnHonestFallback() {
        XCTAssertEqual(PriceBookPresentation.title("[thorbis-plumbing-demo-v1:material-049]"), "Untitled item")
    }

    func testCatalogHighlightsRemainMappedWhenKnownDemoSuffixIsHidden() {
        let raw = "PEX copper rings. Use with compatible fittings. [thorbis-plumbing-demo-v1:material-049]"
        let visibleMatch = raw.range(of: "copper")!
        let metadataMatch = raw.range(of: "material")!
        let result = PriceBookResultsList.highlighted(raw, [visibleMatch, metadataMatch])
        XCTAssertEqual(String(result.characters), "PEX copper rings. Use with compatible fittings.")
        XCTAssertGreaterThan(result.runs.count, 1, "A visible search match should retain its emphasis")
        XCTAssertTrue(raw.hasSuffix("[thorbis-plumbing-demo-v1:material-049]"))
    }

    func testCatalogKeepsOtherMarkersAndHandlesMarkerOnly() {
        let ordinary = "Valve. [Customer requested brass fittings]"
        XCTAssertEqual(String(PriceBookResultsList.highlighted(ordinary, []).characters), ordinary)
        XCTAssertEqual(String(PriceBookResultsList.highlighted("[thorbis-plumbing-demo-v1:service-001]", []).characters), "Untitled item")
    }
}
