# Review saved field work in one place

Status: design for independent builder check; no runtime implementation yet.
Owner: the continuous Swift field-mobile goal, under Linear BYR-416.

## Person and outcome

A technician loses signal while adding a note, changing visit status or capturing
photos/scanned PDFs. From Schedule, Jobs or a job they can see what remains on
this phone, what is sending and what needs attention, then open the affected job
or retry without hunting through every job. This is one review of the existing
two queues, not another queue or a claim that every operation works offline.

The person sees only the currently verified account/workspace. Opening the review
must work offline while cached authority remains valid. Expired/revoked authority
must not expose old rows or permit new network work.

## Current evidence and authority

- `OfflineBanner` in `PaperComponents.swift:407` appears in Schedule, Jobs and job
  details. It counts only `FieldOutbox.pending`/`needsReview`; media is missing.
- `OutboxReviewSheet` at line453 lists refused/held commands, their reason/date and
  Retry/Dismiss. It says to open the job but provides no navigation control.
- `FieldOutbox.entries` is already bound by verified actor/organization. Its
  command IDs, dependency holds, retry/release, persistence and server command/REST
  fallback remain the command authority. `syncing` is queue-wide, not a per-row ID.
  The existing drain needs a narrow live-authority callback and opaque binding
  token so permission loss or A→B→A cannot advance stale work across awaits.
- `PendingMediaStore.items/errors/unverifiedIDs/uploadingID/captureContext` expose
  current scoped metadata. Add a read-only `captureContext(matching:)` check against
  the requested PendingMediaScope; external views must never inspect its private
  scope/binding fields or assume any non-nil context belongs to the session.
  Its protected bytes, guarded drain and confirmed removal remain media authority.
  `totalPendingCount` and `legacyCount` are not
  current-workspace presentation counts and must not be used here.
- `ThorbisApp.resync()` revalidates, drains both stores and refreshes; no second
  automatic sync scheduler is needed. User-triggered sync reuses the same public
  store methods and current session policy, never copies their queue logic.
- Exact existing navigation is `PaperRoute.job(String)` → `PaperRouteView` →
  `JobDetailView(jobId:)`, installed by `.paperDestinations()`. Detail verifies the
  canonical job ID/organization and already has its protected offline fallback.
  Do not use `Store.requestedJobID`: its handler requires a loaded list record and
  can strand an uncached job. No external URL is needed for this in-app action.

Linear source: [BYR-416](https://linear.app/byronwade/issue/BYR-416/field-mobile-harden-offline-operations-push-and-deep-links-with-two).
`linear_get_agent_context` was attempted and returned Tool not found; issue reads
succeeded. This design does not certify the whole offline epic or two-app runtime.

## Paper and native adaptation

Use [Thorbis Mobile](https://app.paper.design/file/01KY0S86CYXENWSH216F3ZB058/B-0),
file Thorbis — Schedule Redesign, token hash `2803f4aa`. Actual direct Paper JSX
for **73 · State · Offline (working)** (`3YFX-1`) groups Pending sync rows for a
note, photos and arrival status. **74 · State · Back online (syncing)** (`3YK5-1`)
is the paired sending state. Direct export was inspected for both; sending/completed
rows are design guidance, not permission to invent per-row send status.

Adopt the planar group/row hierarchy, quiet symbols and 20pt gutter. Reuse existing
PaperGroupHeader, shared semantic fonts/colors and native navigation/confirmation
controls. Adapt static tiny type and 40pt rows to Dynamic Type and at least44pt
staff targets. Do not create a new skin, bespoke gesture or replacement tab.
The user chose the existing Paper design over 12ui alternatives; no generation,
new palette or candidate selection is part of this work.

## Entry, hierarchy and actions

1. Keep the existing banner locations. When either current queue has an item,
   show a tappable summary online or offline, even when no command is refused.
   Attention outranks sending, then queued. Show a combined **item** count (not
   "changes" for photos), counting each command/media ID once. Keep the existing
   offline/cache-age explanation when there is no listed pending work.
2. Open a native sheet titled **Saved on this phone**, with its own NavigationStack
   and `.paperDestinations()`, medium/large detents and a Done button. One sheet
   state carries the captured verified scope; do not add competing review sheets.
3. Group rows by job. Resolve title from current `Store.jobs` only; fallback is
   **Job** plus its secondary short reference, never a fabricated address/name.
   Job groups sort by oldest pending item; rows sort by creation/capture time then
   typed stable identity. Preserve chronological dependency order; grouping is
   presentation only. IDs distinguish `command:<id>` from `media:<id>`.
4. Each group has **Open job**, using `NavigationLink(value: PaperRoute.job(id))`
   inside this sheet. Job detail opens through the existing route even when absent
   from the loaded list. Native Back returns to the review; Done dismisses the
   sheet and restores the original screen/path. The review owns a local
   NavigationPath containing the existing typed PaperRoute values; ordinary
   destination handling remains `.paperDestinations()`. While inside a job pushed
   from this review, its OfflineBanner returns to this same review root by a
   sheet-local environment action, rather than presenting a second review sheet.
   If the captured scope has retired, that action dismisses instead of revealing
   old rows. Media rows explain that previews,
   tags and file-specific retry are in the job's **Photos** tab. Do not duplicate
   capture/preview/recovery UI or extend job-tab routing in this increment.
5. Commands retain summary, date, exact refused reason and held explanation.
   Rejected rows retain Retry and Dismiss; held rows cannot leapfrog the refused
   predecessor. Retry uses the existing `retry(_:)`, preserving command ID and
   release semantics, then can drain when online/currently permitted. Offline
   Retry only requeues existing supported work; it never claims server success.
6. Dismiss removes only that existing local refused command through `dismiss(_:)`.
   Confirm with native **Discard saved change?**, explaining that the server is
   unchanged and later eligible changes may retry. Re-fetch the current entry
   after confirmation; a stale ID/scope/state must have no effect. No media-delete
   action is introduced.
7. Media rows use existing metadata title/kind/tag/capture date without reading
   full bytes. Exact `uploadingID` means **Uploading**; an error means **Needs
   attention** with its existing reason; `unverifiedIDs` means **Needs checking**;
   otherwise **Waiting to upload**. A current active upload outranks an older
   transient error label for that same item. Preserve the original capture time.
8. Queue-wide command `syncing` permits **Syncing changes** in the summary, but
   must not label every pending command as the particular command being sent.
   Rejected/held command rows remain distinct while other work sends.
9. One primary **Sync now** uses existing guarded drains. Keep its label/geometry
   stable while busy. Revalidate session first, recheck the captured scope, require
   online/current `job.edit` on `jobs`, drain eligible commands using
   `session.isFeatureOn("offline_sync")` and a live current-scope/capability
   `canSend` closure, recheck scope after awaiting, then drain media with its
   corresponding live closure. The command drain must check captured identity,
   opaque binding, API generation/origin, task cancellation and canSend before each
   command batch,
   REST mutation/fallback, conflict-recovery GET and all post-await local updates.
   Retire stale results without removing/reidentifying pending work, changing
   holds, recording stale sync totals or persisting another binding’s state.
   Do not automatically retry
   rejected commands. Disable new sync while offline and explain that saved work
   will retry when the app can reconnect; do not promise background timing.
10. Never show a success/all-synced state while either current queue has an item,
    either store is sending or an unresolved listing/storage warning exists.
    When no rows remain, use **No pending items listed for this workspace**, not
    a global "Everything synced" certification. A generic storage/listing warning
    may explain incomplete listing without revealing another workspace's records,
    counts, filenames or legacy ownership. Preserve existing sign-out/legacy
    recovery notices in their original surfaces; do not enumerate them here.

## Scope, lifecycle and privacy

Capture actor ID, organization ID, normalized API origin, `session.generation`,
`api.requestGeneration` and the opaque media `CaptureContext` when opening. Obtain
that context through `captureContext(matching: PendingMediaScope(actorID:
organizationID:origin:))`, which normalizes origin exactly as bind does and returns
nil unless the entire requested owner matches. Ready Session A with media bound
to B must reveal no media metadata and offer no saved-work actions. Before
rendering any rows or executing an action require ready, unexpired `job.view` on
`jobs`, matching user/workspace/origin/generations and matching media context.
Filter commands again by their own actorId/organizationId. Media comes only from
the bound current store; never scan another scope's disk folders for this review.

If binding changes, immediately render no prior rows, cancel view-owned work and
dismiss the review, including a pushed job or pending discard confirmation.
A→B→A must not reactivate the old sheet/action token. Recheck current scope after
all awaits and at the discard/retry commit. Existing stores/server still govern
writes. FieldOutbox's existing persistence format/scope is not expanded; its
new drain guard captures the binding at entry and checks it throughout delivery.
Do not claim new durable origin or two-app isolation for old queued files.

Ordinary `SessionController.revalidate()` preserves session generation. Its existing
`scheduleExpiry` invalidates published session state at the deadline; the review
observes that state and retires immediately. Do not add another timer or expiry
source of truth.

Keep note bodies, raw file bytes, other-workspace records, unknown legacy photos,
provider data and customer-mode surfaces out of this review. No new persistence,
backend routes, dependency, SDK, logging, analytics or permission prompt. The only
store changes are the read-only matching-context accessor and narrow command-drain
authority/binding guards; queue schemas, persistence and App resync scheduling stay
unchanged. File
preview remains in the existing job media flow. No bank-check capture/deposit,
new payment method, offline signing or financial completion is added.

## Acceptance evidence

- Real-store metadata tests cover mixed queues, typed-ID collision, sorting,
  counts, command-wide versus media-row sending, errors/held/unverified states,
  and no all-clear with remaining work or incomplete listing.
- Scope tests cover foreign entry filtering, nil/expired authority, origin change,
  workspace flip including A→B→A, ready Session A/media B refusal, stale retry/
  discard and post-await cancellation. Gate command POST, REST/fallback and
  conflict-recovery GET boundaries; revoke authority or flip binding while blocked,
  then prove no later request/local mutation and exact persisted IDs/holds remain.
- Native journey opens from both offline and online banners, sees mixed note/photo/
  PDF/status work, opens an uncached job by the existing route, returns with Back,
  cancels/confirms discard, then dismisses to the unchanged original navigation.
  Tap the pushed job’s OfflineBanner and prove it returns to the existing review
  root with exactly one review sheet; Back/Done remain native and unambiguous.
- A relaunch without reseeding retains real queue identities/times. Reconnect
  uses original IDs and no duplicate transfer; permission loss prevents new work.
- Large accessibility text on iPhone and narrow/wide iPad retains counts, status,
  explicit Open job/Retry/Dismiss/Done and readable reasons without overlaps.
  Verify VoiceOver labels/order and focus restoration as supported; physical
  assistive-technology/device qualification is separate if not actually executed.
- Inspect rendered native screenshots against Paper73/74 and shared components;
  record exact tests/counts, source hashes, limitations and user-facing notes.

## Independent builder-check remediation

The initial builder check found two Important issues and one Minor: missing live
command-drain authority, unverified media-owner matching and a nested review
presentation. The plan now owns those exact changes and regression boundaries.
Implementation remains gated on scoped re-review and the coordinator’s frozen
media-cleanup commit; this document does not authorize editing that source early.

No unresolved product question requires another user approval. Grouped review,
inside-sheet existing job routing, and the single sync action are builder choices
under the authorized goal and remain subject to independent design/code review.
