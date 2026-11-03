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
        let one = [InvoiceReadPage(cursor: nil, next: nil, source: .networkValidated)]
        let livePages = [InvoiceReadPage(cursor: nil, next: "next", source: .networkValidated),
                         InvoiceReadPage(cursor: "next", next: nil, source: .networkValidated)]
        var state = InvoiceReadProvenance()
        let first = state.begin(scope: scope)
        expect(state.publish(first, current: scope, pages: livePages, invoices: [invoice: digest], allRequestsTerminal: true), "two live pages should establish a grant")
        expect(state.permits(scope: scope, invoice: invoice, digest: digest), "matching current invoice should be permitted")
        expect(!state.permits(scope: scope, invoice: invoice, digest: String(repeating: "b", count: 64)), "changed invoice must not inherit grant")
        let mixed = state.begin(scope: scope)
        expect(!state.publish(mixed, current: scope, pages: [.init(cursor: nil, next: "next", source: .savedCopy), livePages[1]], invoices: [invoice: digest], allRequestsTerminal: true), "saved first page cannot be hidden by later live page")
        state.finishWithoutGrant(mixed)
        let incomplete = state.begin(scope: scope)
        expect(!state.publish(incomplete, current: scope, pages: [.init(cursor: nil, next: "more", source: .networkValidated)], invoices: [invoice: digest], allRequestsTerminal: true), "unread continuation cannot grant access")
        state.finishWithoutGrant(incomplete)
        let loop = state.begin(scope: scope)
        expect(!state.publish(loop, current: scope, pages: [.init(cursor: nil, next: "x", source: .networkValidated), .init(cursor: "x", next: "x", source: .networkValidated)], invoices: [invoice: digest], allRequestsTerminal: true), "repeated cursor cannot grant access")
        state.finishWithoutGrant(loop)
        let extra = state.begin(scope: scope)
        expect(!state.publish(extra, current: scope, pages: [one[0], one[0]], invoices: [invoice: digest], allRequestsTerminal: true), "extra page after terminal cursor cannot grant access")
        state.finishWithoutGrant(extra)
        let unfinished = state.begin(scope: scope)
        expect(!state.publish(unfinished, current: scope, pages: one, invoices: [invoice: digest], allRequestsTerminal: false), "outstanding children cannot grant access")
        state.finishWithoutGrant(unfinished)

        let canceled = state.begin(scope: scope)
        state.cancel(canceled)
        state.cancel(canceled)
        expect(!state.publish(canceled, current: scope, pages: one, invoices: [invoice: digest], allRequestsTerminal: true), "canceled read cannot publish")
        let overlapping = state.begin(scope: scope)
        expect(!state.publish(overlapping, current: scope, pages: one, invoices: [invoice: digest], allRequestsTerminal: true), "unresolved canceled read must block newer grant")
        state.finishCanceled(canceled)
        expect(!state.publish(overlapping, current: scope, pages: one, invoices: [invoice: digest], allRequestsTerminal: true), "read begun before canceled transport terminated remains untrusted")
        state.finishWithoutGrant(overlapping)
        let afterBarrier = state.begin(scope: scope)
        expect(state.publish(afterBarrier, current: scope, pages: one, invoices: [invoice: digest], allRequestsTerminal: true), "new read begun after terminal may publish")

        let denied = state.begin(scope: scope)
        state.deny(denied, current: scope)
        let whileDenied = state.begin(scope: scope)
        expect(!state.publish(whileDenied, current: scope, pages: one, invoices: [invoice: digest], allRequestsTerminal: true), "unresolved denied read blocks newer grant")
        state.deny(denied, current: scope)
        state.finishWithoutGrant(denied)
        state.finishWithoutGrant(whileDenied)
        let recovered = state.begin(scope: scope)
        expect(state.publish(recovered, current: scope, pages: one, invoices: [invoice: digest], allRequestsTerminal: true), "fresh read after denied request terminates may publish")

        let other = InvoiceReadScope(actor: UUID(), organization: organization, job: job, customer: customer,
                                     origin: scope.origin, session: UUID(), authority: UUID(), transport: UUID())
        let otherPending = state.begin(scope: other)
        let ours = state.begin(scope: scope)
        expect(state.publish(ours, current: scope, pages: one, invoices: [invoice: digest], allRequestsTerminal: true), "different actor's pending read does not block")
        state.deny(otherPending, current: scope)
        expect(state.permits(scope: scope, invoice: invoice, digest: digest), "another actor's denial does not retire the current grant")
        state.finishWithoutGrant(otherPending)

        let otherJob = InvoiceReadScope(actor: actor, organization: organization, job: UUID(), customer: customer,
                                        origin: scope.origin, session: UUID(), authority: UUID(), transport: UUID())
        let otherJobPending = state.begin(scope: otherJob)
        let thisJob = state.begin(scope: scope)
        expect(state.publish(thisJob, current: scope, pages: one, invoices: [invoice: digest], allRequestsTerminal: true), "different job's pending read does not block")
        state.deny(otherJobPending, current: otherJob)
        expect(state.permits(scope: scope, invoice: invoice, digest: digest), "another job's denial does not retire the current grant")
        state.finishWithoutGrant(otherJobPending)
        let laterOtherJob = state.begin(scope: otherJob)
        let laterThisJob = state.begin(scope: scope)
        state.deny(laterOtherJob, current: otherJob)
        expect(state.publish(laterThisJob, current: scope, pages: one, invoices: [invoice: digest], allRequestsTerminal: true), "another job's denial does not drop a newer ticket")
        state.finishWithoutGrant(laterOtherJob)

        let changed = InvoiceReadScope(actor: actor, organization: organization, job: job, customer: customer,
                                       origin: scope.origin, session: scope.session, authority: UUID(), transport: scope.transport)
        let oldAuthority = state.begin(scope: scope)
        let newAuthority = state.begin(scope: changed)
        expect(!state.publish(newAuthority, current: changed, pages: one, invoices: [invoice: digest], allRequestsTerminal: true), "authority change cannot bypass an unresolved same-job read")
        state.deny(oldAuthority, current: changed)
        state.finishWithoutGrant(oldAuthority)
        state.finishWithoutGrant(newAuthority)
        let freshAuthority = state.begin(scope: changed)
        expect(state.publish(freshAuthority, current: changed, pages: one, invoices: [invoice: digest], allRequestsTerminal: true), "fresh read under current authority may publish")
        expect(!state.permits(scope: scope, invoice: invoice, digest: digest), "old authority cannot use the new grant")
        if failures > 0 { exit(1) }
        print("PASS: invoice provenance checks")
    }
}
