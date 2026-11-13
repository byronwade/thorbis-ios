# Held invoice idle-draft prototype

This branch does **not** provide invoice draft recovery in the app. Its UI tests and storage primitives are isolated experiments, not a release candidate.

The synthetic same-actor replacement baseline reproduced loss of an unsaved quantity: the test entered `2`, triggered session restoration, and the later editor hierarchy showed a newly created line at `1`. The workspace-replacement baseline reached its trigger but its old snapshot did not prove which workspace was active. A subsequent DEBUG-only marker was added to require that proof; that test has not yet been rerun.

The held sequence gate reserves a sequence before encryption, binds one sealed payload to it, and accepts an acknowledgment only for the same scope, owner, sequence and ciphertext digest. A changed rebind fails rather than appearing durable. The serial writer records immutable ciphertext through the SQLite prototype; a storage error holds the writer. `durable` means only that the store reported a commit for the latest bound bytes, not that the device survived power loss or that the caller has authority.

The cipher uses AES-GCM and authenticates origin, organization, invoice, actor, customer, job, owner and sequence. The separate Keychain key primitive is insert-only and does not silently recreate a key. Host probes use synthetic data and doubles; they do not establish actual iOS file protection, Keychain entitlement or process-death behavior.

Before any UI or financial submission uses these primitives:

- Bind scope and authority to the current verified session and live invoice baseline, recheck after every suspension, and never expose old workspace text to a new scope.
- Atomically coordinate journal initialization with key creation; distinguish locked/unavailable from missing keys and never create a replacement for existing ciphertext. Protect and qualify SQLite, WAL and SHM files on actual devices.
- Retain the latest raw edit outside a retiring view until its exact encrypted snapshot is durably acknowledged; surface failure without silently discarding work. Resume only after verifying the original actor, workspace, job, customer, invoice and current revision.
- Serialize all actors and processes for an invoice, handle stale handles and ambiguous local commits, and add kill/relaunch, disk-full and two-scene tests. Preserve all unresolved snapshots and define bounded retention and explicit cleanup.
- Existing direct `/v2/invoices/{id}/lines` attempts have no command receipt. A fresh GET cannot settle an unknown direct request. Do not automatically retry or clear it; keyed submission and reconciliation need a separate qualified protocol.

The relevant host probes are `scripts/tests/invoice_serial_capture_probe.swift`, `invoice_draft_cipher_probe.swift`, `invoice_draft_key_probe.swift` and `invoice_draft_process_probe.swift`. Their Swift 6 host runs passed with synthetic data. The process probe kills its own child after an acknowledged commit and reopens the encrypted snapshot; it does not test a kill during commit or loss of device power. System Keychain and app behavior were not tested by these probes.
