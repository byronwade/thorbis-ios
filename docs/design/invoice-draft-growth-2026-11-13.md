# Held invoice draft storage growth

The existing prototype keeps every encrypted capture in the `snapshots` table. A host probe using 100 successive 8,192-byte synthetic edits observed 100 rows and 822,000 ciphertext bytes. This is SQLite row payload only, not an iOS device benchmark or a measurement of WAL, filesystem allocation, keychain, or encryption overhead.

Run from this worktree:

```sh
swiftc -swift-version 6 scripts/tests/invoice_draft_growth_probe.swift Thorbis/Sources/InvoiceTransactionFence.swift Thorbis/Sources/InvoiceDraftCipher.swift -lsqlite3 -o /private/tmp/thorbis-invoice-growth-probe
/private/tmp/thorbis-invoice-growth-probe
```

Do not prune captures just because a newer row exists: the process can die after SQLite commits and before the application receives its acknowledgment, and the existing prototype has no durable acknowledgment frontier. A safe retention design must prove which exact scope, owner, sequence and ciphertext the application observed committed, atomically fence concurrent writers and submission markers, and retain enough history for the previous acknowledged state when the latest commit is ambiguous. It must also handle ambiguous outcomes of the acknowledgment transaction itself, disk-full failures and two-scene competition. The prototype is not connected to the editor, and no retention or recovery feature is shipped by this finding.

The held editor recovery work also needs a cache-bypassing server read before any restore. `liveFieldInvoice` currently rejects a saved phone copy and app-level recent-read reuse, but unlike `liveFieldJob` it does not explicitly bypass URLSession's protocol cache. A separate release-based branch, `codex/financial-live-read-1113`, contains unrun URLRequest regression tests; those tests do not establish current or corrected behavior until executed.

## Held acknowledgment experiment (13 November)

`acknowledgeCapture` is an **unsafe, unshipped experiment**. It checks the exact current scope, owner, sequence, version and ciphertext under a SQLite writer transaction, and prunes older versions only when the head matches. A host subprocess probe covers SIGKILL before and after its commit, an ambiguous post-commit error, retry, and one simultaneous capture/acknowledgment race. These are local host outcomes, not iOS durability proof.

Independent review identified a critical missing boundary: its raw arguments do not prove the caller actually observed capture commit. A capture can commit but throw, after which a caller who knows its bytes and version could call this API and prune the previous acknowledged snapshot. Do not integrate, ship, or treat these tests as proof of safe retention. The design needs an unforgeable successful-commit receipt tied to writer authority, validated under the fence; recovery receipts and uncertain operations must not accidentally confer a right to prune. Verify actual process death, concurrent scenes, ciphertext/key lifecycle, pending submissions and fresh authorization separately.

A subsequent held revision replaces the raw prune entry point with an instance-local random receipt created after `capture` returns successfully. The receipt is consumed after a successful prune; a different instance, stale receipt, and replay fail. A subprocess test simulating capture commit followed by an error retains both versions without issuing a receipt. This process-local capability is experimental: it is not durable across process death and does not prove caller authority, disk or key protection, app lifecycle integration, multiple-scenes behavior, or uncertain submission reconciliation. Prior raw-API crash tests do not qualify this revised API; independent review and fresh crash/race probes are required.

Follow-up: the in-memory registry now drops older receipts for the same domain when a newer capture returns, including when registrations arrive out of order. A host probe passes an ambiguous prune commit followed by same-token retry and two simultaneous acknowledgment attempts where exactly one succeeds. A token certifies only the storage call returned; it does not certify UI retirement acknowledgment, an authoritative current session or that a later capture supersedes every earlier edit. The caller contract and its enforcement remain incomplete. No app integration is permitted on this evidence.

**Critical independent review:** The registration inversion probe first creates a capture that commits but returns an ambiguous error, then deliberately supplies that version to later captures. The current fence accepts the guessed version and the latest acknowledgment can delete the ambiguous snapshot. This demonstrates a missing durable uncertain-capture state or reconciliation protocol. A process-local token and high-water cannot solve this across restarts or cooperating writer instances. The probe's final success only covers registration ordering, not safe retention. Do not use this pruning prototype until the database and caller protocol reject advancement or pruning after an ambiguous capture without verified reconciliation.

### Required durable capture protocol before integration

1. Atomically register a unique, scoped capture intent with expected head, owner, sequence and a digest of the encrypted full snapshot before writing that snapshot. The persisted state must fence any other capture, prune, submission, ownership transfer and recovery while unresolved.
2. In a separate transaction verify that exact intent and expected head, persist the snapshot and mark the intent committed. A crash or thrown result at either transaction must leave the intent unresolved; it must not be inferred resolved from a new process knowing a version number.
3. Only the still-live ordered writer that actually received the success response may use its in-memory receipt to attempt an atomic observed-commit acknowledgment, which validates intent, head, owner and digest. Ambiguous acknowledgment leaves the intent unresolved on restart unless a separately designed reconciliation proves its effect.
4. A restart may expose a user-visible recovery state, but cannot auto-prune or submit while the intent is unresolved. A server-authorized, actor/workspace/document/baseline-checked reconciliation and explicit resolution protocol must establish which full snapshot is safe. Unknown submission markers are independent and must continue to block mutation.
5. Every transition needs real subprocess kill tests around both commits and before/after acknowledgment, same-domain concurrent owner and multi-instance tests, key availability/protection and disk-full coverage. SQLite DB, WAL and SHM protection, integrity and key lifecycle must be verified on device.

This protocol is a design constraint, not an implementation. Existing APIs have not been changed to enforce it and the prototype must remain held.
