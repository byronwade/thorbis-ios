# Saved Work Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a technician inspect and recover current-workspace queued commands,
photos and scanned/imported PDFs from one truthful native review.

**Architecture:** A pure metadata projection combines the two existing bound stores;
OfflineBanner presents one scope-bound sheet. The sheet reuses existing queue
methods and `PaperRoute.job` inside its own NavigationStack. A narrow command-drain
authority callback/binding guard and read-only media-owner accessor close the
review’s trust boundaries; no queue or server authority is replaced.

**Tech Stack:** Swift6, SwiftUI, existing ObservableObject environment services,
Foundation, XCTest/XCUITest; iOS18 minimum, pinned dependencies unchanged.

**Spec:** `../specs/2026-10-29-saved-work-review-design.md`

## Global Constraints

- One current verified actor/workspace/API-context review; no other-scope or legacy rows.
- No extra storage, queue, backend, SDK, provider exposure or new permission prompt.
- Preserve command IDs, retry/dismiss/dependency holds and existing media identity/transfer guards.
- Media bytes/preview/tags/file retry remain in the existing job Photos flow.
- Existing Paper73/74 and shared components; 20pt gutter, Dynamic Type, minimum44pt staff targets.
- No all-synced claim while either queue/sender/warning remains; no inferred per-command sending ID.
- User authorized normal implementation/release workflow; do not repeat permission menus.
- Important affected checks and native journeys, not repetitive full CI; never hide known failures.
- Preserve root's in-flight media-cleanup changes and build77's immutable release evidence.
- Do not edit PendingMediaStore until the coordinator’s frozen cleanup fix is committed.
- Existing SessionController revalidation/expiry publication remains the only authority clock; no new timer.

## Review Focus

- A job missing from the loaded list still opens by the existing ID route; no stranded requestedJobID.
- Workspace/origin/expiry/revocation, A→B→A or ready Session A/media B cannot reveal rows or advance stale commands/actions.
- Command/media UUID collision or simultaneous sends cannot collapse rows or produce a false zero count.
- A metadata/storage warning must not become global success or leak another scope's filenames/counts.
- A nested job banner returns to one review owner; Back/Done/focus, large type and iPad resizing retain every action/reason.

---

### Task 1: Unified saved-work review and existing-job recovery

**Files:**
- Create `Thorbis/Sources/SavedWorkReviewState.swift`: pure scoped metadata projection and presentation-scope token.
- Create `Thorbis/Sources/SavedWorkReviewView.swift`: native review, group/row composition and existing-store action calls.
- Modify `Thorbis/Sources/PaperComponents.swift:407-505`: OfflineBanner combines counts and presents the new sheet;
  migrate existing refused-command row behavior from OutboxReviewSheet instead of retaining a competing surface.
- Modify `Thorbis/Sources/FieldOutbox.swift`: optional live canSend callback and private opaque binding/generation guards throughout delivery; no persistence-format change.
- Modify `Thorbis/Sources/PendingMediaStore.swift` only after the root cleanup commit: read-only `captureContext(matching:)`, no change to file/transfer/recovery semantics.
- Modify `Thorbis/Sources/PaperPreview.swift` only for DEBUG read-only fixture states required by native tests.
- Modify `Thorbis/Sources/ReleaseNotes.swift`: unique new top entry or fold into the next unshipped entry per AGENTS.
- Create `ThorbisTests/SavedWorkReviewTests.swift`: real-store/projection/authority/action regression coverage.
- Modify `ThorbisTests/FieldOutboxTests.swift`: gated command/REST/fallback/conflict-read revocation and binding-race regressions.
- Modify `ThorbisTests/PendingMediaStoreTests.swift`: exact matching-owner accessor and no-mutation tests.
- Create `ThorbisUITests/SavedWorkReviewUITests.swift`: nonzero native end-to-end scope/navigation/adaptation journeys.
- Record execution/evidence in `docs/superpowers/execution/2026-10-29-saved-work-review.md` and a separate evidence folder.
- Do not change queue persistence/schema, App resync scheduling, PaperRoute/JobDetailView or backend contracts for this task.

**Interfaces:**

- Consume `FieldOutbox.entries`, `pending`, `needsReview`, `syncing`, `retry(_:)`, `dismiss(_:)`,
  the existing drain and `OutboxEntry` stable IDs/actor/organization/job/state/date/summary.
- Extend the drain to `func drain(api: APIClient, useCommandEndpoint: Bool, canSend: @MainActor () -> Bool = { true }) async`.
  The default preserves legacy call sites. Capture private opaque binding UUID, actor/org identity, normalized origin
  and API requestGeneration at entry; its predicate also requires `!Task.isCancelled`. Rotate the binding on effective identity change/nil/clearAll; A→B→A must not
  regain an old token. Check the same current-authority predicate before all batches/REST/fallback/conflict GETs
  and after every await before local state, held/rejected/restOnly/lastSyncSent updates or persistence.
  A failed guard retires delivery with existing IDs/holds/files intact; do not invent a new rejected state.
- Add `func captureContext(matching requested: PendingMediaScope) -> CaptureContext?` to PendingMediaStore.
  Normalize the requested origin with APIClient.normalizedOrigin and match actor/org/origin against private bound
  scope; return the existing opaque context only on an exact match. This accessor does not bind, reload or mutate.
- Consume `PendingMediaStore.items`, `errors`, `unverifiedIDs`, `uploadingID`, `storageWarning`,
  `captureContext` and `drain(api:jobID:canUpload:storageSession:)`. Do not use global totalPendingCount/legacyCount as current counts.
- Produce `SavedWorkScope: Identifiable, Equatable`, capturing a presentation UUID, actorID,
  organizationID, normalizedOrigin, sessionGeneration, requestGeneration and opaque mediaContext.
  `@MainActor static func capture(session: SessionController, api: APIClient, media: PendingMediaStore) -> SavedWorkScope?`
  refuses non-ready, expired or missing job.view authority; `@MainActor func isCurrent(session:api:media:) -> Bool`
  checks every captured binding and current access, using the new matching-context accessor at capture and comparison.
  A non-nil context alone is insufficient. No stored service references or new disk state.
- Produce `SavedWorkSnapshot.make(scope: SavedWorkScope, entries: [OutboxEntry], media: [PendingMedia],
  mediaErrors: [String: String], unverifiedMediaIDs: Set<String>, uploadingMediaID: String?,
  commandsSyncing: Bool, jobs: [Job], listingWarning: String?) -> SavedWorkSnapshot`.
  The caller must validate scope/media context before projection. Filter command identity again.
  Snapshot carries typed row IDs, ordered job groups, total/attention/pending counts, isSending and optional generic listing-warning state.
  It does not carry full note bodies or Data. Treat listingWarning as presence only; render a fixed generic
  incomplete-listing message, never forward arbitrary global warning text. Media status priority is uploading → error → unverified → waiting.
- Produce `SavedWorkReviewView(scope: SavedWorkScope)`, injecting APIClient, SessionController,
  Store, FieldOutbox and PendingMediaStore through existing environment patterns. It owns the
  NavigationStack with local `@State private var path = NavigationPath()`, Done, native discard confirmation
  and view-owned Task cancellation. The path holds existing typed PaperRoute values and leaves existing
  paperDestinations capable of handling its other registered destination types.
- Inside that sheet install `.paperDestinations()` and use `NavigationLink(value: PaperRoute.job(group.jobID))`.
  No `Store.requestedJobID`, URL dispatch or new global router. Job Photos remains the existing tab after opening.
- Add sheet-local `EnvironmentValues.savedWorkReviewReturnToRoot: (@MainActor () -> Void)?`, nil outside a review.
  The sheet injects a closure that validates its scope, then resets its own path to an empty NavigationPath; if stale,
  dismiss instead. OfflineBanner checks this owner first and invokes it rather than creating a nested sheet.
  Nested job views inherit it through environment. This is not a global navigation service.
- Private view actions are `retryCommand(_ id: String) async`, `discardCommand(_ id: String)` and `sync() async`.
  They re-fetch current entry, check scope/capability at commit and after awaits, and call existing stores only.
  Every review-triggered FieldOutbox.drain supplies live `scope.isCurrent(session:api:media:) &&
  session.can("job.edit", feature: "jobs")` as canSend; media retains its corresponding live canUpload closure.
  Dismiss is local-only and requires the still-current rejected entry; retry cannot bypass held dependencies.

- [ ] **Step 1: Inspect the exact current base and matching Paper source.** Confirm no competing native Xcode process;
  preserve root changes, use the inspected Paper73/74 JSX and read needed computed styles, and verify the existing interfaces above still match.
  Read golden rules/process and nearest AGENTS. Confirm the coordinator’s cleanup fix is committed before any
  source/test edit. Record any genuinely changed contract before coding; no fabricated fields.

- [ ] **Step 2: Write meaningful failing state/action regressions.** Pin these exact behaviors with literal fixtures:
  `mixedCommandsAndMediaCountOnceAndKeepTypedIDs` (same UUID in both stores yields two rows),
  `groupOrderUsesOldestWorkAndStableTieBreak`, `foreignActorOrWorkspaceCommandsAreAbsent`,
  `mediaSendingDoesNotRelabelEveryCommand`, `emptyRowsWhileSenderActiveNeverClaimsSynced`,
  `refusedHeldAndUnverifiedStayDistinct`,
  `emptyMetadataWithListingWarningNeverClaimsSynced` (foreign filename sentinel must never enter output), `scopeFlipAndReturnCannotReuseActionToken`,
  `expiredOrChangedOriginCannotRetryDiscardOrSync`, `readySessionAWithMediaBRefusesRowsAndActions`,
  and `discardConfirmationRefetchesCurrentRejectedEntry`.
  Use real temporary store files and real SessionController/API fixtures at network boundaries; no test-only production setters.
  Assert retained bytes and original IDs where an action is refused, not merely mock invocation counts.
  In FieldOutboxTests add completed REDs for `revocationDuringCommandBatchStopsLaterDelivery`,
  `revocationDuringRESTStopsNextCommand`, `bindingFlipAndReturnCannotCommitOldResponse`,
  `revocationBeforeRESTFallbackPreventsRequest`, `canceledReviewDoesNotRejectOrRemovePendingCommands`
  and `revocationDuringConflictGETPreventsReconciliation`.
  Gate at the actual network boundary; assert requests stop and persisted command IDs/states/holds remain exact.
  In PendingMediaStoreTests add `matchingContextRejectsAnotherActorOrgOrOriginWithoutMutation` and
  `normalizedMatchingContextReturnsCurrentOpaqueBinding`; no getter may change queue state.

- [ ] **Step 3: Run those new tests to a completed RED before implementation.** Use the owned iPhone simulator
  `FA43B63E-98C9-4336-B1F7-A55E9D4B4B0A`, existing derived/cache paths and a unique outside-derived xcresult.
  Regenerate Xcode project only when adding the new files requires it, preserving pinned Package.resolved.
  Command shape is below; require executed cases >0 and expected behavioral failures, not selector/compile errors alone.

```sh
xcodebuild -project Thorbis.xcodeproj -scheme Thorbis \
  -destination 'platform=iOS Simulator,id=FA43B63E-98C9-4336-B1F7-A55E9D4B4B0A' \
  -derivedDataPath /private/tmp/thorbis-job-book-derived \
  -clonedSourcePackagesDirPath /private/tmp/thorbis-ios-payment-derived/SourcePackages \
  -disableAutomaticPackageResolution -parallel-testing-enabled NO \
  -resultBundlePath /private/tmp/<unique-saved-work-run>.xcresult \
  -only-testing:ThorbisTests/SavedWorkReviewTests CODE_SIGNING_ALLOWED=NO test
```

- [ ] **Step 4: Implement the narrow store guards and scope/projection.** First add the read-only matching accessor
  after the frozen cleanup commit, and the existing outbox’s opaque binding/live callback checks throughout both
  command and REST paths, fallback and conflict recovery. Preserve legacy call-site behavior and queue schema.
  Then use the exact projection interfaces above, with no filesystem/network read
  during row rendering. Preserve command chronological/dependency semantics. Snapshot carries no derived success promise:
  zero listed items plus warning is incomplete, and sender activity still prevents all-clear. Do not infer original
  legacy ownership or enumerate a global file count. Unit GREEN must use nonzero cases and prove refused actions keep work.

- [ ] **Step 5: Implement the native sheet and banner integration.** Keep existing banner positions, cache-age text and
  one sheet item state. Add current-workspace combined summary with attention/sending/waiting priority. Move the old
  refused-command presentation/actions into the new sheet; confirm no remaining callers before removing the old struct.
  Use existing Paper group/list grammar, explicit Open job, stable Sync now, native confirmation/Done/Back.
  Revalidate before Sync now; stop if offline/stale or known edit capability is absent. Drain commands using the current
  offline_sync feature and live canSend scope/capability closure, recheck, then media with its live closure. A fresh rejected command Retry requeues
  through existing semantics; offline does not falsely claim it sent. Discard confirmation must re-fetch and scope-check.
  Immediate invalid scope renders no rows and dismisses/cancels the whole sheet including a pushed job/confirmation.
  Use published SessionController deadline invalidation; ordinary revalidate preserves generation, and no second
  expiry timer is permitted. Inject the review-root owner closure so the pushed job’s banner pops this path instead
  of presenting another review. Outside this owner, the existing one-sheet presentation works normally.

- [ ] **Step 6: Add native regressions before declaring UI success.** Define and execute
  `testMixedSavedWorkOpensOfflineAndSurvivesRelaunch`, `testOnlineBannerStillListsQueuedMedia`,
  `testOpenUncachedJobUsesExistingRouteAndBackReturnsToReview`, `testDiscardCancelAndConfirmPreserveOtherWork`,
  `testWorkspaceFlipRetiresOpenReviewAndConfirmation`, `testNestedJobBannerReturnsToOneReviewRoot`,
  `testAuthorityDeadlineRetiresOpenReview` and `testLargeTextKeepsActionsReachable`.
  DEBUG fixtures remain read-only/no live fallback; relaunch must omit reseeding to prove retention.
  Assert literal job/command/media IDs and original dates, both queue counts, exact destination, one review-sheet
  owner, Back/Done/focus and no foreign rows. The deadline fixture must exercise existing published expiry,
  not a test-only review timer. Reopening the review after A→B→A creates a fresh scope/token.
  If a selected class executes zero tests, fix selection and rerun; never count it as green.

- [ ] **Step 7: Qualify final affected behavior and presentation.** Run SavedWorkReviewTests and relevant existing
  FieldOutboxTests, PendingMediaStoreTests, MediaTransferTests, LegacyMediaRecoveryTests and WhatsNewTests, plus the
  actual native class on iPhone. Run adaptation journeys on owned iPad mini `12B515ED-7C0D-4C00-B571-B7561401FDC0`
  (iOS18.2), narrow/wide layout as available, accessibility text and dark mode. Inspect screenshots against Paper73/74.
  Record nonzero counts/pass/fail/skip, exact source SHA, cleanup of synthetic files, and explicit physical VoiceOver/
  camera/provider limitations. Reuse existing cache; do not reset shared simulators or rerun unrelated full CI.

- [ ] **Step 8: Independent review and scoped integration.** Report feature inventory and exact evidence; obtain the
  independent design/builder check before implementation and code review after qualification. Fix material findings
  with RED/GREEN proof. Coordinator commits only task files after review using `[skip ci]` per user preference,
  creates/attaches the appropriate draft PR, then batches a useful next signed TestFlight release. No merge/deployment
  or whole-epic completion follows merely from this task passing. Preserve prior build77 evidence unchanged.

## Plan self-review

The single coherent task owns the projection, presentation and existing-store action bridge;
none is a separately shippable alternate queue. The scoped store changes are authority guards/access only;
persistence and App scheduling remain unchanged. Initial builder findings (two Important, one Minor)
are addressed by explicit callback/binding, owner-matching and sheet-return interfaces/tests above.
Every spec acceptance class maps to Steps2/6/7.
Exact current route/interfaces are named, ordinary Back/Dismiss are covered, and no global
router/storage migration is required. Builder choices are scoped in the spec. No product
question requires repeated user approval; independent design review is the next gate.
