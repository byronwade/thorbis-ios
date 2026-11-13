# Customer invoice summary: held mobile contract

Technicians present job invoices to a customer on a shared device. Each customer-visible
invoice must come from the server's purpose-specific, unsigned presentation, bound to
the active organization, customer, job, invoice and line revision. All visible totals,
discounts, payments and line descriptions must reconcile. A customer can hand the
phone back and return to any invoice. A server failure, stale authority, offline state or
unsupported invoice presents a clear retry/handback state, never raw staff invoice lines.

This first, unshipped slice only decodes and validates the draft server response. It
is not wired to the book, standalone presentation, read-only paper or overview. Before
any release, adapt all those paths, handle exact API/session authority across loading,
disappearance and account changes, preserve payment history and navigation, and test
phone/iPad accessibility. A transformed summary is not a signed document; signing
must wait for server consent bound to the exact displayed summary. Review legacy and
old-client rollout with the backend before enabling this contract. No screenshots,
production backend or TestFlight claim is implied by these contract tests.

## Evidence and holds

- Test-first build failed on the missing DTO: `/private/tmp/thorbis-customer-summary-mobile-red-1113.log`.
- The final focused simulator run passed one contract test with multiple identity,
  snapshot and amount cases: `/private/tmp/thorbis-customer-summary-mobile-final-1113.log`.
- The contract is not connected to any screen or transport. Fresh-response,
  capability/session retirement, account switching, source provenance, exact
  signing consent, customer book and standalone/read-only presentations, payment
  actions, long content and actual device accessibility have not been verified.
- The backend is separately held. Old clients, public/document dispatch and
  ambiguous legacy invoices still require a coordinated rollout and review.
  Do not merge or deploy this slice as a privacy fix.
