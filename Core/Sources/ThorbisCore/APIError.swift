import Foundation

/// RFC 9457 problem details from `/v1`, or Better Auth's `{ code, message }` from `/api/auth`.
public struct Problem: Decodable, Sendable, Equatable {
    public let type: String?
    public let title: String?
    public let status: Int?
    public let detail: String?
    public let code: String?
    public let message: String?

    public init(type: String? = nil, title: String? = nil, status: Int? = nil, detail: String? = nil, code: String? = nil, message: String? = nil) {
        self.type = type; self.title = title; self.status = status; self.detail = detail
        self.code = code; self.message = message
    }
}

public enum APIError: Error, Sendable, Equatable, LocalizedError {
    /// No session, or the session expired. The app returns to sign-in.
    case unauthenticated
    /// Signed in, but the session has no active organization yet.
    case noActiveOrganization
    /// The server refused the request with a problem document.
    case problem(status: Int, Problem)
    /// The network failed before a response arrived; the request may be retried.
    case transport(String)
    /// The response did not match the contract this build expects.
    case decoding(String)
    case invalidURL(String)

    public var errorDescription: String? {
        switch self {
        case .unauthenticated:
            "Your session ended. Sign in again."
        case .noActiveOrganization:
            "Choose a workspace to continue."
        case let .problem(status, problem):
            problem.detail ?? problem.message ?? problem.title ?? "The request failed (\(status))."
        case let .transport(message):
            message
        case let .decoding(message):
            "The server sent something this version of Thorbis can't read. \(message)"
        case let .invalidURL(url):
            "\(url) is not a valid server address."
        }
    }

    /// True when retrying the same request later could succeed.
    public var isRetryable: Bool {
        switch self {
        case .transport: true
        case let .problem(status, _): status == 429 || status >= 500
        default: false
        }
    }

    /// A conflict means someone else changed the record first: refresh, then retry.
    public var isConflict: Bool {
        if case let .problem(status, _) = self { return status == 409 || status == 412 }
        return false
    }

    static func from(status: Int, body: Data) -> APIError {
        let problem = (try? JSONDecoder().decode(Problem.self, from: body)) ?? Problem(status: status)
        if status == 401 { return .unauthenticated }
        let text = [problem.detail, problem.message, problem.title].compactMap { $0 }.joined(separator: " ").lowercased()
        if status == 403, text.contains("no active organization") { return .noActiveOrganization }
        return .problem(status: status, problem)
    }
}
