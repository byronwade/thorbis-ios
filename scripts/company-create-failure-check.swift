import Foundation
struct Problem: Error { let status: Int?; let detail: String? }
@main struct Check {
    static func main() {
        precondition(CompanyCreateFailure.isDefinitive(CompanyCreatePrerequisite.missingSession))
        for status in [400, 401, 403, 404, 405, 409, 422] {
            precondition(CompanyCreateFailure.isDefinitive(Problem(status: status, detail: "rejected")))
        }
        for status in [200, 408, 429, 500, 503] {
            precondition(!CompanyCreateFailure.isDefinitive(Problem(status: status, detail: "unknown")))
        }
        precondition(!CompanyCreateFailure.isDefinitive(Problem(status: nil, detail: "network")))
        precondition(!CompanyCreateFailure.isDefinitive(CancellationError()))
        print("PASS: confirmed rejection permits retry; transport, cancellation and malformed success remain unconfirmed")
    }
}
