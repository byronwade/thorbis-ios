import XCTest
@testable import Thorbis

@MainActor
final class CustomerCompilationConcurrencyTests: XCTestCase {
    func testScopedCacheGenerationRetiresOldPagesWithoutAffectingAnotherCustomer() {
        let path = "/v1/customers/\(CustomerCompilationRoutingProtocol.customer)/history"
        let query = [URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "cursor", value: "older")]
        let old = SavedCopies.key(origin: "https://app.thorbis.com", path: path, query: query, namespace: "customer-a-epoch-1")
        let new = SavedCopies.key(origin: "https://app.thorbis.com", path: path, query: query, namespace: "customer-a-epoch-2")
        let other = SavedCopies.key(origin: "https://app.thorbis.com", path: path, query: query, namespace: "customer-b-epoch-1")
        XCTAssertNotEqual(old, new)
        XCTAssertNotEqual(other, old)
        XCTAssertNotEqual(other, new)
        XCTAssertEqual(other, SavedCopies.key(origin: "https://app.thorbis.com", path: path, query: query, namespace: "customer-b-epoch-1"))
        XCTAssertNotEqual(old, SavedCopies.key(origin: "https://app.thorbis.com", path: path, query: query))
    }

    func testRotatedCustomerNamespaceCannotReadOldOfflinePageButOtherCustomerCan() async throws {
        let a = #"{"items":[{"occurredAt":"2026-07-01T00:00:00Z","kind":"job","subjectId":"a","summary":"Old A"}]}"#
        let b = #"{"items":[{"occurredAt":"2026-07-01T00:00:00Z","kind":"job","subjectId":"b","summary":"Stable B"}]}"#
        let api = APIClient(session: URLProtocolFixture.session([.init(200, a), .init(200, b), URLProtocolFixture.offline]), baseURL: "https://app.thorbis.com")
        api.savedCopyScope = "customer-cache-generation-\(UUID().uuidString)"
        let customer = CustomerCompilationRoutingProtocol.customer
        _ = try await SavedCopies.$customerNamespace.withValue("customer-a-old") { try await api.fieldCustomerHistory(customer) }
        _ = try await SavedCopies.$customerNamespace.withValue("customer-b") { try await api.fieldCustomerHistory(customer) }
        let scope = try XCTUnwrap(api.savedCopyScope)
        let path = "/v1/customers/\(customer)/history"
        let query = [URLQueryItem(name: "limit", value: "50")]
        let aKey = SavedCopies.key(origin: "https://app.thorbis.com", path: path, query: query, namespace: "customer-a-old")
        let bKey = SavedCopies.key(origin: "https://app.thorbis.com", path: path, query: query, namespace: "customer-b")
        for _ in 0..<100 where !SavedCopyStore.shared.exists(scope: scope, key: aKey) || !SavedCopyStore.shared.exists(scope: scope, key: bKey) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(SavedCopyStore.shared.exists(scope: scope, key: aKey))
        XCTAssertTrue(SavedCopyStore.shared.exists(scope: scope, key: bKey))
        api.invalidateRequests()
        api.knownOffline = true
        do {
            _ = try await SavedCopies.$customerNamespace.withValue("customer-a-new") { try await api.fieldCustomerHistory(customer) }
            XCTFail("A rotated generation cannot recover its old offline page")
        } catch let problem as Problem { XCTAssertNil(problem.status) }
        let retained = try await SavedCopies.$customerNamespace.withValue("customer-b") { try await api.fieldCustomerHistory(customer) }
        XCTAssertEqual(retained.items.map(\.summary), ["Stable B"])
    }

    func testGuardedCustomerCacheDoesNotUseAnExpiredOfflinePage() async throws {
        let response = #"{"items":[{"occurredAt":"2026-07-01T00:00:00Z","kind":"job","subjectId":"a","summary":"Old"}]}"#
        let api = APIClient(session: URLProtocolFixture.session([.init(200, response), URLProtocolFixture.offline]), baseURL: "https://app.thorbis.com")
        api.savedCopyScope = "customer-cache-expiry-\(UUID().uuidString)"
        let customer = CustomerCompilationRoutingProtocol.customer
        let namespace = "expiry-generation"
        _ = try await SavedCopies.$customerNamespace.withValue(namespace) { try await api.fieldCustomerHistory(customer) }
        let scope = try XCTUnwrap(api.savedCopyScope)
        let key = SavedCopies.key(origin: "https://app.thorbis.com", path: "/v1/customers/\(customer)/history",
                                  query: [URLQueryItem(name: "limit", value: "50")], namespace: namespace)
        for _ in 0..<100 where !SavedCopyStore.shared.exists(scope: scope, key: key) { try await Task.sleep(for: .milliseconds(10)) }
        let base = try XCTUnwrap(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        let file = base.appendingPathComponent("SavedCopies").appendingPathComponent(scope).appendingPathComponent("\(key).json")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-15 * 86_400)], ofItemAtPath: file.path)
        api.invalidateRequests()
        api.knownOffline = true
        do {
            _ = try await SavedCopies.$customerNamespace.withValue(namespace) { try await api.fieldCustomerHistory(customer) }
            XCTFail("An expired guarded copy must require a live refresh")
        } catch let problem as Problem { XCTAssertNil(problem.status) }
    }

    func testGuardedUpgradeDoesNotReuseUnverifiedLegacyCustomerCopyOffline() async throws {
        let api = APIClient(session: URLProtocolFixture.session([.init(200, #"{"items":[]}"#), URLProtocolFixture.offline]), baseURL: "https://app.thorbis.com")
        api.savedCopyScope = "customer-cache-upgrade-\(UUID().uuidString)"
        let customer = CustomerCompilationRoutingProtocol.customer
        _ = try await api.fieldCustomerHistory(customer)
        let scope = try XCTUnwrap(api.savedCopyScope)
        let key = SavedCopies.key(origin: "https://app.thorbis.com", path: "/v1/customers/\(customer)/history", query: [URLQueryItem(name: "limit", value: "50")])
        for _ in 0..<100 where !SavedCopyStore.shared.exists(scope: scope, key: key) { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(SavedCopyStore.shared.exists(scope: scope, key: key))
        api.invalidateRequests()
        api.knownOffline = true
        do {
            _ = try await SavedCopies.$customerNamespace.withValue("first-guarded-generation") { try await api.fieldCustomerHistory(customer) }
            XCTFail("An unverified legacy copy cannot become an authorized guarded copy")
        } catch let problem as Problem { XCTAssertNil(problem.status) }
    }

    func testGuardedCacheAgeBoundariesRejectExpiredAndFutureCopies() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        XCTAssertTrue(SavedCopies.guardedCopyIsFresh(savedAt: now.addingTimeInterval(-14 * 86_400), now: now))
        XCTAssertFalse(SavedCopies.guardedCopyIsFresh(savedAt: now.addingTimeInterval(-14 * 86_400 - 1), now: now))
        XCTAssertFalse(SavedCopies.guardedCopyIsFresh(savedAt: now.addingTimeInterval(1), now: now))
    }
    func testLiveVerificationDoesNotTreatDeniedMediaAsAnAuthorizedCompilation() async throws {
        for status in [403, 404] {
            CustomerCompilationRoutingProtocol.reset(mediaStatus: status)
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [CustomerCompilationRoutingProtocol.self]
            let api = APIClient(session: URLSession(configuration: config), baseURL: "https://app.thorbis.com")
            do {
                _ = try await SavedCopies.$liveOnly.withValue(true) {
                    try await CustomerJobCompilationLoader.verifyAvailableReads(customerID: CustomerCompilationRoutingProtocol.customer,
                        organizationID: CustomerCompilationRoutingProtocol.org, api: api,
                        access: CustomerRecordAccess(estimates: false, invoices: false), isCurrent: { true })
                }
                XCTFail("A \(status) child denial cannot prove an authorized live compilation")
            } catch let problem as Problem {
                XCTAssertEqual(problem.status, status)
            }
        }
    }

    func testOrdinaryCustomerReadsKeepPartialMediaOnDeniedOrMissingJobMedia() async throws {
        for status in [403, 404] {
            CustomerCompilationRoutingProtocol.reset(mediaStatus: status)
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [CustomerCompilationRoutingProtocol.self]
            let api = APIClient(session: URLSession(configuration: config), baseURL: "https://app.thorbis.com")
            let result = try await CustomerJobCompilationLoader.load(customerID: CustomerCompilationRoutingProtocol.customer,
                organizationID: CustomerCompilationRoutingProtocol.org, api: api,
                access: CustomerRecordAccess(estimates: false, invoices: false))
            XCTAssertTrue(result.mediaIncompleteJobIDs.contains(CustomerCompilationRoutingProtocol.jobs[0]))
        }
    }

    func testStrictCompilationRequiresFreshReadsBeforeAnyRequest() async throws {
        CustomerCompilationRoutingProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CustomerCompilationRoutingProtocol.self]
        let api = APIClient(session: URLSession(configuration: config), baseURL: "https://app.thorbis.com")
        do {
            _ = try await CustomerJobCompilationLoader.verifyAvailableReads(customerID: CustomerCompilationRoutingProtocol.customer,
                organizationID: CustomerCompilationRoutingProtocol.org, api: api,
                access: CustomerRecordAccess(estimates: false, invoices: false), isCurrent: { true })
            XCTFail("Strict verification must require the live-only transport")
        } catch let problem as Problem {
            XCTAssertEqual(problem.title, "Live verification required")
        }
        XCTAssertTrue(CustomerCompilationRoutingProtocol.paths.isEmpty)
    }

    func testStrictCompilationRefusesRetiredSessionBeforeAnyRequest() async throws {
        CustomerCompilationRoutingProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CustomerCompilationRoutingProtocol.self]
        let api = APIClient(session: URLSession(configuration: config), baseURL: "https://app.thorbis.com")
        do {
            _ = try await SavedCopies.$liveOnly.withValue(true) {
                try await CustomerJobCompilationLoader.verifyAvailableReads(customerID: CustomerCompilationRoutingProtocol.customer,
                    organizationID: CustomerCompilationRoutingProtocol.org, api: api,
                    access: CustomerRecordAccess(estimates: false, invoices: false), isCurrent: { false })
            }
            XCTFail("A retired session cannot verify records")
        } catch is CancellationError { }
        XCTAssertTrue(CustomerCompilationRoutingProtocol.paths.isEmpty)
    }
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
