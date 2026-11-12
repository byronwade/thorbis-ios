# Invoice draft recovery foundation

This is an **unconnected foundation**. The editor does not yet save, load, show, or submit these snapshots. It must not be treated as draft recovery available to a technician.

Each snapshot stores the unmodified editor strings, line identities, source evidence, override reason, and the invoice baseline. It is scoped to actor, organization, API origin, invoice, customer, and job. Keychain entries use a hashed scope and a random snapshot ID. They are insert-only: a duplicate ID fails rather than overwriting another editor or an uncertain write. Ordinary removal refuses an uncertain snapshot.

The caller must construct the scope from the **authenticated session and `APIClient.normalizedOrigin`**, not from a request, preview, stale screen, or persisted value. A valid-looking scope is not authorization. Before disclosing or restoring text, independently obtain a fresh server invoice under current authority; verify actor, tenant, origin and invoice/job/customer identity, edit permission and the exact baseline. The `fresh`, `canEdit`, and `noUnresolvedAttempts` flags are assertions by the caller, not proof supplied by this foundation. A changed invoice must be reviewed, not silently overwritten.

The `inFlightOrUncertain` marker only blocks restoration of that particular snapshot. The caller must also account for *all* snapshots and any pending or ambiguous server request before allowing editing/submission. A Boolean check and Keychain insertion alone do not provide an atomic submission lease, prevent a concurrent writer, or prove an attempted server write did not commit. A future integration must define and test a crash-safe write-ahead protocol, reconciliation and cross-snapshot fencing before sending a financial mutation. Never reuse snapshot IDs. Do not automatically remove snapshots after a timeout, cancellation, or ambiguous result.

Retention is intentionally unresolved. A production design needs a bounded policy that preserves unresolved attempts, explicit user review/deletion, a verified-save cleanup rule, account sign-out and erasure behavior, Keychain access failures, and migration/version handling. It must avoid losing edits while preventing exposure to another account. The synchronous Security calls run inside a dedicated actor rather than the UI actor, but Keychain latency, accessibility and cancellation still require real-device qualification.

The host probe compiles the production recovery source with model and Keychain transport doubles. It checks raw text and provenance roundtrips, scope/origin/freshness and baseline rejection, unresolved-write rejection, immutable duplicate insertion, scope isolation, explicit removal and injected storage errors. It does **not** prove iOS Keychain entitlements, real Keychain concurrency, production model typechecking, mounted editor behavior, lifecycle safety, or crash-safe submission.

Run the lightweight probe from the repository root:

```sh
swiftc -swift-version 6 scripts/tests/invoice_recovery_probe.swift Thorbis/Sources/InvoiceDraftRecovery.swift -o /private/tmp/thorbis-invoice-recovery-probe
/private/tmp/thorbis-invoice-recovery-probe
```
