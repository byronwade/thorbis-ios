import Foundation

/// Held calculation only. Callers must prove each page's actual response source,
/// ordered cursor, exact invoice digest and authorization before using a grant.
struct InvoiceReadScope: Equatable {
    let actor: UUID, organization: UUID, job: UUID, customer: UUID
    /// Caller supplies the normalized API origin.
    let origin: String
    let session: UUID, authority: UUID, transport: UUID

    fileprivate func sameResource(as other: Self) -> Bool {
        actor == other.actor && organization == other.organization && job == other.job && origin == other.origin
    }
}

struct InvoiceReadPage {
    enum Source { case networkValidated, savedCopy }
    let cursor: String?, next: String?
    let source: Source
}

struct InvoiceReadTicket { let id: UUID; let scope: InvoiceReadScope }

/// In-memory only, unwired. Does not replace resource authorization or durable
/// denial handling and cannot prove anything about changes while offline.
struct InvoiceReadProvenance {
    private struct Pending {
        let scope: InvoiceReadScope
        var canceled: Bool
        var denied: Bool
        /// A read started while another request for the same job was unresolved
        /// cannot establish authority, even if it later completes successfully.
        let overlapped: Bool
    }
    private var pending: [UUID: Pending] = [:]
    private var latest: UUID?
    private var grant: (scope: InvoiceReadScope, invoices: [UUID: String])?

    mutating func begin(scope: InvoiceReadScope) -> InvoiceReadTicket {
        let ticket = InvoiceReadTicket(id: UUID(), scope: scope)
        let overlapped = pending.values.contains { $0.scope.sameResource(as: scope) }
        pending[ticket.id] = Pending(scope: scope, canceled: false, denied: false, overlapped: overlapped)
        latest = ticket.id
        grant = nil
        return ticket
    }

    /// Publication requires every cursor in the chain and a validated network
    /// response for each; a saved page makes the whole membership read stale.
    /// `allRequestsTerminal` means every child is terminal and all denial
    /// callbacks have been delivered, not merely that cancellation was requested.
    mutating func publish(_ ticket: InvoiceReadTicket, current: InvoiceReadScope?,
                          pages: [InvoiceReadPage], invoices: [UUID: String],
                          allRequestsTerminal: Bool) -> Bool {
        guard let request = pending[ticket.id], request.scope == ticket.scope else { return false }
        // A canceled multi-page read may still have child requests in flight.
        // Only a definitive terminal signal or denial can retire its ticket.
        guard !request.canceled, !request.denied, !request.overlapped, allRequestsTerminal,
              !pending.contains(where: { $0.key != ticket.id && $0.value.scope.sameResource(as: ticket.scope) }) else { return false }
        guard latest == ticket.id, current == ticket.scope, !pages.isEmpty else { return false }
        var expected: String?
        var seen = Set<String>()
        for (index, page) in pages.enumerated() {
            guard (index == 0 || expected != nil), page.cursor == expected,
                  page.source == .networkValidated else { return false }
            if let next = page.next {
                guard !next.isEmpty, seen.insert(next).inserted else { return false }
            }
            expected = page.next
        }
        guard expected == nil, invoices.values.allSatisfy(Self.validDigest) else { return false }
        pending.removeValue(forKey: ticket.id)
        latest = nil
        grant = (ticket.scope, invoices)
        return true
    }

    /// A denial from an older outstanding read still retires a later grant for
    /// the same actor, tenant, origin and job, including after authority changes.
    mutating func deny(_ ticket: InvoiceReadTicket, current: InvoiceReadScope?) {
        guard var request = pending[ticket.id], request.scope == ticket.scope else { return }
        request.denied = true
        pending[ticket.id] = request
        guard let current else { grant = nil; latest = nil; return }
        guard ticket.scope.sameResource(as: current) else { return }
        grant = nil
        latest = nil
    }

    /// Cancellation stops publication, but does not prove the transport is done.
    /// Keep the ticket until its terminal result is observed so a late denial
    /// can still invalidate a subsequent grant.
    mutating func cancel(_ ticket: InvoiceReadTicket) {
        guard var request = pending[ticket.id], request.scope == ticket.scope else { return }
        request.canceled = true
        pending[ticket.id] = request
        if latest == ticket.id { latest = nil; grant = nil }
    }

    /// Call only after every child transport has definitively terminated and
    /// every denial callback was passed to `deny`. Requesting cancellation is not enough.
    mutating func finishCanceled(_ ticket: InvoiceReadTicket) {
        guard let request = pending[ticket.id], request.scope == ticket.scope, request.canceled else { return }
        pending.removeValue(forKey: ticket.id)
    }

    /// Retire a non-published read only after every child request is terminal
    /// and every denial callback has been delivered and reported. Do not call on mere failure
    /// to publish, because other child requests may still return a denial.
    mutating func finishWithoutGrant(_ ticket: InvoiceReadTicket) {
        guard let request = pending[ticket.id], request.scope == ticket.scope else { return }
        pending.removeValue(forKey: ticket.id)
        if latest == ticket.id { latest = nil; grant = nil }
    }

    func permits(scope: InvoiceReadScope, invoice: UUID, digest: String) -> Bool {
        guard let grant, grant.scope == scope, Self.validDigest(digest) else { return false }
        return grant.invoices[invoice] == digest
    }

    private static func validDigest(_ digest: String) -> Bool {
        digest.utf8.count == 64 && digest.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
