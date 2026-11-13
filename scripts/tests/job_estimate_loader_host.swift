import Foundation

struct EstimateRecord {
    let id: String
    let organizationId = "org"
    let customerId = "customer"
}
struct JobEstimateLink { let jobId: String; let estimateId: String }
struct JobDocumentScope: Equatable {
    let jobID: String
    let organizationID: String
    let customerID: String
    let originEstimateID: String?
    func contains(_ record: EstimateRecord, requestedID: String) -> Bool {
        record.id == requestedID && record.organizationId == organizationID && record.customerId == customerID
    }
}
struct JobDocumentRead<Record> {
    let scope: JobDocumentScope
    let records: [Record]
    let freshIDs: Set<String>
    let isComplete: Bool
    let unavailableIDs: [String]
    init(scope: JobDocumentScope, records: [Record], freshIDs: Set<String>, isComplete: Bool,
         unavailableIDs: [String] = [], kind: String, loadingMore: Bool = false) {
        self.scope = scope; self.records = records; self.freshIDs = freshIDs
        self.isComplete = isComplete; self.unavailableIDs = unavailableIDs
    }
}
struct Problem: Error { let status: Int? }
@MainActor final class APIClient {
    let ids: [String]
    var active = 0
    var peak = 0
    var started: [String] = []
    var failure: String?
    var foreign: String?
    var denied: String?
    init(ids: [String], failure: String? = nil) { self.ids = ids; self.failure = failure }
    func fieldJobEstimateLinks(_ id: String, isCurrent: @MainActor () -> Bool) async throws -> [JobEstimateLink] {
        ids.map { .init(jobId: id, estimateId: $0) }
    }
    func fieldEstimate(_ id: String) async throws -> EstimateRecord {
        active += 1; peak = max(peak, active); started.append(id)
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(id == "0" ? 100 : 15))
        if id == failure { throw Problem(status: 503) }
        if id == denied { throw Problem(status: 403) }
        if id == foreign { return .init(id: "foreign") }
        return .init(id: id)
    }
    func savedCopyDate(_ path: String) -> Date? { nil }
}

@main struct Probe {
    @MainActor static func main() async {
        let scope = JobDocumentScope(jobID: "job", organizationID: "org", customerID: "customer", originEstimateID: nil)
        let ids = (0..<12).map(String.init)
        let api = APIClient(ids: ids, failure: "5")
        var partials: [JobDocumentRead<EstimateRecord>] = []
        let result = await JobDocumentsLoader.estimates(scope: scope, api: api, retaining: nil, isCurrent: { true },
                                                         onPartial: { partials.append($0) })!
        precondition(!partials.isEmpty && !partials[0].isComplete, "First cards must publish before all details finish")
        precondition(partials[0].records.count < ids.count, "An early update must not wait for the full list")
        precondition(partials.allSatisfy { !$0.isComplete }, "Partial lists may never authorize complete-set actions")
        precondition(api.peak == 4 && api.active == 0, "Reads must overlap with a maximum of four")
        precondition(result.records.map(\.id) == ids.filter { $0 != "5" }, "Out-of-order completion must preserve association order")
        precondition(result.unavailableIDs == ["5"] && !result.isComplete, "Failed detail must remain visible as unavailable")
        precondition(!result.freshIDs.contains("5") && result.freshIDs.count == 11)
        let retained = JobDocumentRead(scope: scope, records: [EstimateRecord(id: "5"), EstimateRecord(id: "6")], freshIDs: [], isComplete: true, kind: "estimates")
        let retry = APIClient(ids: ids, failure: "5"); retry.denied = "6"; retry.foreign = "7"
        let guarded = await JobDocumentsLoader.estimates(scope: scope, api: retry, retaining: retained, isCurrent: { true })!
        precondition(guarded.records.contains { $0.id == "5" }, "Retryable failures retain an authorized stale copy")
        precondition(!guarded.freshIDs.contains("5"), "Retained copies cannot approve")
        precondition(!guarded.records.contains { $0.id == "6" || $0.id == "foreign" }, "Denied and foreign results stay hidden")
        precondition(guarded.unavailableIDs == ["6", "7"] && !guarded.isComplete)
        var current = true
        let invalidatedAPI = APIClient(ids: ids)
        var leakedPartials = 0
        let load = Task { @MainActor in
            await JobDocumentsLoader.estimates(scope: scope, api: invalidatedAPI, retaining: nil, isCurrent: { current },
                                               onPartial: { _ in leakedPartials += 1 }) == nil
        }
        while invalidatedAPI.active < 4 { await Task.yield() }
        current = false
        let invalidated = await load.value
        precondition(invalidated, "Authority change must discard the full result")
        precondition(leakedPartials == 0, "No partial may publish after authority changes")
        var stillCurrent = true
        var emitted = 0
        let changedAfterPartial = await JobDocumentsLoader.estimates(scope: scope, api: APIClient(ids: ids), retaining: nil,
            isCurrent: { stillCurrent }, onPartial: { _ in emitted += 1; stillCurrent = false })
        precondition(changedAfterPartial == nil && emitted == 1, "Retiring authority after a partial must stop further publication")
        print("PASS actual estimate loader: bounded concurrency, order, partial failure")
    }
}
