import Foundation

enum CompanyCreatePrerequisite: LocalizedError {
    case missingSession
    case invalidServer
    var errorDescription: String? {
        switch self {
        case .missingSession: return "Sign in again to create a company."
        case .invalidServer: return "Check the server address before creating a company."
        }
    }
}

enum CompanyCreateFailure {
    /// Responses indicating a rejected request, as distinct from an invalid success
    /// body, cancellation or a transport/server failure whose outcome is unknown.
    static func isDefinitive(_ error: Error) -> Bool {
        if error is CompanyCreatePrerequisite { return true }
        guard let status = (error as? Problem)?.status else { return false }
        return [400, 401, 403, 404, 405, 409, 422].contains(status)
    }
}
