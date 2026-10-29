# Durable job media implementation plan

> Use superpowers:subagent-driven-development for the coherent media task and independent review. Continue under existing implementation/upload authorization.

**Goal:** Keep job photos and scans safe offline and scoped to their verified owner.
**Architecture:** An injectable main-actor PendingMediaStore owns protected disk units, identity binding, serialized drains and observable queue state. Existing MediaTransfer validates canonical stored replies. App binds the store from verified identity; MediaView uses its scoped queue and existing Paper components.
**Tech Stack:** Swift6, SwiftUI, Foundation protected files, existing media API, XCTest.
**Spec:** ../specs/2026-10-29-durable-job-media.md

## Global constraints

- Preserve all existing capture/import/preview/tag/retry controls and2560px/8MiB bounds.
- No new backend, provider, bank/check evidence path, SDK upgrade or Tap gate change.
- Never infer legacy file ownership; preserve those bytes without automatic upload.
- Only exact stored confirmation can remove local media.
- Important focused native tests; no repetitive full CI.

## Review focus

- Workspace changes between queued files must stop the old drain before another registration.
- Confirmed reply with wrong ID/job/organization/content or pending state must preserve bytes.
- File protection/access failure must not silently delete pending work or show false saved state.
- Duplicate retry/reconnect calls must not race the same item or replace its operation identity.
- Sign-out warning and cleanup must agree about every scope and legacy item being deleted.

### Task 1: Durable scoped job media

**Files:** Create Thorbis/Sources/PendingMediaStore.swift and ThorbisTests/PendingMediaStoreTests.swift. Modify MediaView.swift, MediaTransfer.swift, App.swift, API.swift, SettingsView.swift, Screens.swift, LoginView.swift and focused MediaTransferTests/FieldOutboxTests or dedicated sign-out tests. A focused legacy-recovery helper/view may be extracted if needed; preserve existing Paper components/native confirmations. Update PaperPreview fixtures only if required for isolated native testing; no live network fallback. Keep FieldOutbox's own queue semantics unchanged.

**Interfaces:** Introduce PendingMediaScope(actorID, organizationID, origin), PendingMedia (stable id/job/filename/tags/capturedAt/kind/MIME) and PendingMediaStore with injectable directory, shared production instance, bind/unbind, throwing save/read, scoped metadata listing, observable queue/errors, total pending loss count and serialized upload drain. APIClient exposes a normalized identity from its existing origin validator rather than duplicating URL trust rules. Drain accepts API, optional job filter and a current canUpload closure, captures binding/generation, and rechecks before each item/cleanup. MediaTransfer.upload gains original capturedAt and optional expected organization arguments while preserving current callers. Sign-out text composes outbox's existing cross-workspace count with all pending media/legacy counts.

- [ ] **Step 1: Write and run meaningful failing regressions.** JPEG/PDF relaunch retains bytes/ID/job/MIME/date; A/B actor/org/origin isolation; workspace switch mid-first transfer prevents second registration; bad/missing bytes remain with error; failed payload/metadata commit publishes no saved item; wrong/pending confirm preserves work; concurrent drains use one operation; stored confirmation alone deletes; sign-out counts all scopes/legacy; file protection/backup exclusion; scan waiting presentation survives navigation. Use production components and real temporary filesystem, URLProtocolFixture only at network boundary.
- [ ] **Step 2: Implement store and transfer validation.** Use protected staging-unit rename, scope digest paths, no bulk Data in published state, explicit errors and stable operation/capture identity. Preserve legacy files. Fail closed on unknown scope/capability/generation; preserve queue on every ambiguous result. Reuse existing API registration/PUT/confirm and session authority.
- [ ] **Step 3: Integrate App/media/sign-out.** Persist scans/JPEGs before send, display scoped waiting documents/photos/errors with current Paper rows, retain imports/previews/tags/retry. Bind on verified identity, unbind without erasing other workspaces, drain only current scope/capability. Include all pending media in existing destructive sign-out warning. No guessed legacy ownership or bank-check support.
- [ ] **Step 4: Qualify final source.** Run PendingMediaStoreTests, MediaTransferTests, affected outbox/sign-out tests and a native media queue journey on owned iPhone simulatorFA43B63E-98C9-4336-B1F7-A55E9D4B4B0A. Reuse /private/tmp/thorbis-ios-payment-derived/SourcePackages and /private/tmp/thorbis-job-book-derived; no redundant downloads. Expected: nonzero executed counts, zero failures, synthetic files cleaned. Record exact source hashes and actual logs.
- [ ] **Step 5: Report for independent review.** Do not commit/push/upload from implementer. Return changed files, actual tests/RED proof, assumptions/limits and report path. Coordinator reviews, resolves findings and commits after qualification; signed release/upload are subsequent steps.
