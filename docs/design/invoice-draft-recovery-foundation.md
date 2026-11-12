# Invoice draft recovery foundation

This is an **unconnected foundation**. The editor does not yet save, load, show, or submit these snapshots. It must not be treated as draft recovery available to a technician.

Each snapshot stores the unmodified editor strings, line identities, source evidence, override reason, and the invoice baseline. It is scoped to actor, organization, API origin, invoice, customer, and job. Keychain entries use a hashed scope and a random snapshot ID. They are insert-only: a duplicate ID fails rather than overwriting another editor or an uncertain write. There is no snapshot deletion API in this foundation.

The caller must construct the scope from the **authenticated session and `APIClient.normalizedOrigin`**, not from a request, preview, stale screen, or persisted value. A valid-looking scope is not authorization. Before disclosing or restoring text, independently obtain a fresh server invoice under current authority; verify actor, tenant, origin and invoice/job/customer identity, edit permission and the exact baseline. The `fresh`, `canEdit`, and `noUnresolvedAttempts` flags are assertions by the caller, not proof supplied by this foundation. A changed invoice must be reviewed, not silently overwritten.

Before a send, `beginSubmission` can insert a single immutable marker containing an attempt ID, snapshot ID, expected revision and SHA-256 computed from supplied request bytes. The marker key uses organization, origin and invoice; changes to actor, customer or job must not evade it. Public lookup returns only a generic pending flag; authorized disclosure of marker details for reconciliation is not implemented. A successful insert blocks store-mediated restoration and a second attempt for that domain; a failed insert must not permit sending. An uncertain snapshot found in the requested actor scope also blocks restoration. This is an unconnected primitive, not a complete write-ahead protocol: checking snapshots and inserting the marker are separate Keychain operations, a previously returned editor remains usable, and nothing forces a caller to mark before sending or send the same bytes. A caller-supplied Boolean is not a lease. Cross-process races, crash timing, request identity and authoritative reconciliation must be designed and verified before any financial mutation uses this foundation. Never reuse snapshot or attempt IDs. There is intentionally no marker-clearing API.

New snapshot insertion accepts only idle state; uncertain submission state must be represented by the invoice-wide marker. Earlier prototype data could contain actor-scoped uncertain snapshots without such a marker, and this implementation cannot discover another actor's snapshots from its hashed Keychain account. No version has been shipped. Any migration or integration must explicitly account for those legacy states instead of assuming the marker is exhaustive.

Retention is intentionally unresolved. A production design needs a bounded policy that preserves unresolved attempts, explicit user review/deletion, a verified-save cleanup rule, account sign-out and erasure behavior, Keychain access failures, and migration/version handling. It must avoid losing edits while preventing exposure to another account. The synchronous Security calls run inside a dedicated actor rather than the UI actor, but Keychain latency, accessibility and cancellation still require real-device qualification.

The host probe compiles the production recovery source with model and Keychain transport doubles. It checks raw text and provenance roundtrips, scope/origin/freshness and baseline rejection, unresolved-write rejection, immutable duplicate insertion, scope isolation, explicit removal and injected storage errors. It does **not** prove iOS Keychain entitlements, real Keychain concurrency, production model typechecking, mounted editor behavior, lifecycle safety, or crash-safe submission.

Run the lightweight probe from the repository root:

```sh
swiftc -swift-version 6 -D INVOICE_RECOVERY_HOST_TEST scripts/tests/invoice_recovery_probe.swift Thorbis/Sources/InvoiceDraftRecovery.swift -o /private/tmp/thorbis-invoice-recovery-probe
/private/tmp/thorbis-invoice-recovery-probe
```
