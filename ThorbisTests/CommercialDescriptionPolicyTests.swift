import XCTest
@testable import Thorbis

final class CommercialDescriptionPolicyTests: XCTestCase {
    func testLegacyUnicodeRemainsAcceptedWithoutCapability() {
        XCTAssertNil(CommercialDescriptionPolicy.problem([String(repeating: "🔧", count: 100)], kind: .estimate, capabilityVerified: false))
        XCTAssertNil(CommercialDescriptionPolicy.problem([String(repeating: "🔧", count: 211)], kind: .invoice, capabilityVerified: false))
    }
    func testExtendedTextRequiresFreshCapabilityAndKeepsInput() {
        let text = String(repeating: "Scope ", count: 80) + "\n\nFinish"
        XCTAssertEqual(CommercialDescriptionPolicy.problem([text], kind: .estimate, capabilityVerified: false), .unavailable)
        XCTAssertNil(CommercialDescriptionPolicy.problem([text], kind: .estimate, capabilityVerified: true))
        XCTAssertTrue(text.hasSuffix("Finish"))
    }
    func testExtendedBoundariesAndUnicode() {
        XCTAssertEqual(CommercialDescriptionPolicy.problem([String(repeating: "x", count: 4_001)], kind: .estimate, capabilityVerified: true), .lineTooLong)
        XCTAssertEqual(CommercialDescriptionPolicy.problem([String(repeating: "x", count: 201), "🔧"], kind: .estimate, capabilityVerified: true), .unsupportedCharacters)
        XCTAssertEqual(CommercialDescriptionPolicy.problem(Array(repeating: String(repeating: "x", count: 4_000), count: 13), kind: .estimate, capabilityVerified: true), .totalTooLong)
        XCTAssertEqual(CommercialDescriptionPolicy.problem([String(repeating: "x\n", count: 1_251) + "end", String(repeating: "x\n", count: 1_251) + "end"], kind: .estimate, capabilityVerified: true), .tooManyBreaks)
        XCTAssertEqual(CommercialDescriptionPolicy.problem([String(repeating: "x", count: 201)] + Array(repeating: "a", count: 499), kind: .estimate, optionCount: 1, capabilityVerified: true), .tooManyRows)
    }

    func testAcceptedDocumentAtAggregateLimitsMatchesServerContract() {
        let descriptions = (0..<500).map { index in
            let count = index == 0 ? 3_991 : (index == 499 ? 175 : 83)
            return String(repeating: "x", count: count) + "\n\n\n\n\n" + String(format: "E%03d", index)
        }
        XCTAssertEqual(descriptions.reduce(0) { $0 + $1.utf16.count }, 50_000)
        XCTAssertNil(CommercialDescriptionPolicy.problem(descriptions, kind: .estimate, capabilityVerified: true))
        XCTAssertEqual(CommercialDescriptionPolicy.problem(descriptions, kind: .estimate, optionCount: 1, capabilityVerified: true), .tooManyRows)
    }
}
