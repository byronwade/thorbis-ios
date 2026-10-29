import XCTest
@testable import Thorbis

final class ActivityDestinationTests: XCTestCase {
    private let job = "00000000-0000-4000-8000-000000000001"
    private let other = "00000000-0000-4000-8000-000000000002"
    private let customer = "00000000-0000-4000-8000-000000000003"

    func testEachFeedKindOpensTheRecordItAlreadyNames() {
        XCTAssertEqual(destination("job", subjectID: job), .job(job))
        XCTAssertEqual(destination("status", jobID: job), .job(job))
        XCTAssertEqual(destination("estimate", subjectID: other), .estimate(other))
        XCTAssertEqual(destination("invoice", subjectID: other), .invoice(other))
        XCTAssertEqual(destination("created", invoiceID: other), .invoice(other))
        XCTAssertEqual(destination("issued", subjectID: other), .invoice(other))
        XCTAssertEqual(destination("photo", subjectID: other, jobID: job), .media(jobID: job, assetID: other))
        XCTAssertEqual(destination("media", subjectID: other, jobID: job), .media(jobID: job, assetID: other))
        XCTAssertEqual(destination("document", subjectID: other, jobID: job), .media(jobID: job, assetID: other))
        XCTAssertEqual(destination("note", subjectID: other, jobID: job), .note(jobID: job, noteID: other))
        XCTAssertEqual(destination("payment", subjectID: other, invoiceID: job), .payment(invoiceID: job, paymentID: other))
        XCTAssertEqual(destination("contact", subjectID: other, customerID: customer), .contact(customerID: customer, contactID: other))
        XCTAssertEqual(destination("location", subjectID: other, customerID: customer), .location(customerID: customer, locationID: other))
    }

    func testAPaymentOpensTheInvoiceItNames() {
        let payment = ActivityDestination.payment(invoiceID: job, paymentID: other)
        XCTAssertEqual(payment.route, .invoice(job))
    }

    func testACallOrMessageWithoutARealSubjectStaysClosed() {
        XCTAssertNil(destination("call"))
        XCTAssertNil(destination("message"))
        XCTAssertNil(destination("call", subjectID: "   "))
        XCTAssertNil(destination("message", customerID: customer))
        XCTAssertEqual(destination("call", jobID: job), .job(job))
        XCTAssertEqual(destination("message", subjectID: other, customerID: customer), .contact(customerID: customer, contactID: other))
    }

    func testMissingIdsStayClosed() {
        XCTAssertNil(destination("note", jobID: job))
        XCTAssertNil(destination("photo", subjectID: other))
        XCTAssertNil(destination("payment", subjectID: other))
        XCTAssertNil(destination("payment", invoiceID: job))
        XCTAssertNil(destination("contact", subjectID: other))
        XCTAssertNil(destination("location", customerID: customer))
        XCTAssertNil(destination("job", subjectID: " "))
        XCTAssertNil(destination("estimate"))
        XCTAssertNil(destination("status"))
    }

    func testCustomerHistoryUsesTheSubjectAndDoesNotInventAnInvoice() {
        let entry = CustomerHistoryEntry(occurredAt: "2026-08-01T12:00:00Z", kind: "job", subjectId: job, summary: "Booked")
        XCTAssertEqual(ActivityDestinationMapping.customerHistory(entry, customerID: customer), .job(job))
        let payment = CustomerHistoryEntry(occurredAt: "2026-08-01T12:00:00Z", kind: "payment", subjectId: other, summary: "Paid")
        XCTAssertNil(ActivityDestinationMapping.customerHistory(payment, customerID: customer))
        let contact = CustomerHistoryEntry(occurredAt: "2026-08-01T12:00:00Z", kind: "contact", subjectId: other, summary: "Added")
        XCTAssertEqual(ActivityDestinationMapping.customerHistory(contact, customerID: customer), .contact(customerID: customer, contactID: other))
    }

    func testSameParentOpensActivityDetailsWhileDifferentRecordsKeepTheirRoute() {
        XCTAssertFalse(ActivitySelection.opensRecord(nil, currentRoute: .job(job)))
        XCTAssertFalse(ActivitySelection.opensRecord(.job(job), currentRoute: .job(job)))
        XCTAssertFalse(ActivitySelection.opensRecord(.invoice(job), currentRoute: .invoice(job)))
        XCTAssertFalse(ActivitySelection.opensRecord(.payment(invoiceID: job, paymentID: other), currentRoute: .invoice(job)))
        XCTAssertTrue(ActivitySelection.opensRecord(.estimate(other), currentRoute: .job(job)))
        XCTAssertTrue(ActivitySelection.opensRecord(.job(job), currentRoute: nil))
    }

    func testPresentedDetailsPreserveTheSnapshotEvenIfTheRowChanges() {
        let scope = ActivityAccessScope(actorID: job, organizationID: customer, ownerID: "job:one", generation: UUID(), authorityRevision: UUID())
        var row = ActivityDetails(title: "Original", body: "Long detail", context: "Job")
        let presented = PresentedActivityDetails(details: row, scope: scope)
        row = ActivityDetails(title: "Changed")
        XCTAssertEqual(presented.details.title, "Original")
        XCTAssertEqual(presented.details.body, "Long detail")
    }

    func testANoteDetailShowsAReadableTime() throws {
        let raw = "2026-07-01T15:04:00Z"
        let shown = ActivityRecordLabel.noteWhen(raw)
        let date = try XCTUnwrap(JobFiltering.date(raw))
        XCTAssertEqual(shown, date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute()))
        XCTAssertNotEqual(shown, raw)
        XCTAssertEqual(ActivityRecordLabel.noteWhen("not-a-date"), "not-a-date")
    }

    private func destination(_ kind: String, subjectID: String? = nil, jobID: String? = nil, invoiceID: String? = nil, customerID: String? = nil) -> ActivityDestination? {
        ActivityDestinationMapping.destination(for: ActivityFeedSubject(kind: kind, subjectID: subjectID, jobID: jobID, invoiceID: invoiceID, customerID: customerID))
    }
}
