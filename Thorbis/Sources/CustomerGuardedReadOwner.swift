import Foundation
import Combine

enum CustomerGuardedReadEvidence {
    // Until an authoritative complete-read contract exists, production cannot
    // claim a compilation is complete and thereby clear a denial marker.
    #if DEBUG
    case completeLive
    #endif
    case limitedLive, cached
}
enum CustomerGuardedReadError: Error { case transportNotScoped, stale, denied }
struct CustomerGuardedValue<Value> { let value: Value; let evidence: CustomerGuardedReadEvidence }

struct CustomerGuardedSnapshot<Value> {
    fileprivate let value: Value
    fileprivate let ticket: CustomerQuarantineTicket
    fileprivate let sessionID: UUID
}

@MainActor final class CustomerGuardedReadOwner<Value>: ObservableObject {
    @Published private(set) var snapshot: CustomerGuardedSnapshot<Value>?
    private let quarantine: CustomerQuarantine
    private var generation = UUID()
    private var subscription: AnyCancellable?
    private var expiryTask: Task<Void, Never>?
    init(quarantine: CustomerQuarantine) {
        self.quarantine = quarantine
        subscription = quarantine.$revision.dropFirst().sink { [weak self] _ in
            self?.retireInvalidSnapshot()
        }
    }
    private func retireInvalidSnapshot() {
        guard let snapshot, !quarantine.allowsPublishedValue(snapshot.ticket) else { return }
        self.snapshot = nil
    }
    func visibleValue(scope: CustomerQuarantineScope, authority: CustomerQuarantineAuthority, sessionID: UUID) -> Value? {
        guard let snapshot, snapshot.ticket.scope == scope, Date() < snapshot.ticket.authorityDeadline,
              snapshot.sessionID == sessionID,
              let fingerprint = try? authority.fingerprint(for: scope), fingerprint == snapshot.ticket.authorityFingerprint else { return nil }
        return snapshot.value
    }
    func invalidate() {
        generation = UUID()
        expiryTask?.cancel()
        expiryTask = nil
        snapshot = nil
    }
    // Call on foreground and significant wall-clock changes; the sleeping
    // deadline task alone cannot observe a clock jump or a suspended process.
    func recheckDeadline(now: Date = Date()) {
        guard let snapshot, now >= snapshot.ticket.authorityDeadline else { return }
        expiryTask?.cancel()
        expiryTask = nil
        self.snapshot = nil
    }
    func refresh(scope: CustomerQuarantineScope, authority: CustomerQuarantineAuthority, sessionID: UUID,
                 isCurrent: @escaping @MainActor () -> Bool,
                 read: @escaping @MainActor () async throws -> CustomerGuardedValue<Value>) async throws {
        guard isCurrent(), !Task.isCancelled else { throw CustomerGuardedReadError.stale }
        expiryTask?.cancel()
        expiryTask = nil
        snapshot = nil
        let attempt = UUID()
        generation = attempt
        let ticket = try quarantine.begin(scope, authority: authority)
        var finished = false
        do {
            let loaded = try await SavedCopies.$liveOnly.withValue(ticket.requiresLive || SavedCopies.liveOnly) {
                try await SavedCopies.$customerNamespace.withValue(ticket.cacheNamespace) {
                    guard isCurrent(), !Task.isCancelled else { throw CustomerGuardedReadError.stale }
                    return try await read()
                }
            }
            guard generation == attempt, isCurrent(), !Task.isCancelled else { throw CustomerGuardedReadError.stale }
            let outcome: CustomerQuarantineOutcome
            switch loaded.evidence {
            #if DEBUG
            case .completeLive: outcome = .liveCompilation
            #endif
            case .limitedLive: outcome = .liveActivity
            case .cached: outcome = .cached
            }
            let accepted = try quarantine.finish(ticket, outcome: outcome)
            finished = true
            guard accepted, generation == attempt, isCurrent(), !Task.isCancelled else { throw CustomerGuardedReadError.stale }
            guard quarantine.allowsPublishedValue(ticket) else { throw CustomerGuardedReadError.stale }
            snapshot = CustomerGuardedSnapshot(value: loaded.value, ticket: ticket, sessionID: sessionID)
            expiryTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(max(0, ticket.authorityDeadline.timeIntervalSinceNow))) }
                catch { return }
                guard let self, self.snapshot?.ticket.id == ticket.id else { return }
                self.snapshot = nil
            }
        } catch {
            if generation == attempt {
                snapshot = nil
            }
            if !finished {
                let outcome: CustomerQuarantineOutcome
                if case CustomerGuardedReadError.denied = error { outcome = .denied }
                else if case CustomerGuardedReadError.stale = error { outcome = .retired }
                else { outcome = .uncertain }
                _ = try? quarantine.finish(ticket, outcome: outcome)
            }
            throw error
        }
    }
}
