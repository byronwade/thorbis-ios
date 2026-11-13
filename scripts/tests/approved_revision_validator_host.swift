import Foundation
struct EstimateRecord {
    let id: String; let organizationId: String; let customerId: String; let locationId: String?
    let status: String; let currentRevisionNumber: Int?
}
enum Failure: Error { case invalid }
func customerReviewUnavailable() -> Error { Failure.invalid }
struct CustomerIssuedEstimateRevision {
    let id: String; let estimateId: String; let organizationId: String; let customerId: String
    let locationId: String?; let revisionNumber: Int; let status: String
    // ACTUAL_VALIDATOR
}
@main struct Probe {
    static func main() throws {
        let uuid = "00000000-0000-4000-8000-000000000011"
        func record(_ status: String) -> EstimateRecord { .init(id: uuid, organizationId: "org", customerId: "customer", locationId: nil, status: status, currentRevisionNumber: 2) }
        func revision(_ status: String) -> CustomerIssuedEstimateRevision { .init(id: uuid, estimateId: uuid, organizationId: "org", customerId: "customer", locationId: nil, revisionNumber: 2, status: status) }
        try revision("issued").validate(for: record("sent"))
        try revision("approved").validate(for: record("approved"), allowApprovedForReading: true)
        for pair in [("sent", "approved"), ("approved", "issued"), ("draft", "issued"), ("approved", "declined")] {
            do { try revision(pair.1).validate(for: record(pair.0), allowApprovedForReading: true); fatalError("mismatched lifecycle accepted: \(pair)") }
            catch Failure.invalid { }
        }
        do { try revision("approved").validate(for: record("approved")); fatalError("approved revision accepted in signing mode") }
        catch Failure.invalid { }
        let wrongTenant = EstimateRecord(id: uuid, organizationId: "other", customerId: "customer", locationId: nil, status: "approved", currentRevisionNumber: 2)
        do { try revision("approved").validate(for: wrongTenant, allowApprovedForReading: true); fatalError("foreign tenant accepted") }
        catch Failure.invalid { }
        let changedRevision = EstimateRecord(id: uuid, organizationId: "org", customerId: "customer", locationId: nil, status: "approved", currentRevisionNumber: 3)
        do { try revision("approved").validate(for: changedRevision, allowApprovedForReading: true); fatalError("stale revision accepted") }
        catch Failure.invalid { }
        print("PASS actual revision lifecycle validator")
    }
}
