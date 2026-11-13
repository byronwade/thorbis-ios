import XCTest
@testable import Thorbis

@MainActor
final class CustomerInvoiceOverviewTests: XCTestCase {
    func testSixHundredInvoicesStartAtMostThreeRequestsAndReadOnlyFirstTwenty() async throws {
        let org = "00000000-0000-4000-8000-000000000102"
        let customer = "00000000-0000-4000-8000-000000000103"
        let job = "00000000-0000-4000-8000-000000000104"
        let scope = JobDocumentScope(jobID: job, organizationID: org, customerID: customer)
        let gate = URLProtocolFixture.Gate(); defer { gate.release() }
        var records: [InvoiceRecord] = []
        var routes: [String: URLProtocolFixture.Reply] = [:]
        for index in 0..<600 {
            let id = String(format: "00000000-0000-4000-8000-%012d", index + 1000)
            let invoice: [String: Any] = ["id": id, "organizationId": org, "customerId": customer,
                "jobId": job, "createdByUserId": "00000000-0000-4000-8000-000000000105",
                "origin": "job_completion", "sourceOperationKey": job, "status": "issued", "lines": [],
                "linesRevision": 1, "amountPaid": 0, "currency": "USD", "createdAt": "2026-10-29T00:00:00Z", "updatedAt": "2026-10-29T00:00:00Z"]
            records.append(try JSONDecoder().decode(InvoiceRecord.self, from: JSONSerialization.data(withJSONObject: invoice)))
            if index < 40 {
                let payload: [String: Any] = ["kind": "customer_invoice_presentation", "presentationVersion": 1,
                    "presentationScopeId": "invoice:\(id):lines:1:customer:v1", "isSignedDocument": false,
                    "issuedSnapshotId": "00000000-0000-4000-8000-000000000106", "organizationId": org,
                    "customerId": customer, "invoiceId": id, "jobId": job, "linesRevision": 1, "status": "issued",
                    "currency": "USD", "lines": [], "totalAmount": 0, "amountPaid": 0, "balanceDue": 0]
                routes["/v1/invoices/\(id)/customer-presentation"] = .init(200, String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self), gate: gate)
            }
        }
        let firstPath = "/v1/invoices/\(records[0].id)/customer-presentation"
        let success = routes[firstPath]!
        routes[firstPath] = .init(503, "{}", gate: gate)
        let api = APIClient(session: URLProtocolFixture.session(routes: routes), baseURL: "https://app.thorbis.com")
        let authority = CustomerHandoffExitAuthority(actor: "actor", organization: org, origin: "https://app.thorbis.com",
            sessionGeneration: UUID(), authorityRevision: UUID(), requestGeneration: api.requestGeneration, scopeRevision: api.savedCopyScopeRevision)
        let loader = CustomerInvoiceOverviewLoader()
        let task = Task { @MainActor in await loader.load(records: records, api: api, scope: scope, authority: authority, current: { _ in true }) }
        for _ in 0..<1500 where URLProtocolFixture.recorded.count < 3 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 3, "Only three requests may begin while all responses are held")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(URLProtocolFixture.recorded.count, 3)
        gate.release(); await task.value
        XCTAssertEqual(URLProtocolFixture.recorded.count, 20)
        XCTAssertEqual(loader.entries.count, 19)
        routes[firstPath] = success
        URLProtocolFixture.setRoutes(routes)
        XCTAssertEqual(loader.failedIDs, [records[0].id])
        await loader.retryFailed()
        XCTAssertTrue(loader.failedIDs.isEmpty)
        XCTAssertNotNil(loader.entries[records[0].id], "A transient failure must be retried")
        XCTAssertTrue(loader.canLoadMore)
        await loader.loadMore()
        XCTAssertEqual(URLProtocolFixture.recorded.count, 21)
        XCTAssertEqual(loader.entries.count, 40, "The next page retains previously verified amounts")
        XCTAssertTrue(loader.canLoadMore)

        // Leaving the screen retires its generation before delayed replies are released.
        let retiredGate = URLProtocolFixture.Gate(); defer { retiredGate.release() }
        let delayed = routes.mapValues { URLProtocolFixture.Reply($0.status, $0.body, gate: retiredGate) }
        URLProtocolFixture.setRoutes(delayed)
        let oldTask = Task { @MainActor in await loader.load(records: records, api: api, scope: scope, authority: authority, current: { _ in true }) }
        for _ in 0..<1500 where URLProtocolFixture.recorded.count < 3 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 3)
        loader.retire(); retiredGate.release(); await oldTask.value
        XCTAssertTrue(loader.entries.isEmpty, "Retired responses must never repopulate the overview")
        XCTAssertTrue(loader.failedIDs.isEmpty, "Retirement must clear retry state")
        XCTAssertEqual(URLProtocolFixture.recorded.count, 3, "A retired batch must not start more requests")
    }
}
