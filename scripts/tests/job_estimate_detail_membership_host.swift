import Foundation
struct JobEstimateLink { let jobId: String; let estimateId: String }
struct Problem: Error { let status: Int? }
@main struct Probe {
    @MainActor static func main() async throws {
        var lists = 0; var current = true
        let link = JobEstimateLink(jobId: "job", estimateId: "estimate")
        try await JobEstimateDetailMembership.verify(jobID: "job", estimateID: "estimate", originID: nil, isCurrent: { current }, read: { link }, list: { lists += 1; return [link] })
        precondition(lists == 0, "An existing link should not require a full list")
        try await JobEstimateDetailMembership.verify(jobID: "job", estimateID: "estimate", originID: "estimate", isCurrent: { current }, read: { throw Problem(status: 404) }, list: { lists += 1; return [] })
        precondition(lists == 0, "The verified job's origin may be unlinked")
        try await JobEstimateDetailMembership.verify(jobID: "job", estimateID: "estimate", originID: nil, isCurrent: { current }, read: { throw Problem(status: 404) }, list: { lists += 1; return [link] })
        precondition(lists == 1, "Older servers may use a fresh list fallback")
        do { try await JobEstimateDetailMembership.verify(jobID: "job", estimateID: "estimate", originID: "estimate", isCurrent: { current }, read: { throw Problem(status: 403) }, list: { lists += 1; return [link] }); preconditionFailure("403 must not fall back") } catch let p as Problem { precondition(p.status == 403) }
        do { try await JobEstimateDetailMembership.verify(jobID: "job", estimateID: "estimate", originID: nil, isCurrent: { current }, read: { throw Problem(status: 404) }, list: { [] }); preconditionFailure("Removed link accepted") } catch is JobEstimateDetailMembership.InvalidMembership { }
        do { try await JobEstimateDetailMembership.verify(jobID: "job", estimateID: "estimate", originID: nil, isCurrent: { current }, read: { throw Problem(status: 404) }, list: { current = false; return [link] }); preconditionFailure("Retired authority after fallback") } catch is CancellationError { }
        current = true
        do { try await JobEstimateDetailMembership.verify(jobID: "job", estimateID: "estimate", originID: nil, isCurrent: { current }, read: { .init(jobId: "other", estimateId: "estimate") }, list: { lists += 1; return [link] }); preconditionFailure("Foreign membership") } catch is JobEstimateDetailMembership.InvalidMembership { }
        do { try await JobEstimateDetailMembership.verify(jobID: "job", estimateID: "estimate", originID: nil, isCurrent: { current }, read: { current = false; return link }, list: { lists += 1; return [link] }); preconditionFailure("Retired authority") } catch is CancellationError { }
        print("PASS targeted membership checks")
    }
}
