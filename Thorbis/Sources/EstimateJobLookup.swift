import Foundation

/// Finds the job an estimate belongs to when the estimate was opened without one (the Estimates
/// list). The server has no estimate-to-job link, so this asks the customer's own jobs, a few at
/// most, for their estimates through the caller's existing read. It only chooses which existing
/// "Show customer" entry to call: no match means the single presentation, as before.
enum EstimateJobLookup {
    static let cap = 8

    /// The customer's jobs to ask, in order: open jobs first (not completed or canceled), then the
    /// rest, each group most recent first; never more than `cap`.
    static func candidates(_ jobs: [Job], customerID: String, cap: Int = EstimateJobLookup.cap) -> [Job] {
        let closed: Set<String> = ["completed", "canceled", "cancelled"]
        func stamp(_ job: Job) -> String { job.updatedAt ?? job.scheduledFor ?? job.createdAt ?? "" }
        let own = jobs.filter { $0.customerId?.caseInsensitiveCompare(customerID) == .orderedSame }
            .sorted { stamp($0) > stamp($1) }
        return Array((own.filter { !closed.contains($0.status) } + own.filter { closed.contains($0.status) }).prefix(max(cap, 0)))
    }

    /// The first candidate job whose estimates contain `estimateID`, asked one at a time. Stops at
    /// the first match, when a read fails, when `isCurrent` turns false or the task is cancelled.
    @MainActor
    static func jobID(for estimateID: String, customerID: String, jobs: [Job], cap: Int = EstimateJobLookup.cap,
                      isCurrent: @MainActor () -> Bool = { true },
                      estimateIDs: @MainActor (String) async throws -> [String]) async -> String? {
        for job in candidates(jobs, customerID: customerID, cap: cap) {
            guard isCurrent(), !Task.isCancelled else { return nil }
            guard let ids = try? await estimateIDs(job.id) else { return nil }
            guard isCurrent(), !Task.isCancelled else { return nil }
            if ids.contains(where: { $0.caseInsensitiveCompare(estimateID) == .orderedSame }) { return job.id }
        }
        return nil
    }
}
