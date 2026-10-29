# Durable scoped job media

Native BYR-1585 increment underBYR-416; base1864c498d437658322dc0eb0a595dd2dae152535.
Photos and scanned/imported PDFs commit protected payload+metadata units before
upload, retaining operation ID, bytes and capture date across navigation/relaunch.
The queue binds verified actor/organization/API origin/job, serializes drains and
checks current binding, generation and capability before each upload/removal.
Delayed capture cannot adopt a new workspace, including A→B→A. API origin changes
retire in-flight requests. Only exact stored server confirmation removes local work.
Unreadable files retain metadata/error state; sign-out warns about all queued media.

Current Paper groups/rows, capture/import/preview, before/after tags and retry stay
reachable. Pending work suppresses the empty state. Full image payloads are not
published; original camera images leave callbacks before network suspension.
This improves retention behavior; no measured performance/battery claim is made.

## Evidence

Worker's initial interrupted confirmation regression produced7 assertions, not a
completed result bundle. Later completed REDs cover unreadable-error retention,
stale capture binding and API-origin changes. Missing new types initially caused
compilation RED, not a runtime proof for every new storage case. One UI locator
initially required the wrong XCUI type and was corrected against the rendered row.

Focused units:62executed,61passed,1simulator-only protection skip,0failures.
The same invocation's initial UI locator failed; the
[saved summary](../../design/evidence/durable-job-media/units-and-initial-ui-run.json)
is deliberately retained as failed rather than relabeled green. The independent
[unit transcript](../../design/evidence/durable-job-media/unit-transcript.txt)
shows each passing suite and the explicit skip. Xcode later pruned that older
derived-data result bundle; saved summary/transcript/source fingerprints remain.

Final native journey:1/1passed, no failures/skips; [summary](../../design/evidence/durable-job-media/final-ui-run.json).
It finds the literal client ID and capture timestamp, changes tabs, then relaunches
without reseeding the isolated queue. Another job's item remains absent. Teardown
verified its synthetic directory removed. [Inspected preview](../../design/evidence/durable-job-media/queued-scan.png)
shows a read-only fixture refusal, not a real upload. Actual transfer/removal uses
intercepted network tests with the production store. No real customer media was sent.

Final additional payment/What's-new regressions after release notes:57/57passed,
zero failures/skips; [results](../../design/evidence/durable-job-media/release-regressions.json).
The unit snapshot differs from final worker snapshot only in MediaView and its UI
test; final native journey rebuilt those. Root verified all11final worker hashes,
then added release notes and compiled/tested the latest app in the57-run.
[Frozen Swift sources](../../design/evidence/durable-job-media/source-sha256.json).
Initial independent review and its fix pass are recorded below; signed release
qualification follows. No upload claim yet.

## Decisions and limits

Continue existing authorized implementation/release workflow without repeated menus;
cost if wrong: reviewable changes need revision. One coherent task's independent
review also covers the entire media branch; no duplicate review of an identical diff.
Important focused checks follow the user's instruction; unrelated behavior is not
certified by these runs. Existing payment PR79 and prior document-book delivery
retain their separate evidence rather than repeating a full scheme.

The simulator does not expose the requested protection attribute. Backup exclusion,
counts and cleanup were checked separately and pass. Physical lock/unlock protection,
camera/scan capture, VoiceOver interaction, large text/iPad and production-network
upload are not certified here. Files use the native protection API; no hardware claim.

Legacy photos now have the explicit verified-destination recovery described below.
Unknown/unreadable files remain preserved without guessed ownership, automatic
upload or preview. This is foreground8MiB single-PUT media,
not background/multipart support or private bank-check evidence. Native manual card
entry is BYR-1584; Tap remains gated pending distribution qualification. Parent
BYR-416, customer catalog offers and the overall continuous goal remain incomplete.

## Review fix round 1

Initial review returned0Critical,3Important,1Minor. Root regraded lost cleanup
warning Important because failed promised deletion must be visible. All four were
reproduced with completed native REDs before fixes. Valid legacy photos now have
a reachable recovery flow rather than a preservation-only deferral, consistent
with the user's feature-retention requirement.

Transfer receives the current binding/generation/capability guard and checks it
before each register/PUT/confirm mutation. Gated revocation tests prove no second
or third request after known permission loss. Known integrity failures persist in
protected markers; restored rows remain unverified until read validation without
bulk payload reads. Cleanup failure has a separate generic LoginView notice that
survives nil-identity bind/reload. It lasts for the store lifetime, not a persisted
new-process audit warning.

Legacy recovery fetches the exact current canonical job online and verifies its
ID/organization before offering only matching-job metadata. The user confirms
adoption to the named current job/workspace; original ownership remains unknown.
A second fresh lookup and scope checks precede adoption. Exact bytes/ID/date are
committed and verified in the scoped queue, then a protected recovery receipt
permits idempotent cleanup of either partial legacy-source ordering. Unknown files,
stale/foreign authority and collisions keep source copies. Recovery does not itself
upload or automatically preview images; normal guarded Retry remains available.

Online proof has its own RED: default URLRequest caching could reuse a response.
Only recovery opts into reloadIgnoringLocalCacheData plus Cache-Control:no-cache;
ordinary endpoint/trust/credential behavior remains unchanged.

Completed overlapping scoped runs qualify65distinct media/API/native cases:
64passed,1unchanged simulator-only protection skip,0remaining failures.
[Focused44-run](../../design/evidence/durable-job-media/fix1-focused.json),
[final33-run](../../design/evidence/durable-job-media/fix1-final.json).
After those API changes, root's payment/WhatsNew regressions passed57/57 with no
failures/skips; [results](../../design/evidence/durable-job-media/post-review-regressions.json).
One aborted overlapping build and a zero-case individual UI selector are explicitly
excluded, not counted as qualification. Final runs used outside-derived bundles.
The final release-note recovery wording was manually checked against existing copy
bounds afterward; its ID/date/count remain unchanged and Release will compile it.

Root verified all12worker source hashes and visually inspected the recovery
[destination](../../design/evidence/durable-job-media/recovery-destination.png),
[confirmation](../../design/evidence/durable-job-media/recovery-confirmation.png),
[recovered row](../../design/evidence/durable-job-media/recovered-photo.png),
[cleanup notice](../../design/evidence/durable-job-media/cleanup-notice.png) and
queued PDF. All are isolated synthetic previews. Independent scoped re-review of
7214abc→0ffd577 cleared all four original findings, with no new Critical or
Important findings. Signed archive/upload qualification is now underway.

One Minor follow-up remains: interrupted legacy cleanup can leave only a legacy
JSON file after recovery succeeds. If normal upload then deletes the scoped unit
and its recovery receipt, that JSON remnant can retain a stale recovery warning.
The media bytes have already been confirmed stored by the server; this is a
cleanup-proof retention issue, not lost media. Reconcile remaining legacy files
before removing the scoped receipt, or retain the proof independently. This edge
does not block build77. See the [review record](../../design/evidence/durable-job-media/review.md).
