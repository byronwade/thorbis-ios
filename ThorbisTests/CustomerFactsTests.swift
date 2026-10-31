import XCTest
@testable import Thorbis

/// v2 Record room: a customer's own phone, email and address leave the details panel only when a
/// contact or location below already shows the same value.
final class CustomerFactsTests: XCTestCase {
    func testPhoneMatchesOnItsDigitsWhateverTheFormatting() {
        XCTAssertTrue(CustomerFacts.phone("(555) 010-0413", isIn: ["+1 555-010-0413"]))
        XCTAssertFalse(CustomerFacts.phone("555-010-0413", isIn: ["555-010-9999"]))
        XCTAssertFalse(CustomerFacts.phone("413", isIn: ["413"]), "a stub number is never treated as shown")
        XCTAssertFalse(CustomerFacts.phone("555-010-0413", isIn: []), "a value shown nowhere else always stays")
    }

    func testEmailIgnoresCaseAndSpace() {
        XCTAssertTrue(CustomerFacts.email(" Dani@Example.com", isIn: ["dani@example.com"]))
        XCTAssertFalse(CustomerFacts.email("dani@example.com", isIn: ["office@example.com"]))
    }

    func testAddressIgnoresPunctuationAndCase() {
        XCTAssertTrue(CustomerFacts.address("412 Birchwood Ln, Austin, TX 78701", isIn: ["412 birchwood ln austin tx 78701"]))
        XCTAssertFalse(CustomerFacts.address("412 Birchwood Ln", isIn: ["88 Larch Ave"]))
        XCTAssertFalse(CustomerFacts.address("", isIn: [""]))
    }
}
