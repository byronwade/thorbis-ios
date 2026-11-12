import XCTest
@testable import Thorbis

final class InvoiceActionIdentityTests: XCTestCase {
    func testReloadTimestampsAndAuthorizationDoNotBlockSignDiscountOrCollection() {
        let original = invoice(status: "issued")
        let reloaded = invoice(status: "issued", updatedAt: "2026-11-12T18:00:00Z",
                               authorization: FieldSignatureRecord(id: "s", signerName: "Ada",
                                                                   signedAt: "2026-11-12T18:00:00Z",
                                                                   imageMediaId: "m", linesRevision: 1))
        XCTAssertNotEqual(original, reloaded)
        XCTAssertTrue(invoiceAllowsSignature(original, current: reloaded, canEdit: true))
        XCTAssertTrue(invoiceAllowsCollectionStart(original, paymentInvoice: reloaded,
                                                   canRecordPayment: true, canCreatePayment: true))

        let draft = invoice(status: "draft")
        let reloadedDraft = invoice(status: "draft", updatedAt: "2026-11-12T18:00:00Z")
        XCTAssertNotEqual(draft, reloadedDraft)
        XCTAssertTrue(invoiceAllowsDiscount(draft, current: reloadedDraft, isOffline: false, canDiscount: true))
    }

    func testActionsRejectADifferentInvoiceAndInvalidStatus() {
        let current = invoice(status: "issued")
        let other = invoice(id: "other", status: "issued")
        XCTAssertFalse(invoiceAllowsSignature(other, current: current, canEdit: true))
        XCTAssertFalse(invoiceAllowsCollectionStart(current, paymentInvoice: other,
                                                    canRecordPayment: true, canCreatePayment: true))
        XCTAssertFalse(invoiceAllowsSignature(current, current: invoice(status: "void"), canEdit: true))
        XCTAssertFalse(invoiceAllowsDiscount(invoice(status: "draft"), current: invoice(status: "issued"),
                                             isOffline: false, canDiscount: true))
    }

    func testDiscountApplyStaysBlockedOfflineWhileTheOpenInvoiceStillIdentifies() {
        let draft = invoice(status: "draft")
        let reloaded = invoice(status: "draft", updatedAt: "2026-11-12T18:00:00Z")
        XCTAssertFalse(invoiceAllowsDiscount(draft, current: reloaded, isOffline: true, canDiscount: true))
        XCTAssertTrue(invoiceAllowsDiscount(draft, current: reloaded, isOffline: false, canDiscount: true))
    }

    private func invoice(id: String = "i", status: String, updatedAt: String = "2026-10-28T00:00:00Z",
                         authorization: FieldSignatureRecord? = nil) -> InvoiceRecord {
        InvoiceRecord(id: id, organizationId: "o", customerId: "c", jobId: "j", createdByUserId: "u", locationId: nil, scheduleId: nil,
                      origin: "job_completion", sourceOperationKey: "k", sourceEstimateId: nil, sourceEstimateRevisionNumber: nil,
                      manualPhysicalServiceEvidence: nil, status: status,
                      lines: [FieldLine(id: "l", description: "Work", quantity: 1,
                                        unitPrice: FieldMoney(amount: 48_000, currency: "USD"), source: nil)],
                      linesRevision: 1, amountPaid: 0, currency: "USD", issuedAt: nil, paidAt: nil, voidedAt: nil,
                      createdAt: "2026-10-28T00:00:00Z", updatedAt: updatedAt, customerAuthorization: authorization)
    }
}
