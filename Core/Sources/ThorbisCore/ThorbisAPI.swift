import Foundation

/// How requests prove who is calling.
public enum Credentials: Sendable, Equatable, Codable {
    case none
    /// Better Auth session cookies (name → value), captured from Set-Cookie and
    /// replayed on every request. Persisted by the app in the Keychain.
    case session([String: String])
    /// Loopback-only dev headers accepted by `createDevHeaderIdentityResolver`.
    case devHeaders(user: String, organization: String, roles: String)

    public var isSignedIn: Bool { self != .none }
}

/// Where the API lives. Production serves `/v1` and `/api/auth` on the app origin (ADR-0055).
public struct APIEnvironment: Sendable, Hashable, Codable, Identifiable {
    public let name: String
    public let baseURL: URL
    public var id: String { baseURL.absoluteString }

    public init(name: String, baseURL: URL) {
        self.name = name; self.baseURL = baseURL
    }

    public static let production = APIEnvironment(name: "Thorbis", baseURL: URL(string: "https://app.thorbis.com")!)
    public static let local = APIEnvironment(name: "Local API", baseURL: URL(string: "http://127.0.0.1:8788")!)

    public var isLoopback: Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    /// `scheme://host[:port]`: Better Auth checks Origin on state-changing auth requests.
    public var origin: String {
        var value = "\(baseURL.scheme ?? "https")://\(baseURL.host ?? "")"
        if let port = baseURL.port { value += ":\(port)" }
        return value
    }

    public static func custom(_ text: String) -> APIEnvironment? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), url.host != nil,
              scheme == "https" || (scheme == "http" && APIEnvironment(name: "", baseURL: url).isLoopback)
        else { return nil }
        return APIEnvironment(name: url.host ?? trimmed, baseURL: url)
    }
}

public struct NewCustomer: Encodable, Sendable {
    public var name: String
    public var email: String?
    public var phone: String?
    public var address: String?
    public var accountType: String?
    public var preferredContact: ContactMethod?

    public init(name: String, email: String? = nil, phone: String? = nil, address: String? = nil, accountType: String? = nil, preferredContact: ContactMethod? = nil) {
        self.name = name; self.email = email; self.phone = phone; self.address = address
        self.accountType = accountType; self.preferredContact = preferredContact
    }

    /// Empty strings are absent, never "set to blank".
    public var normalized: NewCustomer {
        func clean(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        return NewCustomer(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines), email: clean(email),
            phone: clean(phone), address: clean(address), accountType: accountType, preferredContact: preferredContact
        )
    }
}

public struct NewContact: Encodable, Sendable {
    public var name: String
    public var role: String?
    public var email: String?
    public var phone: String?
    public var primary: Bool

    public init(name: String, role: String? = nil, email: String? = nil, phone: String? = nil, primary: Bool = false) {
        self.name = name; self.role = role; self.email = email; self.phone = phone; self.primary = primary
    }
}

public struct NewServiceLocation: Encodable, Sendable {
    public var label: String
    public var kind: ServiceLocationKind
    public var address: String
    public var notes: String?
    public var gateCode: String?
    public var alarmCode: String?
    public var dogOnSite: String?
    public var parking: String?

    public init(label: String, kind: ServiceLocationKind = .service, address: String, notes: String? = nil, gateCode: String? = nil, alarmCode: String? = nil, dogOnSite: String? = nil, parking: String? = nil) {
        self.label = label; self.kind = kind; self.address = address; self.notes = notes
        self.gateCode = gateCode; self.alarmCode = alarmCode; self.dogOnSite = dogOnSite; self.parking = parking
    }
}

public struct PauseDetails: Encodable, Sendable, Equatable {
    public var reason: String
    public var nextAction: String

    public init(reason: String, nextAction: String) {
        self.reason = reason; self.nextAction = nextAction
    }
}

/// Thin client over the canonical Thorbis API. No business rules live here:
/// the server decides legality, scope and money; this type moves bytes.
public actor ThorbisAPI {
    public private(set) var environment: APIEnvironment
    public private(set) var credentials: Credentials
    private let transport: HTTPTransport
    private let onCredentialsChange: @Sendable (Credentials) -> Void

    /// Largest page the API serves (`MAX_PAGE_LIMIT`).
    public static let pageLimit = 200
    /// Lists stop after this many pages so a huge tenant can't stall a phone.
    public static let maxPages = 5

    public init(
        environment: APIEnvironment,
        credentials: Credentials = .none,
        transport: HTTPTransport = URLSessionTransport(),
        onCredentialsChange: @escaping @Sendable (Credentials) -> Void = { _ in }
    ) {
        self.environment = environment
        self.credentials = credentials
        self.transport = transport
        self.onCredentialsChange = onCredentialsChange
    }

    public func setEnvironment(_ environment: APIEnvironment) {
        guard environment != self.environment else { return }
        self.environment = environment
        updateCredentials(.none)
    }

    public static let devUserId = "018f0000-0000-7000-8000-000000000203"
    public static let devOrganizationId = "018f0000-0000-7000-8000-000000000201"

    public func useDevIdentity(
        user: String = ThorbisAPI.devUserId,
        organization: String = ThorbisAPI.devOrganizationId,
        roles: String = "owner"
    ) throws {
        guard environment.isLoopback else {
            throw APIError.problem(status: 403, Problem(detail: "Dev identity only works against a local API."))
        }
        updateCredentials(.devHeaders(user: user, organization: organization, roles: roles))
    }

    // MARK: Authentication (Better Auth, /api/auth)

    public func signIn(email: String, password: String) async throws -> AuthSession {
        struct Body: Encodable { let email: String; let password: String }
        updateCredentials(.none)
        let _: Empty = try await request("POST", "/api/auth/sign-in/email", body: Body(email: email, password: password))
        guard case .session = credentials else {
            throw APIError.problem(status: 500, Problem(detail: "Signed in, but the server did not start a session. Try again."))
        }
        return try await session()
    }

    public func session() async throws -> AuthSession {
        let session: AuthSession? = try await request("GET", "/api/auth/get-session")
        guard let session else { throw APIError.unauthenticated }
        return session
    }

    public func organizations() async throws -> [Organization] {
        try await request("GET", "/api/auth/organization/list")
    }

    public func setActiveOrganization(_ id: String) async throws {
        struct Body: Encodable { let organizationId: String }
        let _: Empty = try await request("POST", "/api/auth/organization/set-active", body: Body(organizationId: id))
    }

    public func signOut() async {
        if case .session = credentials {
            let _: Empty? = try? await request("POST", "/api/auth/sign-out", body: EmptyBody())
        }
        updateCredentials(.none)
    }

    // MARK: Account

    public func me() async throws -> Account? {
        struct Envelope: Decodable { struct Me: Decodable { let account: Account }; let me: Me? }
        let envelope: Envelope = try await request("GET", "/v1/me")
        return envelope.me?.account
    }

    public func requestAccountDeletion() async throws -> AccountDeletionRequest {
        try await request("POST", "/v1/account-lifecycle/deletion-requests", body: EmptyBody())
    }

    /// The open deletion request, or nil when the account has none (the API answers 404).
    public func currentDeletionRequest() async throws -> AccountDeletionRequest? {
        struct Envelope: Decodable { let request: AccountDeletionRequest }
        do {
            let envelope: Envelope = try await request("GET", "/v1/account-lifecycle/deletion-requests/current")
            return envelope.request
        } catch let APIError.problem(status, _) where status == 404 {
            return nil
        }
    }

    // MARK: Jobs

    public func jobs(customerId: String? = nil) async throws -> [Job] {
        try await all("/v1/jobs", query: customerId.map { ["customerId": $0] } ?? [:])
    }

    public func job(_ id: String) async throws -> Job {
        try await request("GET", "/v1/jobs/\(id.pathSafe)")
    }

    public func createJob(customerId: String, title: String, notes: String?) async throws -> Job {
        struct Body: Encodable { let customerId: String; let title: String; let notes: String? }
        return try await request("POST", "/v1/jobs", body: Body(customerId: customerId, title: title, notes: notes.nonEmpty))
    }

    public func progress(
        _ id: String, to target: JobStatus, pause: PauseDetails? = nil,
        expectedPauseAuditId: String? = nil, etaMinutes: Int? = nil
    ) async throws -> Job {
        struct Arrival: Encodable { let method = "manual" }
        struct Body: Encodable {
            let to: String
            let arrival: Arrival?
            let pause: PauseDetails?
            let expectedPauseAuditId: String?
            let etaMinutes: Int?
        }
        let body = Body(
            to: target.rawValue, arrival: target == .arrived ? Arrival() : nil, pause: pause,
            expectedPauseAuditId: expectedPauseAuditId, etaMinutes: etaMinutes
        )
        return try await request("POST", "/v1/jobs/\(id.pathSafe)/progress", body: body)
    }

    public func schedule(
        _ id: String, at start: Date, timeZone: TimeZone, windowEnds: Date?, expectedPrior: String?
    ) async throws -> Job {
        struct Body: Encodable {
            let scheduledFor: String
            let timeZone: String
            let arrivalWindowEndsAt: String?
            let expectedPriorScheduledFor: String?
        }
        let body = Body(
            scheduledFor: Timestamp.string(start), timeZone: timeZone.identifier,
            arrivalWindowEndsAt: windowEnds.map(Timestamp.string), expectedPriorScheduledFor: expectedPrior
        )
        return try await request("POST", "/v1/jobs/\(id.pathSafe)/schedule", body: body)
    }

    public func assign(_ id: String, to userId: String, expectedAssigneeId: String?) async throws -> Job {
        struct Body: Encodable { let userId: String; let expectedAssigneeId: String? }
        return try await request("POST", "/v1/jobs/\(id.pathSafe)/assign", body: Body(userId: userId, expectedAssigneeId: expectedAssigneeId))
    }

    public func complete(_ id: String, notes: String?) async throws -> Job {
        struct Body: Encodable { let notes: String? }
        return try await request("POST", "/v1/jobs/\(id.pathSafe)/complete", body: Body(notes: notes.nonEmpty))
    }

    public func cancel(_ id: String) async throws -> Job {
        try await request("POST", "/v1/jobs/\(id.pathSafe)/cancel", body: EmptyBody())
    }

    public func notes(job id: String) async throws -> [JobNote] {
        (try await request("GET", "/v1/jobs/\(id.pathSafe)/notes") as Items<JobNote>).items
    }

    public func addNote(job id: String, body text: String) async throws -> JobNote {
        struct Body: Encodable { let body: String }
        return try await request("POST", "/v1/jobs/\(id.pathSafe)/notes", body: Body(body: text))
    }

    public func photos(job id: String) async throws -> [JobPhoto] {
        (try await request("GET", "/v1/jobs/\(id.pathSafe)/photos") as Items<JobPhoto>).items
    }

    /// Raw bytes, not JSON: the content type is the metadata (`POST /v1/jobs/:id/photos`).
    public func uploadPhoto(job id: String, data: Data, contentType: String) async throws -> JobPhoto {
        guard JobPhoto.acceptedContentTypes.contains(contentType) else {
            throw APIError.problem(status: 415, Problem(detail: "Photos must be JPEG, PNG, WebP or HEIC."))
        }
        guard data.count <= JobPhoto.maxByteSize else {
            throw APIError.problem(status: 413, Problem(detail: "This photo is larger than 15 MB."))
        }
        let response = try await raw("POST", "/v1/jobs/\(id.pathSafe)/photos", body: data, contentType: contentType)
        return try decode(response.body)
    }

    public func photoData(job id: String, photo photoId: String) async throws -> Data {
        try await raw("GET", "/v1/jobs/\(id.pathSafe)/photos/\(photoId.pathSafe)", accept: "image/*").body
    }

    public func completionInvoice(job id: String) async throws -> Invoice {
        try await request("POST", "/v1/jobs/\(id.pathSafe)/completion-invoice", body: EmptyBody())
    }

    public func assignees() async throws -> [Assignee] {
        try await all("/v1/organization/assignees")
    }

    // MARK: Customers

    public func customers() async throws -> [Customer] {
        try await all("/v1/customers")
    }

    public func customer(_ id: String) async throws -> Customer {
        try await request("GET", "/v1/customers/\(id.pathSafe)")
    }

    public func createCustomer(_ input: NewCustomer) async throws -> Customer {
        try await request("POST", "/v1/customers", body: input.normalized)
    }

    public func contacts(customer id: String) async throws -> [CustomerContact] {
        (try await request("GET", "/v1/customers/\(id.pathSafe)/contacts") as Items<CustomerContact>).items
    }

    public func addContact(customer id: String, _ input: NewContact) async throws -> CustomerContact {
        try await request("POST", "/v1/customers/\(id.pathSafe)/contacts", body: input)
    }

    public func locations(customer id: String) async throws -> [ServiceLocation] {
        (try await request("GET", "/v1/customers/\(id.pathSafe)/locations") as Items<ServiceLocation>).items
    }

    public func addLocation(customer id: String, _ input: NewServiceLocation) async throws -> ServiceLocation {
        try await request("POST", "/v1/customers/\(id.pathSafe)/locations", body: input)
    }

    // MARK: Estimates and invoices

    public func estimates(customerId: String? = nil) async throws -> [Estimate] {
        try await all("/v1/estimates", query: customerId.map { ["customerId": $0] } ?? [:])
    }

    public func estimate(_ id: String) async throws -> Estimate {
        try await request("GET", "/v1/estimates/\(id.pathSafe)")
    }

    public func sendEstimate(_ estimate: Estimate) async throws -> Estimate {
        struct Body: Encodable { let expectedRevisionNumber: Int }
        return try await request(
            "POST", "/v1/estimates/\(estimate.id.pathSafe)/send",
            body: Body(expectedRevisionNumber: estimate.currentRevisionNumber ?? 0)
        )
    }

    public func approveEstimate(_ estimate: Estimate) async throws -> Estimate {
        struct Body: Encodable { let revisionNumber: Int? }
        return try await request("POST", "/v1/estimates/\(estimate.id.pathSafe)/approve", body: Body(revisionNumber: estimate.currentRevisionNumber))
    }

    public func declineEstimate(_ estimate: Estimate) async throws -> Estimate {
        struct Body: Encodable { let revisionNumber: Int? }
        return try await request("POST", "/v1/estimates/\(estimate.id.pathSafe)/decline", body: Body(revisionNumber: estimate.currentRevisionNumber))
    }

    public func invoices(customerId: String? = nil) async throws -> [Invoice] {
        try await all("/v1/invoices", query: customerId.map { ["customerId": $0] } ?? [:])
    }

    public func invoice(_ id: String) async throws -> Invoice {
        try await request("GET", "/v1/invoices/\(id.pathSafe)")
    }

    public func issueInvoice(_ invoice: Invoice) async throws -> Invoice {
        struct Body: Encodable { let expectedLinesRevision: Int }
        return try await request("POST", "/v1/invoices/\(invoice.id.pathSafe)/issue", body: Body(expectedLinesRevision: invoice.linesRevision))
    }

    public func payments(invoice id: String) async throws -> [Payment] {
        try await all("/v1/invoices/\(id.pathSafe)/payments")
    }

    // MARK: Inbox and search

    public func staffNotices() async throws -> [StaffNotice] {
        (try await request("GET", "/v1/staff/notices", query: ["limit": "100"]) as StaffNoticePage).items
    }

    public func markNoticesRead() async throws {
        let _: Empty = try await request("POST", "/v1/staff/notices/read", body: EmptyBody())
    }

    public func search(_ text: String, limit: Int = 25) async throws -> [SearchResult] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return (try await request("GET", "/v1/search", query: ["q": query, "limit": String(limit)]) as SearchResponse).items
    }

    // MARK: Plumbing

    struct Empty: Decodable {}
    struct EmptyBody: Encodable {}

    private func all<Item: Decodable & Sendable>(_ path: String, query: [String: String] = [:]) async throws -> [Item] {
        var items: [Item] = []
        var cursor: String?
        for _ in 0..<Self.maxPages {
            var pageQuery = query
            pageQuery["limit"] = String(Self.pageLimit)
            if let cursor { pageQuery["cursor"] = cursor }
            let page: Page<Item> = try await request("GET", path, query: pageQuery)
            items += page.items
            guard let next = page.nextCursor, !page.items.isEmpty else { break }
            cursor = next
        }
        return items
    }

    private func request<T: Decodable>(_ method: String, _ path: String, query: [String: String] = [:]) async throws -> T {
        let response = try await raw(method, path, query: query)
        return try decode(response.body)
    }

    private func request<T: Decodable, B: Encodable>(_ method: String, _ path: String, body: B) async throws -> T {
        let data: Data
        do { data = try JSONEncoder().encode(body) } catch { throw APIError.decoding("Could not encode the request.") }
        let response = try await raw(method, path, body: data, contentType: "application/json")
        return try decode(response.body)
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        let payload = data.isEmpty || data.allSatisfy({ $0 == 0x20 || $0 == 0x0A }) ? Data("null".utf8) : data
        if T.self == Empty.self || T.self == Optional<Empty>.self {
            return try JSONDecoder().decode(T.self, from: Data("{}".utf8))
        }
        do {
            return try JSONDecoder().decode(T.self, from: payload)
        } catch let DecodingError.keyNotFound(key, context) {
            throw APIError.decoding("Missing \(key.stringValue) at \(context.codingPath.map(\.stringValue).joined(separator: ".")).")
        } catch let DecodingError.typeMismatch(_, context), let DecodingError.valueNotFound(_, context) {
            throw APIError.decoding("Unexpected value at \(context.codingPath.map(\.stringValue).joined(separator: ".")).")
        } catch {
            throw APIError.decoding("Unreadable response.")
        }
    }

    @discardableResult
    private func raw(
        _ method: String, _ path: String, query: [String: String] = [:], body: Data? = nil,
        contentType: String? = nil, accept: String = "application/json"
    ) async throws -> HTTPResponse {
        guard var components = URLComponents(url: environment.baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL(environment.baseURL.absoluteString)
        }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
            ? path
            : "/" + components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path
        if !query.isEmpty {
            components.queryItems = query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) }
        }
        guard let url = components.url else { throw APIError.invalidURL(path) }

        var headers = ["accept": accept]
        if let contentType { headers["content-type"] = contentType }
        if path.hasPrefix("/api/auth") { headers["origin"] = environment.origin }
        switch credentials {
        case .none:
            break
        case let .session(cookies):
            headers["cookie"] = cookies.keys.sorted().map { "\($0)=\(cookies[$0] ?? "")" }.joined(separator: "; ")
        case let .devHeaders(user, organization, roles):
            headers["x-thorbis-user"] = user
            headers["x-thorbis-org"] = organization
            headers["x-thorbis-roles"] = roles
        }

        // Requests can outlive the session that sent them (sign-out, then sign-in while one
        // is in flight); only a response to the current session may change credentials.
        let sentWith = credentials
        let response: HTTPResponse
        do {
            response = try await transport.send(HTTPRequest(method: method, url: url, headers: headers, body: body))
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(Self.describe(error))
        }
        let current = credentials == sentWith
        if current { absorbCookies(response.cookies) }
        guard (200..<300).contains(response.status) else {
            let error = APIError.from(status: response.status, body: response.body)
            if current, error == .unauthenticated, case .session = credentials { updateCredentials(.none) }
            throw error
        }
        return response
    }

    /// Better Auth rotates and clears its cookies on any response; keep the jar in step.
    private func absorbCookies(_ cookies: [ResponseCookie]) {
        let relevant = cookies.filter { $0.name.contains("better-auth") }
        if relevant.isEmpty { return }
        if case .devHeaders = credentials { return }
        var jar: [String: String] = [:]
        if case let .session(existing) = credentials { jar = existing }
        for cookie in relevant {
            jar[cookie.name] = cookie.expired ? nil : cookie.value
        }
        let hasSession = jar.keys.contains { $0.hasSuffix("session_token") }
        updateCredentials(hasSession ? .session(jar) : .none)
    }

    private func updateCredentials(_ next: Credentials) {
        guard next != credentials else { return }
        credentials = next
        onCredentialsChange(next)
    }

    private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed:
                return "You're offline. Check your connection and try again."
            case NSURLErrorTimedOut:
                return "The server took too long to answer. Try again."
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed:
                return "Can't reach the Thorbis server."
            default:
                break
            }
        }
        return "The request didn't reach the server. Try again."
    }
}

extension String {
    /// Ids are UUIDs; anything else is percent-encoded so it can't change the path.
    var pathSafe: String { addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-"))) ?? self }
}

extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
