import XCTest
@testable import Thorbis

@MainActor
final class CustomerCompilationConcurrencyTests: XCTestCase {
    func testJobReadsOverlapWithinBoundAndKeepGroupsInJobOrder() async throws {
        CustomerCompilationRoutingProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CustomerCompilationRoutingProtocol.self]
        let api = APIClient(session: URLSession(configuration: config), baseURL: "https://app.thorbis.com")
        let result = try await CustomerJobCompilationLoader.load(
            customerID: CustomerCompilationRoutingProtocol.customer,
            organizationID: CustomerCompilationRoutingProtocol.org,
            api: api,
            access: CustomerRecordAccess(estimates: false, invoices: false)
        )
        XCTAssertEqual(result.notes.map(\.jobID), CustomerCompilationRoutingProtocol.jobs)
        XCTAssertEqual(result.notes.map(\.count), [1, 1, 1, 1, 1, 1])
        XCTAssertGreaterThan(CustomerCompilationRoutingProtocol.peak, 1, "Job requests should overlap")
        XCTAssertLessThanOrEqual(CustomerCompilationRoutingProtocol.peak, 4, "Job reads must be bounded")
        XCTAssertNotEqual(CustomerCompilationRoutingProtocol.noteCompletionOrder.first, CustomerCompilationRoutingProtocol.jobs[0], "The slow first job should finish out of order")
    }

    func testConcurrentFinancialReadsPreserveScopeAndCustomerInvoicePrecedence() async throws {
        CustomerCompilationRoutingProtocol.reset(financial: true)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CustomerCompilationRoutingProtocol.self]
        let api = APIClient(session: URLSession(configuration: config), baseURL: "https://app.thorbis.com")
        let result = try await CustomerJobCompilationLoader.load(
            customerID: CustomerCompilationRoutingProtocol.customer,
            organizationID: CustomerCompilationRoutingProtocol.org, api: api)
        XCTAssertEqual(result.estimates.first?.jobID, CustomerCompilationRoutingProtocol.jobs[0])
        XCTAssertEqual(result.estimates.first?.items.map(\.id), [CustomerCompilationRoutingProtocol.estimate])
        XCTAssertTrue(result.estimatesIncomplete, "Cross-job links are excluded and marked incomplete")
        XCTAssertTrue(result.invoicesIncomplete, "Cross-job invoice results are excluded and marked incomplete")
        XCTAssertEqual(result.invoiceCount, 1)
        XCTAssertEqual(result.invoices.first?.items.first?.status, "draft", "The customer-level invoice wins over a duplicate job response")
    }

    func testConcurrentJobInvoiceServerFailureFailsCompilation() async throws {
        CustomerCompilationRoutingProtocol.reset(financial: true, jobInvoiceFailure: true)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CustomerCompilationRoutingProtocol.self]
        let api = APIClient(session: URLSession(configuration: config), baseURL: "https://app.thorbis.com")
        do {
            _ = try await CustomerJobCompilationLoader.load(
                customerID: CustomerCompilationRoutingProtocol.customer,
                organizationID: CustomerCompilationRoutingProtocol.org, api: api)
            XCTFail("A 500 job invoice response must fail the customer compilation")
        } catch let problem as Problem { XCTAssertEqual(problem.status, 500) }
    }

    func testRetiredAuthorityDoesNotRequestSecondPage() async throws {
        CustomerCompilationRoutingProtocol.reset(paginatedJobs: true)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CustomerCompilationRoutingProtocol.self]
        let api = APIClient(session: URLSession(configuration: config), baseURL: "https://app.thorbis.com")
        var authorityCurrent = true
        let task = Task { @MainActor in
            _ = try await CustomerJobCompilationLoader.load(
                customerID: CustomerCompilationRoutingProtocol.customer,
                organizationID: CustomerCompilationRoutingProtocol.org, api: api,
                access: CustomerRecordAccess(estimates: false, invoices: false),
                isCurrent: { authorityCurrent })
        }
        for _ in 0..<100 where !CustomerCompilationRoutingProtocol.paths.contains("/v1/jobs") {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(CustomerCompilationRoutingProtocol.paths.contains("/v1/jobs"))
        authorityCurrent = false
        do { try await task.value; XCTFail("Retired authority must stop the paginated read") }
        catch is CancellationError {}
        catch { XCTFail("Expected cancellation, got \(error)") }
        XCTAssertEqual(CustomerCompilationRoutingProtocol.paths.filter { $0 == "/v1/jobs" }.count, 1,
                       "A second page must not be requested after authority is retired")
    }

    func testAuthorityRetirementStopsCompilation() async throws {
        CustomerCompilationRoutingProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CustomerCompilationRoutingProtocol.self]
        let api = APIClient(session: URLSession(configuration: config), baseURL: "https://app.thorbis.com")
        var authorityCurrent = true
        let task = Task { @MainActor in
            _ = try await CustomerJobCompilationLoader.load(
                customerID: CustomerCompilationRoutingProtocol.customer,
                organizationID: CustomerCompilationRoutingProtocol.org, api: api,
                access: CustomerRecordAccess(estimates: false, invoices: false),
                isCurrent: { authorityCurrent })
        }
        for _ in 0..<100 where CustomerCompilationRoutingProtocol.peak == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThan(CustomerCompilationRoutingProtocol.peak, 0)
        authorityCurrent = false
        do { try await task.value; XCTFail("Retired authority must not publish customer records") }
        catch is CancellationError {}
        catch { XCTFail("Expected cancellation, got \(error)") }
    }

    func testCancellationDuringJobReadsStopsCompilation() async throws {
        CustomerCompilationRoutingProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CustomerCompilationRoutingProtocol.self]
        let api = APIClient(session: URLSession(configuration: config), baseURL: "https://app.thorbis.com")
        let task = Task { @MainActor in
            _ = try await CustomerJobCompilationLoader.load(
                customerID: CustomerCompilationRoutingProtocol.customer,
                organizationID: CustomerCompilationRoutingProtocol.org,
                api: api, access: CustomerRecordAccess(estimates: false, invoices: false))
        }
        for _ in 0..<100 where CustomerCompilationRoutingProtocol.peak == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThan(CustomerCompilationRoutingProtocol.peak, 0)
        task.cancel()
        do { try await task.value; XCTFail("Canceled customer data must not publish") }
        catch is CancellationError {}
        catch { XCTFail("Expected cancellation, got \(error)") }
    }

    func testRequestGenerationChangeDuringJobReadsCancelsCompilation() async throws {
        CustomerCompilationRoutingProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CustomerCompilationRoutingProtocol.self]
        let api = APIClient(session: URLSession(configuration: config), baseURL: "https://app.thorbis.com")
        let task = Task { @MainActor in
            _ = try await CustomerJobCompilationLoader.load(
                customerID: CustomerCompilationRoutingProtocol.customer,
                organizationID: CustomerCompilationRoutingProtocol.org,
                api: api, access: CustomerRecordAccess(estimates: false, invoices: false))
        }
        for _ in 0..<100 where CustomerCompilationRoutingProtocol.peak == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThan(CustomerCompilationRoutingProtocol.peak, 0)
        api.invalidateRequests()
        do {
            _ = try await task.value
            XCTFail("An old API generation must never publish the combined customer records")
        } catch is CancellationError {
        } catch { XCTFail("Expected cancellation, got \(error)") }
    }

    func testUnauthorizedMediaFailsRatherThanReturningPartialCustomerData() async throws {
        CustomerCompilationRoutingProtocol.reset(mediaStatus: 401)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CustomerCompilationRoutingProtocol.self]
        let api = APIClient(session: URLSession(configuration: config), baseURL: "https://app.thorbis.com")
        do {
            _ = try await CustomerJobCompilationLoader.load(
                customerID: CustomerCompilationRoutingProtocol.customer,
                organizationID: CustomerCompilationRoutingProtocol.org,
                api: api, access: CustomerRecordAccess(estimates: false, invoices: false))
            XCTFail("An unauthorized job media read must fail the compilation")
        } catch let problem as Problem { XCTAssertEqual(problem.status, 401) }
    }

    func testConcurrentJobReadsKeepForeignNotesOutAndMarkFailedMediaIncomplete() async throws {
        CustomerCompilationRoutingProtocol.reset(failFirstMedia: true, includeForeignNote: true)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CustomerCompilationRoutingProtocol.self]
        let api = APIClient(session: URLSession(configuration: config), baseURL: "https://app.thorbis.com")
        let result = try await CustomerJobCompilationLoader.load(
            customerID: CustomerCompilationRoutingProtocol.customer,
            organizationID: CustomerCompilationRoutingProtocol.org,
            api: api,
            access: CustomerRecordAccess(estimates: false, invoices: false)
        )
        XCTAssertTrue(result.notesIncomplete)
        XCTAssertEqual(result.noteCount, 6)
        XCTAssertEqual(result.mediaIncompleteJobIDs, [CustomerCompilationRoutingProtocol.jobs[0]])
        XCTAssertEqual(result.documentIncompleteJobIDs, [CustomerCompilationRoutingProtocol.jobs[0]])
        XCTAssertFalse(CustomerCompilationRoutingProtocol.paths.contains("/v1/jobs/\(CustomerCompilationRoutingProtocol.jobs[0])/photos"))
    }
}

private final class CustomerCompilationRoutingProtocol: URLProtocol, @unchecked Sendable {
    static let org = "00000000-0000-4000-8000-000000000001"
    static let customer = "00000000-0000-4000-8000-000000000002"
    static let jobs = (10..<16).map { String(format: "00000000-0000-4000-8000-%012d", $0) }
    static let estimate = "00000000-0000-4000-8000-000000000101"
    static let invoice = "00000000-0000-4000-8000-000000000102"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var run = 0
    nonisolated(unsafe) private static var active = 0
    nonisolated(unsafe) private static var high = 0
    nonisolated(unsafe) private static var mediaStatus: Int? = nil
    nonisolated(unsafe) private static var foreignNote = false
    nonisolated(unsafe) private static var financial = false
    nonisolated(unsafe) private static var invoiceFailure = false
    nonisolated(unsafe) private static var paginatedJobs = false
    nonisolated(unsafe) private static var requestedPaths: [String] = []
    nonisolated(unsafe) private static var completedNotes: [String] = []
    static var noteCompletionOrder: [String] { lock.lock(); defer { lock.unlock() }; return completedNotes }
    static var paths: [String] { lock.lock(); defer { lock.unlock() }; return requestedPaths }
    static var peak: Int { lock.lock(); defer { lock.unlock() }; return high }
    static func reset(failFirstMedia: Bool = false, includeForeignNote: Bool = false, mediaStatus: Int? = nil, financial: Bool = false, jobInvoiceFailure: Bool = false, paginatedJobs: Bool = false) {
        lock.lock(); run += 1; active = 0; high = 0; self.mediaStatus = mediaStatus ?? (failFirstMedia ? 500 : nil); foreignNote = includeForeignNote; self.financial = financial; invoiceFailure = jobInvoiceFailure; self.paginatedJobs = paginatedJobs; requestedPaths = []; completedNotes = []; lock.unlock()
    }
    private let stateLock = NSLock()
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        Self.lock.lock(); Self.requestedPaths.append(path); let mediaStatus = Self.mediaStatus; let addForeign = Self.foreignNote; let financial = Self.financial; let invoiceFailure = Self.invoiceFailure; let paginatedJobs = Self.paginatedJobs; let run = Self.run; Self.lock.unlock()
        let jobID = Self.jobs.first { path.contains($0) }
        let isNotes = path.hasSuffix("/notes") && jobID != nil
        if isNotes {
            Self.lock.lock(); Self.active += 1; Self.high = max(Self.high, Self.active); Self.lock.unlock()
        }
        var items: [[String: Any]]
        if path == "/v1/jobs" {
            items = Self.jobs.map { ["id": $0, "organizationId": Self.org, "customerId": Self.customer,
                                     "title": "Job \($0.suffix(2))", "status": "completed",
                                     "createdAt": "2026-07-01T12:00:00Z", "updatedAt": "2026-07-01T12:00:00Z"] }
        } else if isNotes, let jobID {
            items = [["id": jobID, "organizationId": Self.org, "jobId": jobID, "authorUserId": Self.org,
                      "body": "Scoped note", "createdAt": "2026-07-01T12:00:00Z"]]
        } else if financial && path == "/v1/estimates" {
            items = [["id": Self.estimate, "organizationId": Self.org, "customerId": Self.customer,
                      "createdByUserId": Self.org, "title": "Estimate", "status": "draft", "lines": [],
                      "createdAt": "2026-07-01T12:00:00Z", "updatedAt": "2026-07-01T12:00:00Z"]]
        } else if financial && path == "/v1/invoices" {
            items = [Self.invoiceObject(job: Self.jobs[0], status: "draft")]
        } else if financial && path == "/v1/jobs/\(Self.jobs[0])/estimates" {
            items = [["id": Self.invoice, "jobId": Self.jobs[0], "estimateId": Self.estimate],
                     ["id": Self.customer, "jobId": Self.jobs[1], "estimateId": Self.estimate]]
        } else if financial && path == "/v1/jobs/\(Self.jobs[0])/invoices" {
            items = [Self.invoiceObject(job: Self.jobs[0], status: "issued"),
                     Self.invoiceObject(job: Self.jobs[1], status: "issued")]
        } else { items = [] }
        if isNotes && addForeign && jobID == Self.jobs[0] {
            items.append(["id": Self.customer, "organizationId": Self.org, "jobId": Self.jobs[1], "authorUserId": Self.org, "body": "Foreign", "createdAt": "2026-07-01T12:00:00Z"])
        }
        let status: Int
        if path == "/v1/jobs/\(Self.jobs[0])/media" { status = mediaStatus ?? 200 }
        else if financial && path == "/v1/jobs/\(Self.jobs[1])/invoices" { status = invoiceFailure ? 500 : 404 }
        else if financial && path == "/v1/jobs/\(Self.jobs[2])/invoices" { status = 405 }
        else { status = 200 }
        let failure = status != 200
        let firstJobsPage = paginatedJobs && path == "/v1/jobs" &&
            !(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "cursor" } ?? false)
        var responseBody: [String: Any] = failure ? ["title": "Unavailable", "status": status] : ["items": items]
        if firstJobsPage { responseBody["nextCursor"] = "next-page" }
        let payload = try! JSONSerialization.data(withJSONObject: responseBody)
        let reply: @Sendable () -> Void = { [self] in
            if isNotes { Self.lock.lock(); if Self.run == run { Self.active -= 1; if let jobID { Self.completedNotes.append(jobID) } }; Self.lock.unlock() }
            guard !stateLock.withLock({ stopped }) else { return }
            guard let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil) else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: payload)
            client?.urlProtocolDidFinishLoading(self)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + (firstJobsPage ? 0.2 : (isNotes ? (jobID == Self.jobs[0] ? 0.2 : 0.05) : 0.001)), execute: reply)
    }
    private static func invoiceObject(job: String, status: String) -> [String: Any] {
        ["id": invoice, "organizationId": org, "customerId": customer, "jobId": job,
         "createdByUserId": org, "origin": "manual", "sourceOperationKey": "fixture", "status": status,
         "lines": [], "linesRevision": 1, "amountPaid": 0, "currency": "USD",
         "createdAt": "2026-07-01T12:00:00Z", "updatedAt": "2026-07-01T12:00:00Z"]
    }
    override func stopLoading() { stateLock.withLock { stopped = true } }
}
