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
    let isLoadingMore: Bool
    let unavailableIDs: [String]
    init(scope: JobDocumentScope, records: [Record], freshIDs: Set<String>, isComplete: Bool,
         unavailableIDs: [String] = [], kind: String, loadingMore: Bool = false) {
        self.scope = scope; self.records = records; self.freshIDs = freshIDs
        self.isComplete = isComplete; self.isLoadingMore = loadingMore; self.unavailableIDs = unavailableIDs
    }
}
struct Problem: Error { let status: Int?; let title: String?; init(status: Int?, title: String? = nil) { self.status = status; self.title = title } }
enum SavedCopies { @TaskLocal static var liveOnly = false }
struct APIRead<Value> { let value: Value; let provenance: Provenance }
struct Provenance { enum Source { case urlSession(cacheBypassed: Bool), savedCopy(Date) }; let source: Source }
@MainActor final class APIClient {
    let ids: [String]
    var active = 0
    var peak = 0
    var started: [String] = []
    var failure: String?
    var foreign: String?
    var denied: String?
    var savedID: String?
    var markerClearedByAnotherRead = false
    var protocolCachedID: String?
    var savedMembership = false
    var deniedMembership = false
    var membershipReadCount = 0
    init(ids: [String], failure: String? = nil) { self.ids = ids; self.failure = failure }
    func fieldJobEstimateLinks(_ id: String, isCurrent: @MainActor () -> Bool = { true }) async throws -> [JobEstimateLink] {
        membershipReadCount += 1
        if deniedMembership { throw Problem(status: 403) }
        if savedMembership && SavedCopies.liveOnly { throw Problem(status: nil, title: "Network error") }
        return ids.map { .init(jobId: id, estimateId: $0) }
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
    func fieldEstimateWithProvenance(_ id: String, requireFresh: Bool = false, saveIfCurrent: @MainActor () -> Bool = { true }) async throws -> APIRead<EstimateRecord> {
        let fresh = requireFresh || SavedCopies.liveOnly
        if fresh && (id == savedID || id == protocolCachedID) { throw Problem(status: nil, title: "Network error") }
        let record = try await fieldEstimate(id)
        return .init(value: record, provenance: .init(source: id == savedID ? .savedCopy(Date()) : .urlSession(cacheBypassed: fresh)))
    }
    func savedCopyDate(_ path: String) -> Date? { !markerClearedByAnotherRead && path == savedID.map { "/v1/estimates/\($0)" } ? Date() : nil }
}

@main struct Probe {
    @MainActor static func main() async {
        let scope = JobDocumentScope(jobID: "job", organizationID: "org", customerID: "customer", originEstimateID: nil)
        let ids = (0..<12).map(String.init)
        let pagedAPI = APIClient(ids: ids)
        let page = await JobDocumentsLoader.estimatesForPage(scope: scope, api: pagedAPI, ids: ["0", "1"],
                                                               previous: nil, membershipFresh: true, membershipComplete: false,
                                                               isCurrent: { true })!
        precondition(pagedAPI.started == ["0", "1"], "Only requested page details should be fetched")
        precondition(page.records.map(\.id) == ["0", "1"] && !page.isComplete, "Incomplete membership must not authorize approval")
        let second = await JobDocumentsLoader.estimatesForPage(scope: scope, api: pagedAPI, ids: ["0", "1", "2"],
                                                                 previous: page, membershipFresh: true, membershipComplete: true,
                                                                 isCurrent: { true })!
        precondition(pagedAPI.started == ["0", "1", "2"], "Previous page details must not be refetched")
        precondition(second.records.map(\.id) == ["0", "1", "2"] && second.isComplete)
        let stale = await JobDocumentsLoader.estimatesForPage(scope: scope, api: pagedAPI, ids: ["0", "1", "2"],
                                                                previous: second, membershipFresh: false, membershipComplete: true,
                                                                isCurrent: { true })!
        precondition(!stale.isComplete && stale.freshIDs.isEmpty, "Cached membership must not enable approval")
        let failedPage = await JobDocumentsLoader.estimatesForPage(scope: scope, api: APIClient(ids: ids, failure: "1"), ids: ["0", "1"],
                                                                    previous: nil, membershipFresh: true, membershipComplete: true,
                                                                    isCurrent: { true })!
        precondition(!failedPage.isComplete && failedPage.unavailableIDs == ["1"], "A failed detail must keep the full set incomplete")
        let savedAPI = APIClient(ids: ids); savedAPI.savedID = "1"
        let savedPage = await JobDocumentsLoader.estimatesForPage(scope: scope, api: savedAPI, ids: ["0", "1"],
                                                                   previous: nil, membershipFresh: true, membershipComplete: true,
                                                                   isCurrent: { true })!
        precondition(!savedPage.isComplete && !savedPage.freshIDs.contains("1"), "Saved details cannot make the set complete")
        let savedShared = await JobDocumentsLoader.estimates(scope: scope, api: savedAPI, retaining: nil, isCurrent: { true })!
        precondition(!savedShared.isComplete && savedShared.records.contains { $0.id == "1" } && !savedShared.freshIDs.contains("1"),
                     "A shared job collection must retain a saved row but mark the collection incomplete")
        let cachedLinksAPI = APIClient(ids: ["1"]); cachedLinksAPI.savedMembership = true; cachedLinksAPI.markerClearedByAnotherRead = true
        let cachedLinks = await JobDocumentsLoader.estimates(scope: scope, api: cachedLinksAPI, retaining: nil, isCurrent: { true })!
        precondition(!cachedLinks.isComplete && cachedLinks.records.map(\.id) == ["1"] && cachedLinks.freshIDs.isEmpty,
                     "A saved membership page must remain incomplete even if a concurrent network read cleared the path marker")
        let deniedLinksAPI = APIClient(ids: ["1"]); deniedLinksAPI.deniedMembership = true
        let deniedLinks = await JobDocumentsLoader.estimates(scope: scope, api: deniedLinksAPI, retaining: nil, isCurrent: { true })!
        precondition(!deniedLinks.isComplete && deniedLinks.records.isEmpty && deniedLinksAPI.membershipReadCount == 1,
                     "Denied membership must not retry using cached links")
        let racedAPI = APIClient(ids: ids); racedAPI.savedID = "1"; racedAPI.markerClearedByAnotherRead = true
        let racedPage = await JobDocumentsLoader.estimatesForPage(scope: scope, api: racedAPI, ids: ["1"],
            previous: nil, membershipFresh: true, membershipComplete: true, isCurrent: { true })!
        precondition(!racedPage.isComplete && !racedPage.freshIDs.contains("1"), "A concurrent fresh read must not turn a saved response into a fresh estimate")
        let protocolAPI = APIClient(ids: ids); protocolAPI.protocolCachedID = "1"
        let protocolPage = await JobDocumentsLoader.estimatesForPage(scope: scope, api: protocolAPI, ids: ["1"],
            previous: nil, membershipFresh: true, membershipComplete: true, isCurrent: { true })!
        precondition(protocolPage.records.count == 1 && !protocolPage.isComplete && protocolPage.freshIDs.isEmpty,
                     "A protocol-cache response remains visible but cannot enable a customer decision")
        var pagePartials: [JobDocumentRead<EstimateRecord>] = []
        let partialPage = await JobDocumentsLoader.estimatesForPage(scope: scope, api: APIClient(ids: ids), ids: ids,
            previous: nil, membershipFresh: true, membershipComplete: false, isCurrent: { true },
            onPartial: { pagePartials.append($0) })!
        precondition(!pagePartials.isEmpty && pagePartials[0].records.count < partialPage.records.count,
                     "First page cards must appear before all its detail reads finish")
        precondition(pagePartials.allSatisfy { !$0.isComplete }, "A partial page must never enable approval")
        let api = APIClient(ids: ids, failure: "5")
        var partials: [JobDocumentRead<EstimateRecord>] = []
        let result = await JobDocumentsLoader.estimates(scope: scope, api: api, retaining: nil, isCurrent: { true },
                                                         onPartial: { partials.append($0) })!
        precondition(!partials.isEmpty && !partials[0].isComplete, "First cards must publish before all details finish")
        precondition(partials[0].records.count < ids.count, "An early update must not wait for the full list")
        precondition(partials.allSatisfy { !$0.isComplete }, "Partial lists may never authorize complete-set actions")
        precondition(partials.allSatisfy(\.isLoadingMore) && !result.isLoadingMore, "Active loading must be distinguishable from a failed result")
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
