import Foundation

struct Customer: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let archived: Bool?
    let createdAt: String?
}

struct Job: Codable, Identifiable, Hashable {
    let id: String
    let customerId: String?
    let title: String
    let status: String
    let createdAt: String?
    let updatedAt: String?
    let allowedTransitions: [String]?

    var shortRef: String { "JOB-" + String(id.suffix(4)).uppercased() }
}

struct Items<T: Codable>: Codable { let items: [T] }

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
    enum Auth: Equatable {
        case none
        /// Better Auth session cookie held by URLSession's shared cookie storage.
        case session
        /// Loopback-only dev headers accepted by createDevHeaderIdentityResolver.
        case devHeaders(user: String, org: String, roles: String)
    }

    @Published var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: "thorbis.apiBaseURL") }
    }
    @Published var auth: Auth = .none
    @Published var displayName = ""

    init() {
        let env = ProcessInfo.processInfo.environment
        baseURL = env["THORBIS_API_URL"] ?? UserDefaults.standard.string(forKey: "thorbis.apiBaseURL") ?? "http://127.0.0.1:8788"
        if env["THORBIS_DEV_LOGIN"] == "1" { useDevIdentity() }
    }

    var isLoopback: Bool { baseURL.contains("127.0.0.1") || baseURL.contains("localhost") }

    func useDevIdentity() {
        auth = .devHeaders(user: "018f0000-0000-7000-8000-000000000203",
                           org: "018f0000-0000-7000-8000-000000000201",
                           roles: "owner")
        displayName = "Local dev"
    }

    func signIn(email: String, password: String) async throws {
        struct Body: Encodable { let email: String; let password: String }
        let _: EmptyResponse = try await send("POST", "/api/auth/sign-in/email", body: Body(email: email, password: password), authed: false)
        auth = .session
        let me: MeEnvelope = try await send("GET", "/v1/me")
        displayName = me.me?.account.name ?? email
    }

    func signOut() {
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        auth = .none
    }

    func jobs() async throws -> [Job] { (try await send("GET", "/v1/jobs") as Items<Job>).items }
    func job(_ id: String) async throws -> Job { try await send("GET", "/v1/jobs/\(id)") }
    func customers() async throws -> [Customer] { (try await send("GET", "/v1/customers") as Items<Customer>).items }
    func customer(_ id: String) async throws -> Customer { try await send("GET", "/v1/customers/\(id)") }
    func progress(_ id: String, to: String) async throws {
        struct Body: Encodable { let to: String }
        let _: EmptyResponse = try await send("POST", "/v1/jobs/\(id)/progress", body: Body(to: to))
    }
    func createCustomer(name: String) async throws -> Customer {
        struct Body: Encodable { let name: String }
        return try await send("POST", "/v1/customers", body: Body(name: name))
    }
    func createJob(customerId: String, title: String) async throws -> Job {
        struct Body: Encodable { let customerId: String; let title: String }
        return try await send("POST", "/v1/jobs", body: Body(customerId: customerId, title: title))
    }

    struct EmptyResponse: Decodable { init(from decoder: Decoder) throws {} }

    private func send<T: Decodable>(_ method: String, _ path: String, authed: Bool = true) async throws -> T {
        try await send(method, path, body: Optional<String>.none, authed: authed)
    }

    private func send<T: Decodable, B: Encodable>(_ method: String, _ path: String, body: B?, authed: Bool = true) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw Problem(title: "Bad API URL", status: nil, detail: baseURL) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = try JSONEncoder().encode(body)
        }
        if authed, case let .devHeaders(user, org, roles) = auth {
            req.setValue(user, forHTTPHeaderField: "x-thorbis-user")
            req.setValue(org, forHTTPHeaderField: "x-thorbis-org")
            req.setValue(roles, forHTTPHeaderField: "x-thorbis-roles")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw (try? JSONDecoder().decode(Problem.self, from: data)) ?? Problem(title: "HTTP \(code)", status: code, detail: nil)
        }
        if data.isEmpty, let empty = try? JSONDecoder().decode(T.self, from: Data("{}".utf8)) { return empty }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

extension String {
    var statusLabel: String { replacingOccurrences(of: "_", with: " ").capitalized }
}

func relativeDay(_ iso: String?) -> String {
    guard let iso else { return "" }
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let d = f.date(from: iso) else { return "" }
    let r = RelativeDateTimeFormatter(); r.unitsStyle = .short
    return r.localizedString(for: d, relativeTo: Date())
}
