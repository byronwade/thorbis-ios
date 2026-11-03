import Foundation

/// Held integration seam. No product view invokes it. `isCurrent` must re-read
/// the verified persisted authority and match the current runtime actor, tenant,
/// origin, job, session, policy and API generations. `fetch` must perform a
/// fresh, uncached read; only an actual 401/403/404 maps to `.denied`.
@MainActor final class JobOfficeColdReadCoordinator {
    enum LiveResult {
        case success(JobRecord)
        case denied
        case connectivity
        case cancelled
        case failed
    }
    enum Outcome {
        case live(JobOfficeColdOfflineStore.Snapshot)
        case offline(JobOfficeColdOfflineStore.Snapshot)
        case denied
        case retired
        case unavailable
    }
    private let store: JobOfficeColdOfflineStore
    init(store: JobOfficeColdOfflineStore) { self.store = store }

    func read(scope: JobOfficeColdScope, isCurrent: @MainActor () -> Bool,
              fetch: @MainActor () async -> LiveResult) async -> Outcome {
        guard !Task.isCancelled, isCurrent() else { return .retired }
        let ticket: UUID
        do { ticket = try store.beginLive(scope: scope) }
        catch { return .unavailable }
        let response = await fetch()
        // A confirmed denial retires the captured stable identity even if the
        // runtime lease or its deadline expired while the request was in flight.
        if case .denied = response {
            do { try store.deny(scope: scope); return .denied }
            catch { return .unavailable }
        }
        guard !Task.isCancelled, isCurrent() else {
            try? store.abandon(scope: scope, ticket: ticket)
            return .retired
        }
        switch response {
        case .success(let job):
            do {
                guard let snapshot = try store.completeLive(scope: scope, ticket: ticket, job: job, stillAuthorized: true) else { return .unavailable }
                return .live(snapshot)
            } catch {
                try? store.abandon(scope: scope, ticket: ticket)
                return .unavailable
            }
        case .connectivity:
            do {
                if let snapshot = try store.restoreAfterConnectivityFailure(scope: scope, ticket: ticket, stillAuthorized: true) {
                    return .offline(snapshot)
                }
                try? store.abandon(scope: scope, ticket: ticket)
                return .unavailable
            } catch {
                try? store.abandon(scope: scope, ticket: ticket)
                return .unavailable
            }
        case .cancelled:
            try? store.abandon(scope: scope, ticket: ticket)
            return .retired
        case .failed:
            try? store.abandon(scope: scope, ticket: ticket)
            return .unavailable
        case .denied:
            return .unavailable // handled before checking cancellation/current scope
        }
    }
}
