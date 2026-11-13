import Foundation
struct EstimateRecord {
    let id: String; let organizationId: String; let customerId: String; let locationId: String?
    let status: String; let currentRevisionNumber: Int?
}
struct CustomerIssuedEstimateRevision {
    let revisionNumber: Int
    func validate(for expected: EstimateRecord) throws { guard revisionNumber == expected.currentRevisionNumber else { throw Failure.invalid } }
}
enum Failure: Error { case offline, invalid }
@MainActor final class APIClient {
    var requestGeneration = UUID()
    var freshFlag: Bool?
    var offline = false
    var afterAggregate: (() -> Void)?
    var aggregateStatus = "sent"
    func checkCustomerReviewRequest(_ generation: UUID, currentAuthority: @MainActor () -> Bool) throws {
        guard generation == requestGeneration, currentAuthority(), !Task.isCancelled else { throw CancellationError() }
    }
    func customerReviewUnavailable() -> Error { Failure.invalid }
    func liveFieldEstimate(_ id: String) async throws -> EstimateRecord {
        afterAggregate?(); return .init(id: id, organizationId: "org", customerId: "customer", locationId: nil, status: aggregateStatus, currentRevisionNumber: 2)
    }
    func financialPath(_ base: String, id: String, suffix: String) throws -> String { base + "/" + id + suffix }
    func send<T>(_ method: String, _ path: String, requireFresh: Bool = false) async throws -> T {
        freshFlag = requireFresh
        if offline && requireFresh { throw Failure.offline }
        return CustomerIssuedEstimateRevision(revisionNumber: 2) as! T
    }
    // ACTUAL_READER
}
@main struct Probe {
    @MainActor static func main() async throws {
        let expected = EstimateRecord(id: "estimate", organizationId: "org", customerId: "customer", locationId: nil, status: "sent", currentRevisionNumber: 2)
        let client = APIClient(); _ = try await client.customerIssuedEstimateRevision(for: expected)
        precondition(client.freshFlag == true, "Issued terms must bypass local caches")
        client.offline = true
        do { _ = try await client.customerIssuedEstimateRevision(for: expected); preconditionFailure("A saved revision must not satisfy live review") } catch Failure.offline { }
        var authorized = true
        client.afterAggregate = { authorized = false }
        client.freshFlag = nil
        do { _ = try await client.customerIssuedEstimateRevision(for: expected, currentAuthority: { authorized }); preconditionFailure("Retired access") } catch is CancellationError { }
        precondition(client.freshFlag == nil, "No revision request after revocation")
        client.afterAggregate = nil; client.offline = false; client.aggregateStatus = "approved"
        let approved = EstimateRecord(id: "estimate", organizationId: "org", customerId: "customer", locationId: nil, status: "approved", currentRevisionNumber: 2)
        _ = try await client.customerIssuedEstimateRevision(for: approved, allowApprovedForReading: true)
        do { _ = try await client.customerIssuedEstimateRevision(for: approved); preconditionFailure("Approved must not enter signing preparation") } catch Failure.invalid { }
        print("PASS issued revision freshness and retirement")
    }
}
