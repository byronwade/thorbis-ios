import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPRequest: Sendable, Equatable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: String, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method; self.url = url; self.headers = headers; self.body = body
    }
}

/// A cookie the server set or cleared. `expired` covers Max-Age=0, past Expires,
/// and empty values, which Better Auth uses to sign a session out.
public struct ResponseCookie: Sendable, Equatable {
    public let name: String
    public let value: String
    public let expired: Bool

    public init(name: String, value: String, expired: Bool = false) {
        self.name = name; self.value = value; self.expired = expired
    }
}

public struct HTTPResponse: Sendable {
    public let status: Int
    public let headers: [String: String]
    public let cookies: [ResponseCookie]
    public let body: Data

    public init(status: Int, headers: [String: String] = [:], cookies: [ResponseCookie] = [], body: Data = Data()) {
        self.status = status
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, last in last })
        self.cookies = cookies
        self.body = body
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// URLSession without its own cookie jar: the session cookie is owned by
/// `ThorbisAPI` and persisted by the app in the Keychain, never in
/// `HTTPCookieStorage.shared` (which would leak it across environments).
public final class URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(timeout: TimeInterval = 30) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = timeout
        #if canImport(Darwin)
        configuration.waitsForConnectivity = false
        #endif
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.httpShouldHandleCookies = false
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("The server sent a response that is not HTTP.")
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String { headers[key] = value }
        }
        let now = Date()
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: request.url).map { cookie in
            ResponseCookie(
                name: cookie.name,
                value: cookie.value,
                expired: cookie.value.isEmpty || (cookie.expiresDate.map { $0 <= now } ?? false)
            )
        }
        return HTTPResponse(status: http.statusCode, headers: headers, cookies: cookies, body: data)
    }
}
