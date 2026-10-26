import Foundation
import XCTest
@testable import ThorbisCore

final class DecodingTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func testJobDetailDecodesServerShapeAndIgnoresUnknownFields() throws {
        let job = try JSONDecoder().decode(Job.self, from: fixture("job-detail"))
        XCTAssertEqual(job.status, .paused)
        XCTAssertEqual(job.allowedTransitions, [.inProgress, .completed, .canceled])
        XCTAssertEqual(job.pauseReason, "Waiting on part")
        XCTAssertEqual(job.reference, "JOB-4A5B")
        XCTAssertNotNil(job.scheduledDate)
        XCTAssertNotNil(job.updatedDate, "timestamps without fractional seconds still parse")
    }

    func testUnknownJobStatusDoesNotBreakTheList() throws {
        let data = Data(#"{"items":[{"id":"a","customerId":"c","title":"T","status":"teleported","createdAt":"x","updatedAt":"x"}]}"#.utf8)
        let page = try JSONDecoder().decode(Page<Job>.self, from: data)
        XCTAssertEqual(page.items.first?.status, .unknown)
        XCTAssertNil(page.nextCursor)
    }

    func testCustomersPageKeepsCursorAndToleratesUnknownContactPreference() throws {
        let page = try JSONDecoder().decode(Page<Customer>.self, from: fixture("customers-page"))
        XCTAssertEqual(page.items.count, 2)
        XCTAssertNil(page.items[0].preferredContact)
        XCTAssertEqual(page.items[0].billingTerms, "net_30")
        XCTAssertTrue(page.items[1].isArchived)
        XCTAssertEqual(page.nextCursor, "018f3a52-0000-7000-8000-00000000c002")
    }

    func testInvoiceTotalsUseIntegerCents() throws {
        let invoice = try JSONDecoder().decode(Invoice.self, from: fixture("invoice"))
        XCTAssertEqual(invoice.status, .issued)
        XCTAssertEqual(invoice.total, 185_000 + 2 * 2_500)
        XCTAssertEqual(invoice.balance, 190_000 - 50_000)
        XCTAssertEqual(invoice.linesRevision, 3)
    }

    func testEstimateWithPriceBookSourceAndOptions() throws {
        let estimate = try JSONDecoder().decode(Estimate.self, from: fixture("estimate"))
        XCTAssertEqual(estimate.status, .sent)
        XCTAssertEqual(estimate.currentRevisionNumber, 2)
        XCTAssertEqual(estimate.total, 240_000)
        XCTAssertEqual(estimate.options?.first?.totalAmount, 50_000)
    }

    func testProblemMapping() {
        let body = Data(#"{"type":"https://thorbis.com/problems/forbidden","title":"forbidden","status":403,"detail":"no active organization for this session"}"#.utf8)
        XCTAssertEqual(APIError.from(status: 403, body: body), .noActiveOrganization)
        XCTAssertEqual(APIError.from(status: 401, body: Data()), .unauthenticated)
        let conflict = APIError.from(status: 409, body: Data(#"{"detail":"stale"}"#.utf8))
        XCTAssertTrue(conflict.isConflict)
        XCTAssertEqual(conflict.errorDescription, "stale")
        let betterAuth = APIError.from(status: 400, body: Data(#"{"code":"INVALID_EMAIL_OR_PASSWORD","message":"Invalid email or password"}"#.utf8))
        XCTAssertEqual(betterAuth.errorDescription, "Invalid email or password")
        XCTAssertTrue(APIError.from(status: 503, body: Data()).isRetryable)
    }
}
