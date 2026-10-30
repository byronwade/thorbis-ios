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

    func testLegacyFailureRetainsPreviouslyVerifiedInvoiceAsStale() async throws {
        let first = api([.init(200, page([invoice(50), invoice(52)]))])
        let previous = await JobDocumentsLoader.invoices(scope: scope(), api: first, knownIDs: [], retaining: nil, isCurrent: { true })
        let second = api([.init(404, problem(404)), .init(200, page([invoice(50)])), .init(503, problem(503))])
        let result = await JobDocumentsLoader.invoices(scope: scope(), api: second, knownIDs: [id(52)], retaining: previous, isCurrent: { true })
        let read = try XCTUnwrap(result)
        XCTAssertEqual(Set(read.records.map(\.id)), Set([id(50), id(52)]))
        XCTAssertEqual(read.freshIDs, [id(50)])
        XCTAssertFalse(read.isComplete)
        XCTAssertNil(read.preferredInvoice(id: id(52)).flatMap { $0.id == id(52) ? $0 : nil })
    }

    func testLegacyDeniedOrContradictoryDetailsNeverRetainOldContents() async throws {
        let deniedOrForeign: [URLProtocolFixture.Reply] = [.init(403, problem(403)), .init(404, problem(404)),
            .init(200, invoice(52, job: 101)), .init(200, invoice(99)), .init(200, invoice(52, customer: 9))]
        for last in deniedOrForeign {
            let first = api([.init(200, page([invoice(50), invoice(52)]))])
            let previous = await JobDocumentsLoader.invoices(scope: scope(), api: first, knownIDs: [], retaining: nil, isCurrent: { true })
            let second = api([.init(405, problem(405)), .init(200, page([invoice(50)])), last])
            let result = await JobDocumentsLoader.invoices(scope: scope(), api: second, knownIDs: [id(52)], retaining: previous, isCurrent: { true })
            XCTAssertEqual(result?.records.map(\.id), [id(50)])
        }
    }

    func testFailedLinksCannotResurrectDeniedOrInvalidOriginEstimate() async throws {
        let rejected: [URLProtocolFixture.Reply] = [.init(401, problem(401)), .init(403, problem(403)),
            .init(404, problem(404)), .init(410, problem(410)), .init(200, estimate(10, customer: 9)), .init(200, estimate(99))]
        for last in rejected {
            let first = api([.init(200, page([])), .init(200, estimate(10))])
            let previous = await JobDocumentsLoader.estimates(scope: scope(origin: 10), api: first, retaining: nil, isCurrent: { true })
            let second = api([.init(503, problem(503)), last])
            let result = await JobDocumentsLoader.estimates(scope: scope(origin: 10), api: second, retaining: previous, isCurrent: { true })
            XCTAssertTrue(try XCTUnwrap(result).records.isEmpty)
            XCTAssertTrue(result?.freshIDs.isEmpty == true)
            XCTAssertFalse(result?.isComplete == true)
        }
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

    func testDiscountedOwedInvoiceRemainsPreferredOverNewerPaidDeposit() async throws {
        var discounted = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(invoice(50).utf8)) as? [String: Any])
        var lines = try XCTUnwrap(discounted["lines"] as? [[String: Any]])
        lines.append(["id": id(901), "description": "Customer discount", "quantity": 1,
                      "unitPrice": ["amount": -1500, "currency": "USD"]])
        discounted["lines"] = lines
        let discountedBody = try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: discounted), encoding: .utf8))
        let deposit = invoice(52, status: "paid", paid: 10000)
            .replacingOccurrences(of: "2026-10-01", with: "2026-10-02")
        let client = api([.init(200, page([deposit, discountedBody]))])
        let result = await JobDocumentsLoader.invoices(scope: scope(), api: client, knownIDs: [], retaining: nil, isCurrent: { true })
        let read = try XCTUnwrap(result)
        XCTAssertTrue(read.isComplete)
        XCTAssertEqual(read.preferredInvoice(id: nil)?.id, id(50))
        XCTAssertEqual(read.preferredInvoice(id: id(52))?.id, id(50))
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

    func testOlderInvoiceReadCannotReplaceNewerEmptySnapshotOrMemory() async throws {
        let scope = scope()
        let oldMemory = JobInvoiceMemory.ids(scope.jobID)
        defer { JobInvoiceMemory.replace(oldMemory, jobID: scope.jobID) }
        JobInvoiceMemory.replace([], jobID: scope.jobID)
        let gate = URLProtocolFixture.Gate()
        defer { gate.release() }
        let client = api([.init(200, page([invoice(50)]), gate: gate), .init(200, page([]))])
        let documents = JobDocumentCollections()
        let older = Task { await documents.loadInvoices(scope: scope, api: client, isCurrent: { true }) }
        for _ in 0..<300 where URLProtocolFixture.recorded.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        let newer = await documents.loadInvoices(scope: scope, api: client, isCurrent: { true })
        XCTAssertTrue(newer)
        gate.release()
        let obsolete = await older.value
        XCTAssertFalse(obsolete)
        XCTAssertEqual(documents.invoices?.records.map(\.id), [])
        XCTAssertEqual(JobInvoiceMemory.ids(scope.jobID), [])
    }

    func testMarkingEstimateReadStaleKeepsKnownRowsAndUnavailableReferences() async throws {
        let client = api([.init(200, page([link(11), link(12)])), .init(200, estimate(11)), .init(503, problem(503))])
        let documents = JobDocumentCollections()
        let loaded = await documents.loadEstimates(scope: scope(), api: client, isCurrent: { true })
        XCTAssertTrue(loaded)
        documents.markEstimatesStale(scope: scope(job: 101))
        XCTAssertEqual(documents.estimates?.freshIDs, [id(11)], "A different job cannot invalidate this collection")
        documents.markEstimatesStale(scope: scope())
        XCTAssertEqual(documents.estimates?.records.map(\.id), [id(11)])
        XCTAssertEqual(documents.estimates?.unavailableIDs, [id(12)])
        XCTAssertEqual(documents.estimates?.freshIDs, [])
        XCTAssertEqual(documents.estimates?.isComplete, false)
    }

    func testApprovalResultOnlyReplacesTheMatchingLinkedEstimateAndIsNotFresh() async throws {
        let client = api([.init(200, page([link(11), link(12)])), .init(200, estimate(11)), .init(200, estimate(12))])
        let documents = JobDocumentCollections()
        let loaded = await documents.loadEstimates(scope: scope(), api: client, isCurrent: { true })
        XCTAssertTrue(loaded)
        let updatedText = estimate(11).replacingOccurrences(of: "\"status\":\"sent\"", with: "\"status\":\"approved\"")
        let updated = try JSONDecoder().decode(EstimateRecord.self, from: Data(updatedText.utf8))
        documents.markEstimatesStale(scope: scope(), updated: updated, requestedID: id(12))
        XCTAssertEqual(documents.estimates?.records.first?.status, "sent", "An unrelated result must not replace either linked estimate")
        documents.markEstimatesStale(scope: scope(), updated: updated, requestedID: id(11))
        XCTAssertEqual(documents.estimates?.records.first?.status, "approved")
        XCTAssertEqual(documents.estimates?.freshIDs, [])
        documents.markEstimatesStale(scope: scope(), updated: nil, requestedID: id(11))
        XCTAssertEqual(documents.estimates?.freshIDs, [], "A nil public approval result cannot make old Sent status current")
    }

    func testMarkingStaleInvalidatesAnEarlierInFlightEstimateRead() async throws {
        let gate = URLProtocolFixture.Gate(); defer { gate.release() }
        let client = api([.init(200, page([link(11)])), .init(200, estimate(11)),
                          .init(200, page([link(11)]), gate: gate)])
        let documents = JobDocumentCollections()
        let loaded = await documents.loadEstimates(scope: scope(), api: client, isCurrent: { true })
        XCTAssertTrue(loaded)
        let older = Task { await documents.loadEstimates(scope: scope(), api: client, isCurrent: { true }) }
        for _ in 0..<300 where URLProtocolFixture.recorded.count < 3 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 3)
        documents.markEstimatesStale(scope: scope())
        gate.release()
        let published = await older.value
        XCTAssertFalse(published)
        XCTAssertEqual(documents.estimates?.records.map(\.id), [id(11)])
        XCTAssertEqual(documents.estimates?.freshIDs, [])
        XCTAssertFalse(documents.estimates?.isComplete ?? true)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 3)
    }

    func testOlderEstimateReadCannotReplaceNewerEmptySnapshot() async throws {
        let gate = URLProtocolFixture.Gate()
        defer { gate.release() }
        let client = api([.init(200, page([link(11)]), gate: gate), .init(200, page([]))])
        let documents = JobDocumentCollections()
        let older = Task { await documents.loadEstimates(scope: scope(), api: client, isCurrent: { true }) }
        for _ in 0..<300 where URLProtocolFixture.recorded.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        let newer = await documents.loadEstimates(scope: scope(), api: client, isCurrent: { true })
        XCTAssertTrue(newer)
        gate.release()
        let obsolete = await older.value
        XCTAssertFalse(obsolete)
        XCTAssertEqual(documents.estimates?.records.map(\.id), [])
        XCTAssertEqual(URLProtocolFixture.recorded.count, 2, "An obsolete link read must not request old details")
    }

    func testSharedCollectionsRecoverKnownInvoicesOnLegacyRefresh() async throws {
        let scope = scope()
        let oldMemory = JobInvoiceMemory.ids(scope.jobID)
        defer { JobInvoiceMemory.replace(oldMemory, jobID: scope.jobID) }
        JobInvoiceMemory.replace([id(50)], jobID: scope.jobID)
        let client = api([.init(404, problem(404)), .init(200, page([])), .init(200, invoice(50))])
        let documents = JobDocumentCollections()
        let published = await documents.loadInvoices(scope: scope, api: client, isCurrent: { true })
        XCTAssertTrue(published)
        XCTAssertEqual(documents.invoices?.records.map(\.id), [id(50)])
        XCTAssertEqual(documents.invoices?.freshIDs, [id(50)])
        XCTAssertEqual(documents.invoices?.isComplete, false)
    }

    private func api(_ replies: [URLProtocolFixture.Reply]) -> APIClient {
        APIClient(session: URLProtocolFixture.session(replies), baseURL: "https://app.thorbis.com")
    }

    func testJobEstimateCreationRequiresReadableDocumentsAndEstimateView() {
        XCTAssertFalse(JobEstimateCreation.canOpen(canCreate: true, canView: true, canEditJob: true, estimatesComplete: false))
        XCTAssertTrue(JobEstimateCreation.canOpen(canCreate: true, canView: true, canEditJob: true, estimatesComplete: true))
        XCTAssertFalse(JobEstimateCreation.canOpen(canCreate: true, canView: false, canEditJob: true, estimatesComplete: true))
        XCTAssertFalse(JobEstimateCreation.canOpen(canCreate: true, canView: true, canEditJob: false, estimatesComplete: true))
        XCTAssertFalse(JobEstimateCreation.canOpen(canCreate: false, canView: true, canEditJob: true, estimatesComplete: true))
    }

    func testFixedEstimateSummarySeparatesStatusAndCurrencyAndExcludesOptions() throws {
        let records = try [pricedEstimate(status: "approved", cents: 1000),
                           pricedEstimate(status: "approved", cents: 2000),
                           pricedEstimate(status: "sent", cents: 4000),
                           pricedEstimate(status: "sent", currency: "EUR", cents: 5000),
                           pricedEstimate(status: "draft", cents: 90000),
                           pricedEstimate(status: "sent", cents: 80000, options: true)]
        let summary = try XCTUnwrap(JobEstimateSummary(records: records, complete: true))
        XCTAssertEqual(summary.amounts, [.init(status: "approved", currency: "USD", cents: 3000),
                                         .init(status: "sent", currency: "EUR", cents: 5000),
                                         .init(status: "sent", currency: "USD", cents: 4000)])
        XCTAssertEqual(summary.optionCount, 1)
    }

    func testFixedEstimateSummaryIncludesDiscountInItsStatusCurrencyTotal() throws {
        let original = try pricedEstimate(status: "sent", cents: 10000)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        var lines = try XCTUnwrap(object["lines"] as? [[String: Any]])
        lines.append(["id": id(901), "description": "Customer discount", "quantity": 1,
                      "unitPrice": ["amount": -1500, "currency": "USD"]])
        object["lines"] = lines
        let discounted = try JSONDecoder().decode(EstimateRecord.self, from: JSONSerialization.data(withJSONObject: object))
        let other = try pricedEstimate(status: "sent", cents: 1000)
        let summary = try XCTUnwrap(JobEstimateSummary(records: [discounted, other], complete: true))
        XCTAssertEqual(summary.amounts, [.init(status: "sent", currency: "USD", cents: 9500)])
        XCTAssertEqual(summary.optionCount, 0)
    }

    func testEstimateSummaryNeverPublishesIncompleteInvalidOrOverflowTotals() throws {
        let good = try pricedEstimate(status: "sent", cents: 1000)
        XCTAssertNil(JobEstimateSummary(records: [good], complete: false))
        for bad in try [pricedEstimate(status: "sent", cents: -1),
                        pricedEstimate(status: "approved", cents: Int.max, quantity: 2),
                        pricedEstimate(status: "sent", cents: 1, quantity: -1)] {
            XCTAssertNil(JobEstimateSummary(records: [good, bad], complete: true))
        }
        let maximum = try pricedEstimate(status: "sent", cents: Int.max)
        XCTAssertNil(JobEstimateSummary(records: [maximum, good], complete: true))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(good)) as? [String: Any])
        var lines = try XCTUnwrap(object["lines"] as? [[String: Any]])
        lines.append(["id": id(999), "description": "Other currency", "quantity": 1,
                      "unitPrice": ["amount": 20, "currency": "EUR"]])
        object["lines"] = lines
        let mixed = try JSONDecoder().decode(EstimateRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(JobEstimateSummary(records: [mixed], complete: true))
    }

    private func pricedEstimate(status: String, currency: String = "USD", cents: Int,
                                quantity: Int = 1, options: Bool = false) throws -> EstimateRecord {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(PaperPreview.estimate)) as? [String: Any])
        object["status"] = status
        if !options { object["options"] = NSNull() }
        object["lines"] = [["id": id(900), "description": "Fixture service", "quantity": quantity,
                            "unitPrice": ["amount": cents, "currency": currency]]]
        return try JSONDecoder().decode(EstimateRecord.self, from: JSONSerialization.data(withJSONObject: object))
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
