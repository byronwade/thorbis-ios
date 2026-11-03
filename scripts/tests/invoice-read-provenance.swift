import Foundation

@main enum InvoiceReadProvenanceChecks {
    static func main() {
        var failures = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { print("FAIL: \(message)"); failures += 1 }
        }
        let actor = UUID(), organization = UUID(), job = UUID(), customer = UUID()
        let scope = InvoiceReadScope(actor: actor, organization: organization, job: job, customer: customer,
                                     origin: "https://app.thorbis.com", session: UUID(), authority: UUID(), transport: UUID())
        let invoice = UUID(), digest = String(repeating: "a", count: 64)
        let livePages = [InvoiceReadPage(cursor: nil, next: "next", source: .networkValidated),
                         InvoiceReadPage(cursor: "next", next: nil, source: .networkValidated)]
        var state = InvoiceReadProvenance()
        let first = state.begin(scope: scope)
        expect(state.publish(first, current: scope, pages: livePages, invoices: [invoice: digest]), "two live pages should establish a grant")
        expect(state.permits(scope: scope, invoice: invoice, digest: digest), "matching current invoice should be permitted")
        expect(!state.permits(scope: scope, invoice: invoice, digest: String(repeating: "b", count: 64)), "changed invoice must not inherit grant")
        let mixed = state.begin(scope: scope)
        expect(!state.publish(mixed, current: scope, pages: [.init(cursor: nil, next: "next", source: .savedCopy), livePages[1]], invoices: [invoice: digest]), "saved first page cannot be hidden by later live page")
        expect(!state.permits(scope: scope, invoice: invoice, digest: digest), "mixed snapshot cannot grant access")
        let incomplete = state.begin(scope: scope)
        expect(!state.publish(incomplete, current: scope, pages: [.init(cursor: nil, next: "more", source: .networkValidated)], invoices: [invoice: digest]), "unread continuation cannot grant access")
        let loop = state.begin(scope: scope)
        expect(!state.publish(loop, current: scope, pages: [.init(cursor: nil, next: "x", source: .networkValidated), .init(cursor: "x", next: "x", source: .networkValidated)], invoices: [invoice: digest]), "repeated cursor cannot grant access")
        let extra = state.begin(scope: scope)
        expect(!state.publish(extra, current: scope, pages: [.init(cursor: nil, next: nil, source: .networkValidated), .init(cursor: nil, next: nil, source: .networkValidated)], invoices: [invoice: digest]), "an extra page after the terminal cursor cannot grant access")
        let old = state.begin(scope: scope)
        let fresh = state.begin(scope: scope)
        expect(state.publish(fresh, current: scope, pages: [.init(cursor: nil, next: nil, source: .networkValidated)], invoices: [invoice: digest]), "newer complete response should publish")
        state.deny(old, current: scope)
        expect(!state.permits(scope: scope, invoice: invoice, digest: digest), "late denial must retire newer grant")
        let refreshed = state.begin(scope: scope)
        expect(state.publish(refreshed, current: scope, pages: [.init(cursor: nil, next: nil, source: .networkValidated)], invoices: [invoice: digest]), "fresh response after denial can restore grant")
        let other = InvoiceReadScope(actor: UUID(), organization: organization, job: job, customer: customer,
                                     origin: scope.origin, session: UUID(), authority: UUID(), transport: UUID())
        let otherPending = state.begin(scope: other)
        let ours = state.begin(scope: scope)
        expect(state.publish(ours, current: scope, pages: [.init(cursor: nil, next: nil, source: .networkValidated)], invoices: [invoice: digest]), "current actor can publish while another scope is pending")
        state.deny(otherPending, current: scope)
        expect(state.permits(scope: scope, invoice: invoice, digest: digest), "another actor's denial must not retire this scope")
        let older = state.begin(scope: scope)
        let currentRead = state.begin(scope: scope)
        expect(state.publish(currentRead, current: scope, pages: [.init(cursor: nil, next: nil, source: .networkValidated)], invoices: [invoice: digest]), "latest read is published")
        state.deny(older, current: nil)
        expect(!state.permits(scope: scope, invoice: invoice, digest: digest), "loss of current scope during denial must retire the grant")
        let changed = InvoiceReadScope(actor: actor, organization: organization, job: job, customer: customer,
                                       origin: scope.origin, session: scope.session, authority: UUID(), transport: scope.transport)
        let priorAuthority = state.begin(scope: scope)
        let newAuthority = state.begin(scope: changed)
        expect(state.publish(newAuthority, current: changed, pages: [.init(cursor: nil, next: nil, source: .networkValidated)], invoices: [invoice: digest]), "new authority can publish a new live grant")
        expect(!state.permits(scope: scope, invoice: invoice, digest: digest), "old authority cannot use the new grant")
        state.deny(priorAuthority, current: changed)
        expect(!state.permits(scope: changed, invoice: invoice, digest: digest), "late denial under a prior authority must retire the new grant")
        if failures > 0 { exit(1) }
        print("PASS: invoice provenance checks")
    }
}
