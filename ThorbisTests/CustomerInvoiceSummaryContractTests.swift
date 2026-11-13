import XCTest
@testable import Thorbis

@MainActor
final class CustomerInvoiceSummaryContractTests: XCTestCase {
    private let scope = JobDocumentScope(jobID: "job-1", organizationID: "org-1", customerID: "customer-1")
    private func decode(_ changes: [String: Any] = [:]) throws -> CustomerInvoiceSummary {
        var payload: [String: Any] = [
            "kind": "customer_invoice_presentation", "presentationVersion": 1,
            "presentationScopeId": "invoice:invoice-1:lines:2:customer:v1", "isSignedDocument": false,
            "issuedSnapshotId": "00000000-0000-4000-8000-000000000001", "organizationId": "org-1", "customerId": "customer-1",
            "invoiceId": "invoice-1", "jobId": "job-1", "linesRevision": 2,
            "status": "issued", "currency": "USD", "totalAmount": 10000, "amountPaid": 2500,
            "balanceDue": 7500, "lines": [["id": "line-1", "description": "Materials", "quantity": 1,
                                              "unitPrice": ["amount": 10000, "currency": "USD"]]]
        ]
        changes.forEach { payload[$0.key] = $0.value }
        return try JSONDecoder().decode(CustomerInvoiceSummary.self, from: JSONSerialization.data(withJSONObject: payload))
    }
    func testAcceptsOnlyMatchingUnsignedScopedPresentationWithReconciledAmounts() throws {
        XCTAssertTrue(try decode().matches(scope: scope, invoiceID: "invoice-1", linesRevision: 2))
        for override in [["organizationId": "other"], ["customerId": "other"], ["jobId": "other"],
                         ["invoiceId": "other"], ["linesRevision": 3], ["presentationVersion": 2],
                         ["kind": "invoice"], ["isSignedDocument": true], ["issuedSnapshotId": NSNull()], ["issuedSnapshotId": "invalid"],
                         ["totalAmount": 1], ["balanceDue": 1], ["currency": "EUR"]] as [[String: Any]] {
            XCTAssertFalse(try decode(override).matches(scope: scope, invoiceID: "invoice-1", linesRevision: 2))
        }
        XCTAssertFalse(try decode(["status": "draft", "amountPaid": 0, "balanceDue": 10000]).matches(scope: scope, invoiceID: "invoice-1", linesRevision: 2))
        XCTAssertFalse(try decode(["status": "paid", "totalAmount": 0, "amountPaid": 0, "balanceDue": 0, "lines": []]).matches(scope: scope, invoiceID: "invoice-1", linesRevision: 2))
        XCTAssertFalse(try decode(["status": "issued", "amountPaid": 10000, "balanceDue": 0]).matches(scope: scope, invoiceID: "invoice-1", linesRevision: 2))
    }
    func testStandaloneSummaryRequiresNoJobAndMatchingCustomer() throws {
        let summary = try decode(["jobId": NSNull()])
        XCTAssertTrue(summary.matches(organizationID: "org-1", customerID: "customer-1", jobID: nil, invoiceID: "invoice-1", linesRevision: 2))
        XCTAssertFalse(summary.matches(organizationID: "org-1", customerID: "other", jobID: nil, invoiceID: "invoice-1", linesRevision: 2))
        XCTAssertFalse(summary.matches(organizationID: "org-1", customerID: "customer-1", jobID: "job-1", invoiceID: "invoice-1", linesRevision: 2))
    }

    func testSummaryReadRequiresFreshServerAndMatchingScope() async throws {
        let id = "00000000-0000-4000-8000-000000000101"
        let jobScope = JobDocumentScope(jobID: "job-1", organizationID: "org-1", customerID: "customer-1")
        let json = try responseJSON(id: id)
        let api = APIClient(session: URLProtocolFixture.session([.init(200, json)]), baseURL: "https://app.thorbis.com")
        let summary = try await api.customerInvoiceSummary(scope: jobScope, invoiceID: id, linesRevision: 2, currentAuthority: { true })
        XCTAssertEqual(summary.lines.first?.description, "Materials")
        XCTAssertEqual(URLProtocolFixture.recorded.last?.url?.path, "/v1/invoices/\(id)/customer-presentation")
        XCTAssertEqual(URLProtocolFixture.recorded.last?.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testSummaryReadRejectsOfflineAndMismatchedJob() async throws {
        let id = "00000000-0000-4000-8000-000000000101"
        let jobScope = JobDocumentScope(jobID: "job-1", organizationID: "org-1", customerID: "customer-1")
        let api = APIClient(session: URLProtocolFixture.session([URLProtocolFixture.offline, .init(200, try responseJSON(id: id, job: "other"))]), baseURL: "https://app.thorbis.com")
        let cacheScope = "customer-invoice-summary-\(UUID().uuidString)"
        api.savedCopyScope = cacheScope
        let path = "/v1/invoices/\(id)/customer-presentation"
        let key = SavedCopies.key(origin: "https://app.thorbis.com", path: path, query: [])
        let saved = Data(try responseJSON(id: id).utf8)
        SavedCopyStore.shared.write(saved, scope: cacheScope, key: key)
        SavedCopyStore.shared.waitForQueuedWrites()
        XCTAssertEqual(SavedCopyStore.shared.read(scope: cacheScope, key: key)?.data, saved)
        do { _ = try await api.customerInvoiceSummary(scope: jobScope, invoiceID: id, linesRevision: 2, currentAuthority: { true }); XCTFail("Offline response must not use cached or raw invoice lines") } catch { }
        do { _ = try await api.customerInvoiceSummary(scope: jobScope, invoiceID: id, linesRevision: 2, currentAuthority: { true }); XCTFail("A different job must not be displayed") } catch { }
    }

    func testSummaryReadDiscardsResponseAfterAuthorityChanges() async throws {
        let id = "00000000-0000-4000-8000-000000000101"
        let jobScope = JobDocumentScope(jobID: "job-1", organizationID: "org-1", customerID: "customer-1")
        let gate = URLProtocolFixture.Gate(); defer { gate.release() }
        let api = APIClient(session: URLProtocolFixture.session([.init(200, try responseJSON(id: id), gate: gate)]), baseURL: "https://app.thorbis.com")
        var authorized = true
        let task = Task { @MainActor in try await api.customerInvoiceSummary(scope: jobScope, invoiceID: id, linesRevision: 2, currentAuthority: { authorized }) }
        for _ in 0..<1500 where URLProtocolFixture.recorded.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        authorized = false; gate.release()
        do { _ = try await task.value; XCTFail("A response under retired authority must be discarded") } catch is CancellationError { } catch { XCTFail("Expected cancellation, got \(error)") }
    }

    private func responseJSON(id: String, job: String = "job-1") throws -> String {
        let response: [String: Any] = ["kind": "customer_invoice_presentation", "presentationVersion": 1,
            "presentationScopeId": "invoice:\(id):lines:2:customer:v1", "isSignedDocument": false,
            "issuedSnapshotId": "00000000-0000-4000-8000-000000000001", "organizationId": "org-1", "customerId": "customer-1",
            "invoiceId": id, "jobId": job, "linesRevision": 2, "status": "issued", "currency": "USD",
            "totalAmount": 10000, "amountPaid": 2500, "balanceDue": 7500,
            "lines": [["id": "line-1", "description": "Materials", "quantity": 1, "unitPrice": ["amount": 10000, "currency": "USD"]]]]
        return String(decoding: try JSONSerialization.data(withJSONObject: response), as: UTF8.self)
    }

}
