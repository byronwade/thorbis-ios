# Offline Job Activity Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development or superpowers:executing-plans. Checkboxes track work; nothing in this plan is implemented or deployed by this document.

**Goal:** Keep job activity and note composition usable after a cold offline launch, with selectable activity, bounded access, durable notes and honest synchronization states.

**Architecture:** The server issues a job-specific offline activity snapshot only after its current resource-specific view check, with a separate note decision. iOS stores that snapshot and its associated job and notes as one protected actor/workspace/job-bound unit. Queued notes keep a durable stable command identity; reconnect uses current server authorization and receipt arbitration. A disconnected device cannot learn about a remote revocation until it reconnects; access is bounded by the snapshot expiry, not instant revocation.

**Tech Stack:** SwiftUI, Swift concurrency and protected Foundation storage; Thorbis TypeScript API, jobs and permissions domains, command ledger, Vitest and XCTest.

**Spec:** `docs/design/ios-golden-rules.md`, `docs/design/ios-implementation-process.md`, and `docs/superpowers/execution/2026-10-29-activity-selection.md`; Linear BYR-137, BYR-173 and BYR-935 describe related offline authorization and note-queue intentions. Those issues do not establish an iOS endpoint or job-specific grant.

## Global constraints

- No new online-only requirement for previously supported job history or note work; do not release the activity branch until the offline path is qualified.
- Maximum offline access is 12 hours from server issuance, further capped by the underlying authority expiry. A shorter server limit is allowed; do not extend a snapshot by refreshing local storage.
- Read and note permissions are independent, exact actor/organization/job decisions. Client checks determine presentation, never server write authority.
- Retain pending notes on connectivity, authorization, storage and replay errors; show pending, confirmed and rejected truthfully. Avoid duplicate server notes after an uncertain response.
- No note bodies, grants or credentials in logs. Respect existing sign-out warnings and retention policy. No new paid providers or payment behavior.

## Review focus

- Assignment changes without a policy-version change: server evaluates the current resource on first application and every replay; offline data stays bounded by expiry.
- Clock manipulation, reboot or unavailable trustworthy time: do not make an expired snapshot valid again; fail closed when elapsed time cannot be established safely.
- A read grant without a note grant: show authorized history without a composer; a denied/missing read never presents history as empty.
- Process interruption or disk/Keychain failures: never claim a note is saved unless its durable write succeeded; preserve existing pending data on migration and recovery.
- A lost upload response, changed payload or changed job under the same ID: retry the same command identity, prevent duplicate insert or disclosure, and surface unverified legacy receipts for review.

## Existing seams and contract decisions

- `domains/jobs/src/queries.ts` (`getJob`, `jobResource`, `listJobNotes`) authorizes `job.view` on the job resource; `domains/jobs/src/commands.ts` (`addJobNote`) checks `job.note` after locking the current job. `assignJob` can change assignee independently of policy-version changes.
- `packages/permissions/src/entitlements.ts` already defines a 12-hour default and offline grant layers; `packages/permissions/src/local-engine.ts` evaluates location, team and assigned scope. Neither the generic snapshot nor the five-minute PowerSync token is proof of a particular job's current access. Avoid duplicating the full policy evaluator in Swift.
- Existing REST paths are `GET /v1/jobs/:id`, `GET/POST /v1/jobs/:id/notes`, and `POST /v1/commands`. The following new route and data types are **proposed**, not available today.
- Proposed `GET /v1/jobs/:id/offline-activity` returns `{ version: 1, actorId, organizationId, jobId, policyVersion, issuedAt, expiresAt, mayAddNote, job, notes }`. `job` and each note must match the same organization/job; `mayAddNote` represents a separate current `job.note` decision. No response is issued without `job.view`. Treat this single response as a snapshot, not a transferable credential or authorization to mutate the server. Define the exact wire schema in the API contract and regenerate/update the API client and OpenAPI before use.
- The server transaction must evaluate both decisions against the same current job and load the associated data under a coherent authority/transaction boundary. If the permission engine cannot represent or reliably return a separate note decision, omit the grant and do not offer the composer. Cap `expiresAt` by the existing entitlement and session/authority boundaries.
- `Thorbis/Sources/OfflineSupport.swift` currently has a job-ID-only `JobDetailCache`; it is not authority. `PaperJobDetailView.swift` currently requires fresh `fieldJob` and `fieldNotes` for Activity. `FieldOutbox.swift` swallows persistence errors and uses a non-idempotent REST note fallback; these must not be treated as qualified offline behavior.

## Task 1: Issue a bounded, job-specific activity snapshot

**Files:** Modify backend `domains/jobs/src/queries.ts`, `services/api/src/app.ts`, API schema/OpenAPI and client declarations; add focused coverage in `domains/jobs/test/jobs.test.ts` and a new `services/api/test/offline-job-activity.test.ts`.

**Interface:** Add `getOfflineJobActivity(ctx, deps, jobId)` returning the proposed version-1 response above. Keep creation inside the authenticated API transaction; use the server clock and the existing permissions engine's exact resource checks.

- [ ] Add failing tests for actor and tenant isolation, nonexistent/denied jobs, view allowed plus note denied, view and note allowed, assignment/team/location-specific decisions, a policy change during acquisition, and consistent job/note identity.
- [ ] Add boundary tests proving expiry equals no more than `issuedAt + 12h` and is capped by earlier authority expiry, with invalid/expired authority rejected. A decision failure must never produce a positive note grant.
- [ ] Run `pnpm --filter @thorbis/jobs exec vitest run test/jobs.test.ts` and `pnpm --filter @thorbis/service-api exec vitest run --config vitest.config.ts test/offline-job-activity.test.ts`; confirm the new cases fail for the missing contract.
- [ ] Implement the domain query, coherent transaction, endpoint and schema; expose only job and notes needed by this activity flow. Do not broaden existing endpoint authorization or present an empty list for denial.
- [ ] Re-run the two commands and package typechecks; require all focused tests and typechecks to pass. Add API contract tests for unsupported version and response identity.

## Task 2: Make note receipts safe under replay and policy change

**Files:** Modify backend `services/api/src/commands.ts` and `domains/jobs/src/commands.ts`; add `services/api/test/job-note-replay.test.ts` and, if needed, receipt persistence/migration under the existing command ledger owner. Review `POST /v1/jobs/:id/notes` separately before claiming any REST idempotency.

**Interface:** `jobs.addNote` keeps its original `commandId`; bind a canonical fingerprint of job ID and note body to its durable receipt. A duplicate response must first validate the exact payload and reauthorize `job.note` for the current job; the stored result must match actor, organization and job. Preserve a supported path for preexisting receipts only if it can establish those facts; otherwise return a recoverable, non-disclosing refusal.

- [ ] Add failing tests for lost response followed by exact retry (one note), concurrent identical uploads, same ID with different body/job/actor, changed assignment without policy change, revoked permission, policy superseded, and legacy receipt missing a verifiable fingerprint. Verify no old note body is disclosed after access loss.
- [ ] Run `pnpm --filter @thorbis/service-api exec vitest run --config vitest.config.ts test/job-note-replay.test.ts`; confirm the new tests expose current generic receipt behavior.
- [ ] Implement fingerprint binding and current-resource replay checks transactionally with the existing ledger. For superseded policy, define an exact same-command reauthorization path that cannot skip receipt arbitration. Do not retry the same uncertain write through a REST endpoint without a matching server-owned idempotency contract.
- [ ] Re-run focused tests, including a database-backed concurrent/rollback test using the existing integration test configuration. Require one stored note and one accepted receipt for every uncertain-retry case.

## Task 3: Persist and validate offline snapshots on iOS

**Files:** Create `Thorbis/Sources/OfflineJobActivityStore.swift`; modify `Thorbis/Sources/FieldAPI.swift`, `Thorbis/Sources/OfflineSupport.swift`, and `Thorbis/Sources/SessionController.swift` as needed. Add `ThorbisTests/OfflineJobActivityStoreTests.swift` and extend `ThorbisTests/FieldAPITests.swift`.

**Interface:** Decode the server's version-1 response into `OfflineJobActivitySnapshot`; `OfflineJobActivityStore.save(snapshot, session:) throws` atomically stores the bound snapshot, and `load(actorID:organizationID:jobID:session:clock:)` returns usable data or a typed unavailable reason. Key storage by full identity using collision-free canonical encoding, not filename filtering alone. Treat legacy job-only cache as untrusted for activity until a fresh authorized snapshot replaces it; do not destroy pending outbox data.

- [ ] Add failing tests for exact identity matching, foreign note/job IDs, unsupported version, bad/missing expiry, both independent grants, atomic write interruption, corrupt storage, protected-file failure, logout/workspace switches, policy changes, session expiration and stale async completion.
- [ ] Define and test a clock policy: track server-issued time plus monotonic elapsed time on a known boot, detect local clock rollback, and fail closed after reboot if a trustworthy expiry bound cannot be established. Never silently extend expiry; document the resulting availability limitation until a verified time strategy exists.
- [ ] Run `xcodebuild test -project Thorbis.xcodeproj -scheme Thorbis -destination 'platform=iOS Simulator,id=B80AE818-3E9D-4248-8221-9B178FAAC268' -only-testing:ThorbisTests/OfflineJobActivityStoreTests -only-testing:ThorbisTests/FieldAPITests`; require failure for the new tests before implementation.
- [ ] Implement authenticated fetching and one atomic protected snapshot file, with identity/session/authority checks before publication. Invalidate access on known authority changes, sign-out or expiry; preserve pending work in its separate owner-bound queue.
- [ ] Re-run the focused tests and require a pass, including a cold process restart with an unexpired valid snapshot and a refused write with no false saved state.

## Task 4: Restore durable offline notes and selectable Activity

**Files:** Modify `Thorbis/Sources/FieldOutbox.swift`, `Thorbis/Sources/PaperJobDetailView.swift`, and `Thorbis/Sources/ActivityRecordViews.swift`; extend `ThorbisTests/FieldOutboxTests.swift`, `ThorbisTests/ActivityDestinationTests.swift` and add the relevant native journey test under `ThorbisUITests`.

**Interface:** Replace fire-and-forget queue persistence with `enqueue(...) throws -> OutboxEntry`, returning success only after an atomic durable write. `loadVerifiedActivity()` consumes Task 1's snapshot and Task 3's store; its view shows snapshot history with a stale/offline label, and enables note composition only with its separate valid note grant. Always retry the same `commandId` through Task 2's qualified server path; without it, hold uncertain notes for review rather than resubmit them via unqualified REST.

- [ ] Add failing tests for offline first open, relaunch, selected item detail, view-only grant, offline note persistence and restart, failed disk write, queue identity change, note permission expiry, reconnect after reassignment, an upload that commits then loses its response, and denied/held recovery. Confirm a long note remains selectable and readable at large text.
- [ ] Run targeted `xcodebuild test` for `ThorbisTests/FieldOutboxTests`, `ThorbisTests/ActivityDestinationTests`, the new store tests and the named UI journey; verify new regressions fail.
- [ ] Implement the Activity restore and queue changes, preserving current navigation mappings, already-saved queue entries and user-visible error/retry states. Disable only the unsafe retry, not access to review or copy the pending note.
- [ ] Re-run the targeted tests and record exact results. Exercise actual simulator cold start offline and reconnect; inspect VoiceOver, large Dynamic Type and phone/iPad presentation. A test failure or unavailable device remains a recorded gap, not a pass.

## Task 5: Integrate and release safely

**Files:** Update `docs/superpowers/execution/2026-10-29-activity-selection.md` and `Thorbis/Sources/ReleaseNotes.swift`; create a build-specific release record after qualification.

- [ ] Independently review the complete backend and iOS changes for identity, note receipt privacy, revocation/expiry, cache migration, accessibility and feature retention; fix material findings with regression tests.
- [ ] Verify backend deployment, endpoint availability, command feature gating, ledger migration and compatibility with both older and new iOS builds before enabling the mobile path. A build alone does not deploy the API. Do not roll out an unsafe fallback when the backend capability is absent.
- [ ] Run the relevant native, backend, offline-restart and replay suites on the exact release source, plus release boundary audit; record pass/fail and untested conditions. Verify no unfinished activity scaffold or known offline regression is included.
- [ ] Archive and upload a uniquely numbered build, then verify Apple processing and intended tester group availability. Record exact build, source revisions, test evidence and remaining limits. Do not claim full device accessibility, immediate offline revocation or complete activity coverage without evidence.
