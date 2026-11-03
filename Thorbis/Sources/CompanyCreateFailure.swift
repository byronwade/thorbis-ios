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
        guard let problem = error as? Problem, problem.status == 403, let code = problem.title else { return false }
        return ["YOU_ARE_NOT_ALLOWED_TO_CREATE_A_NEW_ORGANIZATION",
                "YOU_HAVE_REACHED_THE_MAXIMUM_NUMBER_OF_ORGANIZATIONS"].contains(code)
    }
}
