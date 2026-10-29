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
Independent review and signed release qualification follow; no upload claim yet.

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

Legacy/uncommitted files remain preserved with recovery warnings and loss counts,
without guessed ownership, automatic upload or preview. Cost: older pending work
requires explicit recovery in later work. This is foreground8MiB single-PUT media,
not background/multipart support or private bank-check evidence. Native manual card
entry is BYR-1584; Tap remains gated pending distribution qualification. Parent
BYR-416, customer catalog offers and the overall continuous goal remain incomplete.
