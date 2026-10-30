import XCTest
@testable import Thorbis

@MainActor
final class InvoiceCollectionOptionTests: XCTestCase {
    func testPendingTenderWinsOverTheLastUsedChoice() {
        for method in FieldPaymentMethod.allCases {
            let option = InvoiceCollectionOption.initial(pendingMethod: method, lastUsed: .paymentLink)
            XCTAssertEqual(option.recordedMethod, method, "A retry must restore its original tender")
        }
    }

    func testBankAndExternalCardChoicesRecordTheirCanonicalTender() {
        XCTAssertEqual(InvoiceCollectionOption.bankTransfer.recordedMethod, .ach)
        XCTAssertEqual(InvoiceCollectionOption.externalCard.recordedMethod, .card)
        XCTAssertNil(InvoiceCollectionOption.paymentLink.recordedMethod)
        XCTAssertNil(InvoiceCollectionOption.tapToPay.recordedMethod)
    }

    func testOnlyDirectChoicesCanBeRememberedForNewPayments() {
        for option in [InvoiceCollectionOption.cash, .check, .paymentLink] {
            XCTAssertEqual(InvoiceCollectionOption.initial(pendingMethod: nil, lastUsed: option), option)
        }
        for option in [InvoiceCollectionOption.bankTransfer, .externalCard, .tapToPay] {
            XCTAssertEqual(InvoiceCollectionOption.initial(pendingMethod: nil, lastUsed: option), .paymentLink)
        }
    }
}
