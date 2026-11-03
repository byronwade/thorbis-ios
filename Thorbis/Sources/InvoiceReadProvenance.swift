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
    private var pending: [UUID: InvoiceReadScope] = [:]
    private var latest: UUID?
    private var grant: (scope: InvoiceReadScope, invoices: [UUID: String])?

    mutating func begin(scope: InvoiceReadScope) -> InvoiceReadTicket {
        let ticket = InvoiceReadTicket(id: UUID(), scope: scope)
        pending[ticket.id] = scope
        latest = ticket.id
        grant = nil
        return ticket
    }

    /// Publication requires every cursor in the chain and a validated network
    /// response for each; a saved page makes the whole membership read stale.
    mutating func publish(_ ticket: InvoiceReadTicket, current: InvoiceReadScope?,
                          pages: [InvoiceReadPage], invoices: [UUID: String]) -> Bool {
        guard pending.removeValue(forKey: ticket.id) == ticket.scope,
              latest == ticket.id, current == ticket.scope else { return false }
        latest = nil
        guard !pages.isEmpty else { return false }
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
        grant = (ticket.scope, invoices)
        return true
    }

    /// A denial from an older outstanding read still retires a later grant for
    /// the same actor, tenant, origin and job, including after authority changes.
    mutating func deny(_ ticket: InvoiceReadTicket, current: InvoiceReadScope?) {
        guard pending.removeValue(forKey: ticket.id) == ticket.scope else { return }
        guard let current else { grant = nil; latest = nil; return }
        guard ticket.scope.sameResource(as: current) else { return }
        grant = nil
        latest = nil
    }

    mutating func cancel(_ ticket: InvoiceReadTicket) {
        guard pending.removeValue(forKey: ticket.id) == ticket.scope else { return }
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
