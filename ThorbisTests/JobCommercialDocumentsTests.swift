import XCTest
@testable import Thorbis

@MainActor
final class JobCommercialDocumentsTests: XCTestCase {
    private func id(_ value: Int) -> String { String(format: "00000000-0000-4000-8000-%012d", value) }
    private func scope(job: Int = 100, origin: Int? = nil) -> JobDocumentScope {
        .init(jobID: id(job), organizationID: id(1), customerID: id(2), originEstimateID: origin.map(id))
    }

    func testEstimateMembershipDeduplicatesAndRejectsAnotherJobForSameCustomer() async throws {
        let client = api([
            .init(200, page([link(11), link(11), link(12, job: 101)])),
            .init(200, estimate(10)), .init(200, estimate(11))
        ])
        let result = await JobDocumentsLoader.estimates(scope: scope(origin: 10), api: client, retaining: nil, isCurrent: { true })
        let read = try XCTUnwrap(result)
        XCTAssertEqual(read.records.map(\.id), [id(10), id(11)])
        XCTAssertEqual(read.freshIDs, Set([id(10), id(11)]))
        XCTAssertFalse(read.isComplete)
        XCTAssertNotNil(read.issue)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 3)
        XCTAssertFalse(URLProtocolFixture.recorded.contains { $0.url?.path.hasSuffix(self.id(12)) == true })
    }

    func testOneFailedEstimateKeepsOtherSuccessesAndSameJobPreviousRow() async throws {
        let first = api([.init(200, page([link(11), link(12)])),
                         .init(200, estimate(10)), .init(200, estimate(11)), .init(200, estimate(12))])
        let previous = await JobDocumentsLoader.estimates(scope: scope(origin: 10), api: first, retaining: nil, isCurrent: { true })
        let second = api([.init(200, page([link(11), link(12)])), .init(200, estimate(10)),
                          .init(503, problem(503)), .init(200, estimate(12))])
        let result = await JobDocumentsLoader.estimates(scope: scope(origin: 10), api: second, retaining: previous, isCurrent: { true })
        let read = try XCTUnwrap(result)
        XCTAssertEqual(Set(read.records.map(\.id)), Set([id(10), id(11), id(12)]))
        XCTAssertEqual(read.freshIDs, Set([id(10), id(12)]))
        XCTAssertFalse(read.isComplete)
    }

    func testInitiallyUnavailableLinkedEstimateKeepsItsOwnVisibleReference() async throws {
        let client = api([.init(200, page([link(11), link(12, job: 101)])),
                          .init(200, estimate(10)), .init(503, problem(503))])
        let result = await JobDocumentsLoader.estimates(scope: scope(origin: 10), api: client, retaining: nil, isCurrent: { true })
        let read = try XCTUnwrap(result)
        XCTAssertEqual(read.records.map(\.id), [id(10)])
        XCTAssertEqual(read.unavailableIDs, [id(11)])
        XCTAssertFalse(read.isComplete)
    }

    func testEstimateDetailMustMatchTheRequestedIdentityAndCustomer() async throws {
        for body in [estimate(99), estimate(10, customer: 3), estimate(10, organization: 4)] {
            let client = api([.init(200, page([])), .init(200, body)])
            let result = await JobDocumentsLoader.estimates(scope: scope(origin: 10), api: client, retaining: nil, isCurrent: { true })
            let read = try XCTUnwrap(result)
            XCTAssertTrue(read.records.isEmpty)
            XCTAssertTrue(read.freshIDs.isEmpty)
            XCTAssertFalse(read.isComplete)
        }
    }

    func testAnotherJobsRetainedEstimatesCannotBecomeFallbackForSameCustomer() async throws {
        let first = api([.init(200, page([link(11, job: 101)])), .init(200, estimate(11))])
        let previous = await JobDocumentsLoader.estimates(scope: scope(job: 101), api: first, retaining: nil, isCurrent: { true })
        let second = api([.init(503, problem(503))])
        let result = await JobDocumentsLoader.estimates(scope: scope(), api: second, retaining: previous, isCurrent: { true })
        let read = try XCTUnwrap(result)
        XCTAssertTrue(read.records.isEmpty)
        XCTAssertFalse(read.isComplete)
    }

    func testInvoiceEndpointRejectsForeignJobTenantCustomerAndMissingJob() async throws {
        let client = api([.init(200, page([invoice(50), invoice(51, job: 101), invoice(52, job: nil),
                                         invoice(53, organization: 9), invoice(54, customer: 9)]))])
        let result = await JobDocumentsLoader.invoices(scope: scope(), api: client, knownIDs: [], retaining: nil, isCurrent: { true })
        let read = try XCTUnwrap(result)
        XCTAssertEqual(read.records.map(\.id), [id(50)])
        XCTAssertEqual(read.freshIDs, Set([id(50)]))
        XCTAssertFalse(read.isComplete)
    }

    func testAuthoritativeEmptyInvoiceReadNeverResurrectsCachedIDs() async throws {
        let client = api([.init(200, page([]))])
        let result = await JobDocumentsLoader.invoices(scope: scope(), api: client, knownIDs: [id(50)], retaining: nil, isCurrent: { true })
        let read = try XCTUnwrap(result)
        XCTAssertTrue(read.records.isEmpty)
        XCTAssertTrue(read.isComplete)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
    }

    func testLegacyCompatibilityUnionsOnlyVerifiedKnownJobInvoicesAndReportsIncomplete() async throws {
        let client = api([.init(404, problem(404)), .init(200, page([invoice(50), invoice(51, job: 101)])),
                          .init(200, invoice(52))])
        let result = await JobDocumentsLoader.invoices(scope: scope(), api: client, knownIDs: [id(52), id(51)], retaining: nil, isCurrent: { true })
        let read = try XCTUnwrap(result)
        XCTAssertEqual(Set(read.records.map(\.id)), Set([id(50), id(52)]))
        XCTAssertFalse(read.isComplete)
        XCTAssertNotNil(read.issue)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 3)
    }

    func testAllInvoicePagesAreIncludedAndPaidDepositDoesNotHideUnpaidInvoice() async throws {
        let client = api([.init(200, page([invoice(52, status: "paid", paid: 10000)], cursor: "page-two")),
                          .init(200, page([invoice(50), invoice(53, status: "draft")]))])
        let result = await JobDocumentsLoader.invoices(scope: scope(), api: client, knownIDs: [], retaining: nil, isCurrent: { true })
        let read = try XCTUnwrap(result)
        XCTAssertEqual(read.records.count, 3)
        XCTAssertTrue(read.isComplete)
        XCTAssertEqual(read.preferredInvoice(id: nil)?.id, id(50))
        XCTAssertEqual(read.preferredInvoice(id: id(52))?.id, id(50))
        XCTAssertEqual(read.preferredInvoice(id: id(53))?.id, id(53))
    }

    func testWorkspaceChangeDuringCachedFallbackCannotPublish() async throws {
        let gate = URLProtocolFixture.Gate()
        let client = api([.init(405, problem(405)), .init(200, page([])), .init(200, invoice(50), gate: gate)])
        var current = true
        let load = Task {
            let result = await JobDocumentsLoader.invoices(scope: scope(), api: client, knownIDs: [id(50)], retaining: nil, isCurrent: { current })
            return result != nil
        }
        let deadline = Date().addingTimeInterval(3)
        while URLProtocolFixture.recorded.count < 3 && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 3)
        current = false
        gate.release()
        let published = await load.value
        XCTAssertFalse(published)
        XCTAssertTrue(URLProtocolFixture.recorded.allSatisfy { $0.method == "GET" })
    }

    func testPreviewExercisesTheCanonicalJobInvoiceEndpoint() async throws {
        let client = APIClient(session: PaperPreview.transport(), baseURL: "https://app.thorbis.com")
        let invoices = try await client.fieldJobInvoices(PaperPreview.jobID)
        XCTAssertEqual(invoices.count, 1)
        XCTAssertTrue(invoices.allSatisfy { $0.jobId == PaperPreview.jobID })
    }

    private func api(_ replies: [URLProtocolFixture.Reply]) -> APIClient {
        APIClient(session: URLProtocolFixture.session(replies), baseURL: "https://app.thorbis.com")
    }
    private func page(_ rows: [String], cursor: String? = nil) -> String {
        "{\"items\":[\(rows.joined(separator: ","))],\"nextCursor\":\(cursor.map { "\"\($0)\"" } ?? "null")}"
    }
    private func link(_ estimate: Int, job: Int = 100) -> String {
        "{\"id\":\"\(id(1000+estimate))\",\"jobId\":\"\(id(job))\",\"estimateId\":\"\(id(estimate))\"}"
    }
    private func estimate(_ value: Int, organization: Int = 1, customer: Int = 2) -> String {
        "{\"id\":\"\(id(value))\",\"organizationId\":\"\(id(organization))\",\"customerId\":\"\(id(customer))\",\"createdByUserId\":\"\(id(3))\",\"status\":\"sent\",\"currentRevisionNumber\":1,\"title\":\"Estimate \(value)\",\"lines\":[],\"createdAt\":\"2026-10-01T12:00:00Z\",\"updatedAt\":\"2026-10-01T12:00:00Z\"}"
    }
    private func invoice(_ value: Int, job: Int? = 100, organization: Int = 1, customer: Int = 2,
                         status: String = "issued", paid: Int = 0) -> String {
        "{\"id\":\"\(id(value))\",\"organizationId\":\"\(id(organization))\",\"customerId\":\"\(id(customer))\",\"jobId\":\(job.map { "\"\(id($0))\"" } ?? "null"),\"createdByUserId\":\"\(id(3))\",\"origin\":\"job_completion\",\"sourceOperationKey\":\"test:\(value)\",\"status\":\"\(status)\",\"lines\":[{\"id\":\"\(id(900))\",\"description\":\"Plumbing service\",\"quantity\":1,\"unitPrice\":{\"amount\":10000,\"currency\":\"USD\"}}],\"linesRevision\":1,\"amountPaid\":\(paid),\"currency\":\"USD\",\"createdAt\":\"2026-10-01T12:00:00Z\",\"updatedAt\":\"2026-10-01T12:00:00Z\"}"
    }
    private func problem(_ status: Int) -> String { "{\"title\":\"Read unavailable\",\"status\":\(status)}" }
}
