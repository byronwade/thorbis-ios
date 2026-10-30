import XCTest
@testable import Thorbis

final class DescriptionCanvasLimitTests: XCTestCase {
    func testEstimateLimitCountsTrimmedUTF16WithoutTruncatingInput() {
        let text = "  " + String(repeating: "😀", count: 101) + "  "
        XCTAssertEqual(DescriptionCanvasLimit.utf16(200).count(text), 202)
        XCTAssertEqual(text.utf16.count, 206)
    }

    func testOptionLimitCountsWhitespaceExactlyAsStored() {
        XCTAssertEqual(DescriptionCanvasLimit.utf16Raw(500).count("  option  "), 10)
    }

    func testInvoiceLimitCountsTrimmedUnicodeScalars() {
        let text = "  " + String(repeating: "😀", count: 211) + "  "
        XCTAssertEqual(DescriptionCanvasLimit.unicodeScalars(211).count(text), 211)
    }
}

final class DescriptionCanvasScopeTests: XCTestCase {
    func testOnlyOriginalAuthorityCanRevealUnsavedContent() {
        let generation = UUID(), authority = UUID()
        let captured = DescriptionCanvasScope(actor: "actor", organization: "org", generation: generation, authority: authority)
        XCTAssertTrue(captured.matches(actor: "actor", organization: "org", generation: generation, authority: authority))
        XCTAssertFalse(captured.matches(actor: "actor", organization: "org", generation: generation, authority: UUID()))
        XCTAssertFalse(captured.matches(actor: "other", organization: "org", generation: generation, authority: authority))
        XCTAssertFalse(captured.matches(actor: "actor", organization: "other", generation: generation, authority: authority))
        XCTAssertFalse(captured.matches(actor: "actor", organization: "org", generation: UUID(), authority: authority))
    }
}
