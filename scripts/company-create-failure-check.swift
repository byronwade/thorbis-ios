import Foundation
struct Problem: Error { let title: String?; let status: Int?; let detail: String? }
@main struct Check {
    static func main() {
        precondition(CompanyCreateFailure.isDefinitive(CompanyCreatePrerequisite.missingSession))
        for code in ["YOU_ARE_NOT_ALLOWED_TO_CREATE_A_NEW_ORGANIZATION", "YOU_HAVE_REACHED_THE_MAXIMUM_NUMBER_OF_ORGANIZATIONS"] {
            precondition(CompanyCreateFailure.isDefinitive(Problem(title: code, status: 403, detail: "rejected")))
        }
        for status in [200, 400, 401, 403, 408, 409, 422, 429, 500, 503] {
            precondition(!CompanyCreateFailure.isDefinitive(Problem(title: "unknown", status: status, detail: nil)))
        }
        precondition(!CompanyCreateFailure.isDefinitive(Problem(title: nil, status: nil, detail: "network")))
        precondition(!CompanyCreateFailure.isDefinitive(CancellationError()))
        print("PASS: proven pre-create rejections permit retry; unknown responses and transport remain unconfirmed")
    }
}
