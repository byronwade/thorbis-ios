import XCTest
@testable import Thorbis

/// Redesign phase 3: estimate and invoice statuses map onto the job glyph's tones, and the
/// words come only from the record (no derived "overdue" or "viewed").
final class DocumentStatusTests: XCTestCase {
    func testEstimateStatusesMapToLinearRings() {
        XCTAssertEqual(DocumentStatus(estimateStatus: "draft"), DocumentStatus(tone: .unscheduled, word: "Draft"))
        XCTAssertEqual(DocumentStatus(estimateStatus: "sent"), DocumentStatus(tone: .scheduled, word: "Sent"))
        XCTAssertEqual(DocumentStatus(estimateStatus: "viewed"), DocumentStatus(tone: .dispatched, word: "Viewed"))
        XCTAssertEqual(DocumentStatus(estimateStatus: "approved"), DocumentStatus(tone: .done, word: "Approved"))
        XCTAssertEqual(DocumentStatus(estimateStatus: "declined"), DocumentStatus(tone: .cancelled, word: "Declined"))
        XCTAssertEqual(StatusTone(estimateStatus: "approved"), .done)
    }

    func testInvoiceStatusesReadFromTheRecordOnly() {
        XCTAssertEqual(DocumentStatus(invoice: invoice("draft")), DocumentStatus(tone: .unscheduled, word: "Draft"))
        XCTAssertEqual(DocumentStatus(invoice: invoice("issued")), DocumentStatus(tone: .scheduled, word: "Unpaid"))
        XCTAssertEqual(DocumentStatus(invoice: invoice("issued", paid: 10_000)), DocumentStatus(tone: .inProgress, word: "Part paid"))
        XCTAssertEqual(DocumentStatus(invoice: invoice("paid", paid: 48_000)), DocumentStatus(tone: .invoiced, word: "Paid"))
        XCTAssertEqual(DocumentStatus(invoice: invoice("void")), DocumentStatus(tone: .cancelled, word: "Void"))
        // Overdue only when the server says so: the record has no due date to work it out from.
        XCTAssertEqual(DocumentStatus(invoiceStatus: "overdue", amountPaid: 0, balance: 100).tone, .attention)
        XCTAssertEqual(StatusTone(invoice: invoice("issued", paid: 10_000)), .inProgress)
    }

    func testFullyPaidIssuedInvoiceReadsPaidNotPartPaid() {
        XCTAssertEqual(DocumentStatus(invoice: invoice("issued", paid: 48_000)), DocumentStatus(tone: .invoiced, word: "Paid"))
    }

    private func invoice(_ status: String, total: Int = 48_000, paid: Int = 0) -> InvoiceRecord {
        InvoiceRecord(id: "i", organizationId: "o", customerId: "c", jobId: "j", createdByUserId: "u", locationId: nil, scheduleId: nil,
                      origin: "job_completion", sourceOperationKey: "k", sourceEstimateId: nil, sourceEstimateRevisionNumber: nil,
                      manualPhysicalServiceEvidence: nil, status: status,
                      lines: [FieldLine(id: "l", description: "Work", quantity: 1,
                                        unitPrice: FieldMoney(amount: total, currency: "USD"), source: nil)],
                      linesRevision: 1, amountPaid: paid, currency: "USD", issuedAt: nil, paidAt: nil, voidedAt: nil,
                      createdAt: "2026-10-28T00:00:00Z", updatedAt: "2026-10-28T00:00:00Z")
    }
}
