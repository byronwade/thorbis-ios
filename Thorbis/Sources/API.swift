import Foundation

struct Customer: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let archived: Bool?
    let createdAt: String?
}

/// `customers.create` input (createCustomerInputSchema); nil fields are omitted.
struct NewCustomerRequest: Encodable, Equatable {
    var name: String
    var phone: String? = nil
    var email: String? = nil
    var address: String? = nil
    var accountType: String? = nil
    var preferredContact: String? = nil
}

struct Job: Codable, Identifiable, Hashable {
    let id: String
    let customerId: String?
    let title: String
    let status: String
    let createdAt: String?
    let updatedAt: String?
    let allowedTransitions: [String]?
    var scheduledFor: String? = nil
    var assignedToUserId: String? = nil
    var locationId: String? = nil

    var shortRef: String { "JOB-" + String(id.suffix(4)).uppercased() }
}

struct Items<T: Codable>: Codable {
    let items: [T]
    let nextCursor: String?
}

struct Problem: Codable, Error, LocalizedError {
    let title: String?
    let status: Int?
    let detail: String?
    var errorDescription: String? { detail ?? title ?? "Request failed (\(status ?? 0))" }
}

struct MeAccount: Codable { let id: String; let name: String?; let email: String? }
struct Me: Codable { let account: MeAccount }
struct MeEnvelope: Codable { let me: Me? }

/// Thin client over the canonical Thorbis API (services/api, OpenAPI 3.1, RFC 9457 errors).
@MainActor
final class APIClient: ObservableObject {
    private static let productionOrigin = "https://app.thorbis.com"

    private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    enum Auth: Equatable {
        case none
        /// Better Auth session cookie held by URLSession's shared cookie storage.
        case session
        /// Loopback-only dev headers accepted by createDevHeaderIdentityResolver.
        case devHeaders(user: String, org: String, roles: String)
    }

    @Published var baseURL: String {
        didSet {
            #if DEBUG
            if Self.validatedOrigin(baseURL) != nil {
                UserDefaults.standard.set(baseURL, forKey: "thorbis.apiBaseURL")
            }
            #endif
        }
    }
    @Published var auth: Auth = .none
    @Published var displayName = ""

    private let session: URLSession
    private(set) var requestGeneration = UUID()
    var onUnauthorized: (() -> Void)?

    func invalidateRequests() { requestGeneration = UUID() }

    func clearSessionCookies() {
        guard let origin = Self.validatedOrigin(baseURL)?.url,
              let storage = session.configuration.httpCookieStorage else { return }
        storage.cookies(for: origin)?.forEach { storage.deleteCookie($0) }
    }

    init(session: URLSession? = nil, baseURL: String? = nil) {
        let env = ProcessInfo.processInfo.environment
        self.session = session ?? URLSession(configuration: .default, delegate: NoRedirects(), delegateQueue: nil)
        if let baseURL {
            self.baseURL = baseURL
        } else {
            #if DEBUG
            let candidate = env["THORBIS_API_URL"] ?? UserDefaults.standard.string(forKey: "thorbis.apiBaseURL")
            self.baseURL = candidate.flatMap { Self.validatedOrigin($0) == nil ? nil : $0 } ?? Self.productionOrigin
            #else
            self.baseURL = Self.productionOrigin
            #endif
        }
        #if DEBUG
        if env["THORBIS_DEV_LOGIN"] == "1" { useDevIdentity() }
        #endif
    }

    private static func validatedOrigin(_ raw: String) -> URLComponents? {
        guard let components = URLComponents(string: raw),
              let host = components.host?.lowercased(),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/"
        else { return nil }
        if components.scheme == "https", host == "app.thorbis.com", components.port == nil {
            return components
        }
        #if DEBUG
        if components.scheme == "http", ["127.0.0.1", "localhost", "[::1]"].contains(host) {
            return components
        }
        #endif
        return nil
    }

    var isLoopback: Bool {
        #if DEBUG
        guard let origin = Self.validatedOrigin(baseURL), let host = origin.host?.lowercased() else { return false }
        return ["127.0.0.1", "localhost", "[::1]"].contains(host)
        #else
        return false
        #endif
    }

    func useDevIdentity() {
        #if DEBUG
        guard isLoopback else { auth = .none; return }
        auth = .devHeaders(user: "018f0000-0000-7000-8000-000000000203",
                           org: "018f0000-0000-7000-8000-000000000201",
                           roles: "owner")
        displayName = "Local dev"
        #endif
    }

    func jobs() async throws -> [Job] { try await allPages("/v1/jobs") }
    func job(_ id: String) async throws -> Job { try await send("GET", "/v1/jobs/\(id)") }
    func customers() async throws -> [Customer] { try await allPages("/v1/customers") }
    func customer(_ id: String) async throws -> Customer { try await send("GET", "/v1/customers/\(id)") }
    func progress(_ id: String, to: String) async throws {
        struct Arrival: Encodable { let method: String }
        struct Body: Encodable { let to: String; let arrival: Arrival? }
        let _: EmptyResponse = try await send("POST", "/v1/jobs/\(id)/progress",
                                              body: Body(to: to, arrival: to == "arrived" ? Arrival(method: "manual") : nil))
    }
    func createCustomer(name: String) async throws -> Customer {
        try await createCustomer(NewCustomerRequest(name: name))
    }
    func createCustomer(_ request: NewCustomerRequest) async throws -> Customer {
        try await send("POST", "/v1/customers", body: request)
    }
    func createJob(customerId: String, title: String) async throws -> Job {
        struct Body: Encodable { let customerId: String; let title: String }
        return try await send("POST", "/v1/jobs", body: Body(customerId: customerId, title: title))
    }

    struct EmptyResponse: Decodable { init(from decoder: Decoder) throws {} }
    private struct AuthError: Decodable { let code: String?; let message: String? }

    private func allPages<T: Codable>(_ path: String) async throws -> [T] {
        let generation = requestGeneration
        var all: [T] = []
        var cursor: String?
        var seen: Set<String> = []
        repeat {
            try Task.checkCancellation()
            guard generation == requestGeneration else { throw CancellationError() }
            let page: Items<T> = try await send("GET", path, cursor: cursor)
            all.append(contentsOf: page.items)
            cursor = page.nextCursor
            if let cursor, !seen.insert(cursor).inserted || cursor.isEmpty {
                throw Problem(title: "Pagination cursor loop", status: nil, detail: "Repeated or empty cursor")
            }
        } while cursor != nil
        return all
    }

    func send<T: Decodable>(_ method: String, _ path: String, queryItems: [URLQueryItem] = [], cursor: String? = nil, authed: Bool = true) async throws -> T {
        try await send(method, path, body: Optional<String>.none, queryItems: queryItems, cursor: cursor, authed: authed)
    }

    func send<T: Decodable, B: Encodable>(_ method: String, _ path: String, body: B?, queryItems: [URLQueryItem] = [], cursor: String? = nil, authed: Bool = true) async throws -> T {
        let response = try await sendData(method, path, body: body, queryItems: queryItems, cursor: cursor, authed: authed)
        return try decodeResponse(response)
    }

    func sendWithStatus<T: Decodable, B: Encodable>(_ method: String, _ path: String, body: B?) async throws -> (value: T, status: Int) {
        let response = try await sendData(method, path, body: body)
        return (try decodeResponse(response), response.status)
    }

    private func decodeResponse<T: Decodable>(_ response: DataResponse) throws -> T {
        if response.data.isEmpty, let empty = try? JSONDecoder().decode(T.self, from: Data("{}".utf8)) { return empty }
        do { return try JSONDecoder().decode(T.self, from: response.data) }
        catch { throw Problem(title: "Invalid API response", status: response.status, detail: error.localizedDescription) }
    }

    func sendPublic<T: Decodable>(_ method: String, _ path: String) async throws -> T {
        let response = try await sendData(method, path, body: Optional<String>.none, authed: false, handleCookies: false)
        do { return try JSONDecoder().decode(T.self, from: response.data) }
        catch { throw Problem(title: "Invalid API response", status: response.status, detail: error.localizedDescription) }
    }

    func sendPublic<T: Decodable, B: Encodable>(_ method: String, _ path: String, body: B) async throws -> T {
        let response = try await sendData(method, path, body: body, authed: false, handleCookies: false)
        do { return try JSONDecoder().decode(T.self, from: response.data) }
        catch { throw Problem(title: "Invalid API response", status: response.status, detail: error.localizedDescription) }
    }

    func documentData(_ path: String) async throws -> Data {
        let response = try await sendData("GET", path, body: Optional<String>.none, accept: "application/pdf")
        guard response.contentType?.lowercased().split(separator: ";").first == "application/pdf",
              response.data.starts(with: Data("%PDF-".utf8)), response.data.count <= 50 * 1024 * 1024 else {
            throw Problem(title: "Invalid document", status: response.status, detail: "The server did not return a supported PDF.")
        }
        return response.data
    }

    /// A server-rendered Excel workbook (`/v1/reports/*.xlsx`), checked to be a zip before it is saved.
    func spreadsheetData(_ path: String) async throws -> Data {
        let mime = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        let response = try await sendData("GET", path, body: Optional<String>.none, accept: mime)
        guard response.contentType?.lowercased().split(separator: ";").first.map(String.init) == mime,
              response.data.starts(with: Data("PK".utf8)), response.data.count <= 50 * 1024 * 1024 else {
            throw Problem(title: "Invalid spreadsheet", status: response.status, detail: "The server did not return an Excel file.")
        }
        return response.data
    }

    private struct DataResponse {
        let data: Data
        let status: Int
        let contentType: String?
    }

    private func sendData<B: Encodable>(_ method: String, _ path: String, body: B?, queryItems: [URLQueryItem] = [], cursor: String? = nil, authed: Bool = true, accept: String = "application/json", handleCookies: Bool = true) async throws -> DataResponse {
        let generation = requestGeneration
        guard var origin = Self.validatedOrigin(baseURL), path.hasPrefix("/"), !path.hasPrefix("//") else {
            throw Problem(title: "Bad API URL", status: nil, detail: baseURL)
        }
        origin.path = ""
        guard let requestOrigin = origin.url?.absoluteString else {
            throw Problem(title: "Bad API URL", status: nil, detail: baseURL)
        }
        origin.path = path
        let requestQueryItems = queryItems + (cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? [])
        origin.queryItems = requestQueryItems.isEmpty ? nil : requestQueryItems
        guard let url = origin.url else { throw Problem(title: "Bad API URL", status: nil, detail: baseURL) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpShouldHandleCookies = handleCookies
        req.setValue(accept, forHTTPHeaderField: "accept")
        // URLSession does not supply the browser Origin required for cookie-backed mutations.
        if !["GET", "HEAD", "OPTIONS"].contains(method.uppercased()) {
            req.setValue(requestOrigin, forHTTPHeaderField: "Origin")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = try JSONEncoder().encode(body)
        }
        #if DEBUG
        if authed, isLoopback, case let .devHeaders(user, org, roles) = auth {
            req.setValue(user, forHTTPHeaderField: "x-thorbis-user")
            req.setValue(org, forHTTPHeaderField: "x-thorbis-org")
            req.setValue(roles, forHTTPHeaderField: "x-thorbis-roles")
        }
        #endif
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch {
            let offline: Set<URLError.Code> = [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
                                               .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff]
            let detail = (error as? URLError).map { offline.contains($0.code) } == true
                ? "No connection. Check your signal and try again."
                : error.localizedDescription
            throw Problem(title: "Network error", status: nil, detail: detail)
        }
        try Task.checkCancellation()
        guard generation == requestGeneration else { throw CancellationError() }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401, authed { onUnauthorized?() }
        guard (200..<300).contains(code) else {
            if let decoded = try? JSONDecoder().decode(Problem.self, from: data),
               decoded.title != nil || decoded.detail != nil {
                throw Problem(title: decoded.title, status: code, detail: decoded.detail)
            }
            if let decoded = try? JSONDecoder().decode(AuthError.self, from: data),
               decoded.code != nil || decoded.message != nil {
                throw Problem(title: decoded.code, status: code, detail: decoded.message)
            }
            throw Problem(title: "HTTP \(code)", status: code, detail: nil)
        }
        return DataResponse(data: data, status: code, contentType: (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type"))
    }
}

extension String {
    /// Sentence case, like every other label: "In progress", not "In Progress".
    var statusLabel: String {
        let words = replacingOccurrences(of: "_", with: " ").lowercased()
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

func relativeDay(_ iso: String?) -> String {
    guard let iso else { return "" }
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let d = f.date(from: iso) else { return "" }
    let r = RelativeDateTimeFormatter(); r.unitsStyle = .short
    return r.localizedString(for: d, relativeTo: Date())
}
