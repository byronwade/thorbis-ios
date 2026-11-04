import XCTest
@testable import Thorbis

final class InvoiceReferenceSearchTests: XCTestCase {
    func testCustomerAndShortReferencesStillMatch() {
        let id = "11111111-1111-4111-8111-111100002209"
        XCTAssertTrue(InvoiceReferenceSearch.matches(query: "marlow", invoiceID: id, customerName: "Marlowe"))
        XCTAssertTrue(InvoiceReferenceSearch.matches(query: "inv-2209", invoiceID: id, customerName: "Marlowe"))
        XCTAssertFalse(InvoiceReferenceSearch.matches(query: "unrelated", invoiceID: id, customerName: "Marlowe"))
    }

    func testFullIDDisambiguatesInvoicesWithIdenticalShortReferences() {
        let first = "11111111-1111-4111-8111-111100002209"
        let second = "22222222-2222-4222-8222-222200002209"
        XCTAssertTrue(InvoiceReferenceSearch.matches(query: "00002209", invoiceID: first, customerName: "A"))
        XCTAssertTrue(InvoiceReferenceSearch.matches(query: "00002209", invoiceID: second, customerName: "B"))
        XCTAssertTrue(InvoiceReferenceSearch.matches(query: first.uppercased(), invoiceID: first, customerName: "A"))
        XCTAssertFalse(InvoiceReferenceSearch.matches(query: first.uppercased(), invoiceID: second, customerName: "B"))
    }
}
