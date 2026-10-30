import ActivityKit
import Foundation

/// Keeps one Live Activity in step with the job the technician has under way.
/// Nonisolated: ActivityKit's Activity is not Sendable, so it never crosses to the main actor.
enum JobLiveActivity {
    static let liveStatuses: Set<String> = ["en_route", "arrived", "in_progress", "paused"]

    @MainActor private static let lifecycle = JobActivityLifecycle()

    @MainActor
    static func sync(job: JobRecord, status: String, waitingToSync: Bool, customer: String, address: String?,
                     isAuthorized: @escaping @MainActor () -> Bool) async {
        let running = Activity<JobActivityAttributes>.activities
        guard liveStatuses.contains(status) else {
            let matching = running.filter { $0.attributes.jobID == job.id }.map(\.id)
            await lifecycle.perform(endCount: matching.count, isAuthorized: isAuthorized,
                                    end: { await end(id: matching[$0]) }, finish: {})
            return
        }
        let sameJob = running.filter { $0.attributes.jobID == job.id }
        let current = sameJob.first { !addressNeedsReplacement(existing: $0.attributes.address, desired: address) }
        // Preserve the timer when replacing a stale, inferred address.
        let previous = current ?? sameJob.first
        let kept = previous.flatMap { $0.content.state.status == status ? $0.content.state.since : nil }
        let state = JobActivityAttributes.ContentState(status: status, since: JobFiltering.date(stamp(job, status)) ?? kept ?? Date(),
                                                       waitingToSync: waitingToSync)
        let content = ActivityContent(state: state, staleDate: nil)
        // Remove stale-address and duplicate cards before retaining or requesting one card.
        let toEnd = running.filter { $0.id != current?.id }.map(\.id)
        await lifecycle.perform(endCount: toEnd.count, isAuthorized: isAuthorized, end: { index in
            await end(id: toEnd[index])
        }, finish: {
            if let current {
                if current.content.state != state {
                    await update(id: current.id, status: state.status, since: state.since, waitingToSync: state.waitingToSync)
                }
                return
            }
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            let attributes = JobActivityAttributes(jobID: job.id, jobNumber: "JOB-\(job.id.suffix(4).uppercased())",
                                                   title: job.title, customer: customer, address: address)
            _ = try? Activity.request(attributes: attributes, content: content)
        })
    }

    static func addressNeedsReplacement(existing: String?, desired: String?) -> Bool {
        existing != desired
    }

    /// Retire in-flight work synchronously, then dismiss the captured cards before
    /// a later authorized sync can run.
    @MainActor
    static func retire() {
        let running = Activity<JobActivityAttributes>.activities.map(\.id)
        lifecycle.retire(endCount: running.count, end: { await end(id: running[$0]) })
    }

    @MainActor
    static func endAll() async {
        let running = Activity<JobActivityAttributes>.activities.map(\.id)
        await lifecycle.perform(endCount: running.count, isAuthorized: { true },
                                end: { await end(id: running[$0]) }, finish: {})
    }

    private static func end(id: String) async {
        guard let activity = Activity<JobActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    private static func update(id: String, status: String, since: Date, waitingToSync: Bool) async {
        guard let activity = Activity<JobActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        let state = JobActivityAttributes.ContentState(status: status, since: since, waitingToSync: waitingToSync)
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    private static func stamp(_ job: JobRecord, _ status: String) -> String? {
        switch status {
        case "en_route": job.enRouteAt
        case "arrived": job.arrivedAt
        case "in_progress": job.startedAt
        case "paused": job.pausedAt
        default: nil
        }
    }
}

// Coordinates operations across suspension points while ActivityKit ends a card.
@MainActor
final class JobActivityLifecycle {
    private var revision = UUID()
    private var running = 0
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []
    private var retirement: Task<Void, Never>?

    func retire(endCount: Int, end: @escaping @MainActor (Int) async -> Void) {
        revision = UUID()
        let previous = retirement
        retirement = Task { @MainActor in
            await previous?.value
            if running > 0 { await withCheckedContinuation { drainWaiters.append($0) } }
            for index in 0..<endCount { await end(index) }
        }
    }

    func perform(endCount: Int, isAuthorized: () -> Bool,
                 end: (Int) async -> Void, finish: () async -> Void) async {
        let current = UUID()
        revision = current
        await retirement?.value
        if running > 0 { await withCheckedContinuation { drainWaiters.append($0) } }
        func mayContinue() -> Bool { revision == current && !Task.isCancelled && isAuthorized() }
        guard mayContinue() else { return }
        running += 1
        defer {
            running -= 1
            if running == 0 {
                let waiters = drainWaiters
                drainWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
        }
        for index in 0..<endCount {
            guard mayContinue() else { return }
            await end(index)
        }
        guard mayContinue() else { return }
        await finish()
    }
}
