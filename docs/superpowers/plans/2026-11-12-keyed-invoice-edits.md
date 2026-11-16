# Keyed Invoice Edit Recovery Implementation Plan

> **For agentic workers:** Execute with superpowers:executing-plans and independent review. This plan is held; it does not authorize enabling the prototype or releasing it.

**Goal:** Preserve technician invoice drafts and make newly submitted line edits recoverable after a lost response through the canonical command receipt.

**Architecture:** Persist an immutable, complete command and raw draft before sending. Serialize editor ownership and submission state by trusted origin, organization, and invoice in one transactional durable store; all participants must use that store. Reconcile only through the same command identity and current authorized server responses, retaining ambiguous attempts and work until their outcome is proven.

**Tech Stack:** Swift, protected transactional local storage, Thorbis `/v1/commands`, authenticated server transactions, XCTest and Postgres integration tests.

**Spec:** This document and `docs/design/invoice-draft-recovery-foundation.md`; server contract is in `packages/sync/src/envelope.ts`, `services/api/src/commands.ts`, `domains/invoicing/src/commands.ts` in the Thorbis TanStack repository.

## Global Constraints

- Leave current production UI and unkeyed direct route unchanged until qualified; migrate only future submissions. A preexisting uncertain direct request has no command receipt and remains held for explicit reconciliation.
- No mutation while authority, durable recording, identity, scope, or server outcome is uncertain. Keep raw user-entered strings, original IDs, all line sources and override reasons.
- Scope fence by trusted normalized API origin, organization and invoice; separately require same actor, current authorization, and matching job/customer before showing a draft. Do not derive origin from an editable URL.
- Don't silently overwrite or expire drafts/uncertain attempts. Never send during restoration, and never reuse a command ID for different intent.

## Contract and risks

`POST /v1/commands` accepts `{commands:[envelope]}`; each envelope has UUID `commandId`, `deviceId`, `actorId`, `organizationId`, positive current `policyVersion`, `command: "invoices.updateLines"`, timestamp `clientCreatedAt`, and `payload` containing `invoiceId`, `expectedLinesRevision`, `lines`, optional `priceBookOverrideReason`. Limit 50 commands and 65,536 UTF-8 bytes per parsed envelope. Use one command per batch. The server checks actor/org claims and policy, locks the invoice, requires edit authorization, checks revision, draft status, ledger and concession rules, then increments revision and generates new line IDs. It records the command and domain mutation in the same transaction. Exact same-actor replay checks an invoicing-owned canonical parsed-intent SHA-256; it reauthorizes current resource and returns `duplicate` with the **current** invoice, which may have since changed. Receipt mismatch, old receipts without fingerprints, authorization and policy can produce rejections; they do not generally prove a prior unknown attempt did not commit.

A retry is an application attempt if the first command never committed, not a read-only status lookup. Explain this and require the technician's deliberate choice before retrying. Neither fresh invoice state nor a rejected retry is by itself proof that an earlier request is no longer in flight. The direct route has no command ID and cannot be converted into a keyed replay. A server-side status/reconciliation protocol may be required for safe resolution when an authorized duplicate cannot be obtained.

## Review Focus

- Process termination during each durability boundary and unknown storage outcomes: retain both raw draft and identity; never send on failed or ambiguous commit.
- Two scenes/processes racing same invoice, including different actors and reassigned jobs: only one mutation owner; no stale draft restore or send.
- Session, organization, permission, feature or policy change during await: no disclosure or mutation under an old authority handle.
- Server accepted edit followed by another edit, or accepted response lost: duplicate confirms command acceptance but current record may differ; never replace it with old draft.
- Oversized payload, long multiline descriptions, invalid decimals and every provenance variant: preserve exact inputs and explain rejection without truncation.

## Task 1: Prove local serialization and preservation

**Files:** `Thorbis/Sources/InvoiceDraftRecovery.swift`, a new transactional recovery store, and `scripts/tests/invoice_recovery_probe.swift` or equivalent dedicated host tests.

- [ ] Specify atomic transactions and process/extension participation, ownership token, generation checks, crash recovery and protected storage; reject operations if the protocol cannot be proved across every participant. The existing separate Keychain snapshot and marker keys are not an atomic fence.
- [ ] Test two independent store instances racing save, begin, restore, and authority change; hold an old handle across begin and verify it cannot disclose, edit, delete, or transmit. Test raw strings/provenance and simultaneous actor/job reassignment.
- [ ] Test crashes and failures before/after committing envelope and during ambiguous storage commit. No request occurs until the durable commit is positively confirmed; unresolved records survive restart and no cleanup removes them.
- [ ] Implement the transactional store, run host tests and independently review the full cross-process guarantee. Do not wire editor yet.

## Task 2: Keyed submission and reconciliation

**Files:** `Thorbis/Sources/FinancialActionAPI.swift`, a dedicated keyed submission service, `Thorbis/Sources/SessionController.swift`, new service tests; server integration tests under `services/api/test`.

- [ ] Test one immutable command ID and exact serialized intent across initial attempt, interruption, restart and deliberate replay. Simulate accepted response loss, first attempt not accepted, two concurrent exact retries, different payload reuse, revision conflicts and later server edits. Assert at most one committed mutation and that `duplicate` shows current server state without claiming it equals the original submission.
- [ ] Test actor, organization, server origin, live authorization and policy replacement before and during each suspension; revalidate at disclosure and send. Do not accept cached `canEdit` or a caller-supplied freshness Boolean as proof.
- [ ] Test 64 KiB limit, malformed outcomes, failures before and after commit, unavailable ledger, denied replay and legacy receipts; preserve draft and uncertain marker on every unproven outcome. Verify true concurrent Postgres transactions rather than only an in-memory fake.
- [ ] Construct a durable immutable envelope and transmit only that record; validate returned command ID, outcome and invoice scope. `applied` or authorized `duplicate` may prove acceptance; first establish and test exactly which other responses are terminal. Do not guess terminality from HTTP status or a fresh GET.
- [ ] Run focused Swift and server integration tests. Document server deploy/version, actual feature gates and conditions verified in the target environment. If backend cannot resolve a denied/unknown receipt, keep the attempt held and design a permission-safe read-only receipt/status API before enabling.

## Task 3: Editor integration after qualification

**Files:** `Thorbis/Sources/InvoiceLineEditorView.swift`, `Thorbis/Sources/InvoiceLineEditorState.swift`, targeted UI tests.

- [ ] Test leaving/reopening, session replacement, later edits and cancellation; raw unsaved input survives, unavailable authority reveals no prior scope, and unresolved submissions block new saves/issues. Include 500 lines, multiline content and error accessibility.
- [ ] Wire explicit save and issue through the qualified service. Show pending/retry states and a deliberate retry action; preserve drafts through conflict resolution. Issue only after confirmed line-edit acceptance and a fresh authorized invoice/revision check.
- [ ] Verify real Keychain/protected-store behavior, process termination, background/foreground and phone/iPad UX in signed builds; independently review and stage TestFlight only when the above checks pass.
