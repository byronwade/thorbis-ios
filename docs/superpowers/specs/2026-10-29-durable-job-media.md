# Durable field media

Linear: BYR-1585, scoped native increment under BYR-416. This does not complete the
parent's remaining push/deep-link/two-app scope.

Photos and scanned job PDFs must survive offline use, leaving the screen and app
relaunch. A saved item belongs to the verified actor, organization, API origin and
job that captured it. Reconnecting or switching workspaces must never upload a
different identity's queue. This uses existing register/PUT/confirm APIs, not new
server storage or banking/check evidence.

## Work and identity

Replace the unscoped PendingPhotos implementation with an injectable, observable
PendingMediaStore. Retain stable client asset UUID, job, photo/document kind, MIME,
filename, tags, original capture date and bytes. Persist every captured JPEG and
scanned PDF before attempting transfer. Preserve Photos import, PDF import, native
camera/scanner, previews, before/after tags and retries. Camera bounds remain2560px
and8MiB; all single-PUT media remain nonempty and at most8MiB.

Bind storage only through verified identity to exact actor, organization and
validated normalized API origin. Unbinding hides the active queue but retains disk
data. Before each queued operation and destructive cleanup, recheck the captured
binding, API generation and job-edit capability. Serialize manual/reconnect drains.
Never accept a scope inferred from a stored file, latest login or job UUID alone.

Legacy unscoped PendingPhotos files remain preserved, excluded from automatic
upload/preview. Display a truthful recovery notice and include them in sign-out
loss counts. Their absent ownership cannot safely be reconstructed; do not assign
them to the next person who signs in. Recovery remains explicit follow-up work.

## Durable storage and state

Commit payload and metadata as one recoverable unit through an atomic final
directory rename on the same volume. Use file protection until first unlock and
exclude queue directories and contents from backup. Failed saves must not publish
an item as saved. Remove only staging data owned by that failed save; never delete
another item or existing queue. Namespace paths with a deterministic digest of the
scope; do not concatenate arbitrary identity strings into paths.

Unreadable, missing or corrupt bytes must retain metadata and actionable error
state. Do not silently remove them or falsely say their bytes are safely saved.
Unreadable/corrupt metadata must not be interpreted as an empty queue; preserve it
and report a storage/recovery warning. Do not retain full payloads in published
lists or read all images to render the queue.

Only a matching stored server asset permits deletion: verify registered/confirmed
asset identity, exact job and expected organization, kind, content hash, MIME and
size, with uploadState=stored. A rejected PUT, ambiguous confirmation, cancellation
or context switch keeps the local copy. Replays retain ID, bytes, hash and capture
date. Preserve the existing no-redirect, no-cookie storage-session protections.

## Presentation and release

Reuse current Paper media waiting rows, error banners, groups, native confirmations
and scan/import controls. Distinguish queued photo vs document, uploading and needs
attention. Do not show No photos yet as if no work exists when pending media exists.
Respect existing capabilities; offline capture stays available only under the
verified cached identity/capabilities already supported by SessionController.
Explicit sign-out follows existing deletion policy only after its warning includes
pending photos/documents across scopes and legacy items, as it already does for
other-workspace outbox entries.

Use isolated synthetic files and intercepted network requests. No actual customer
media uploads or check images. Run important persistence/identity/transfer/sign-out
tests and one native queue/scan presentation journey; preserve previous payment
fixes. Release qualification and a new TestFlight build follow review, with no
claim that native keyed cards, check deposit or Tap distribution are qualified.
