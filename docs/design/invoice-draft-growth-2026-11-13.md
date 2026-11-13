# Held invoice draft storage growth

The existing prototype keeps every encrypted capture in the `snapshots` table. A host probe using 100 successive 8,192-byte synthetic edits observed 100 rows and 822,000 ciphertext bytes. This is SQLite row payload only, not an iOS device benchmark or a measurement of WAL, filesystem allocation, keychain, or encryption overhead.

Run from this worktree:

```sh
swiftc -swift-version 6 scripts/tests/invoice_draft_growth_probe.swift Thorbis/Sources/InvoiceTransactionFence.swift Thorbis/Sources/InvoiceDraftCipher.swift -lsqlite3 -o /private/tmp/thorbis-invoice-growth-probe
/private/tmp/thorbis-invoice-growth-probe
```

Do not prune captures just because a newer row exists: the process can die after SQLite commits and before the application receives its acknowledgment, and the existing prototype has no durable acknowledgment frontier. A safe retention design must prove which exact scope, owner, sequence and ciphertext the application observed committed, atomically fence concurrent writers and submission markers, and retain enough history for the previous acknowledged state when the latest commit is ambiguous. It must also handle ambiguous outcomes of the acknowledgment transaction itself, disk-full failures and two-scene competition. The prototype is not connected to the editor, and no retention or recovery feature is shipped by this finding.

The held editor recovery work also needs a cache-bypassing server read before any restore. `liveFieldInvoice` currently rejects a saved phone copy and app-level recent-read reuse, but unlike `liveFieldJob` it does not explicitly bypass URLSession's protocol cache. A separate release-based branch, `codex/financial-live-read-1113`, contains unrun URLRequest regression tests; those tests do not establish current or corrected behavior until executed.
