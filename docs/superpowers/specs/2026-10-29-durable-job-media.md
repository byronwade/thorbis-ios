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
upload/preview. Include them in sign-out loss counts. Their original actor/origin
cannot be reconstructed. Provide explicit recovery for valid older photos of the
current job: first fetch the canonical JobRecord online under current authority,
verify its exact ID/organization against captured scope/generation, then allow the
user to review only matching-job entries and explicitly confirm recovery into that
named job/workspace. Do not call the destination the original owner. The user is
authorizing adoption into a verified destination; no silent assignment occurs.
Retain ID, bytes and capture date. Delete an older copy only after its exact new
scoped unit is committed and verified; interruption/duplicate recovery must not
lose work or create another operation. Refuse stale/foreign/unauthorized recovery.
Unreadable or unidentifiable legacy files stay preserved with truthful warnings.

## Durable storage and state

Commit payload and metadata as one recoverable unit through an atomic final
directory rename on the same volume. Use file protection until first unlock and
exclude queue directories and contents from backup. Failed saves must not publish
an item as saved. Remove only staging data owned by that failed save; never delete
another item or existing queue. Namespace paths with a deterministic digest of the
scope; do not concatenate arbitrary identity strings into paths.

Unreadable, missing or corrupt bytes must retain metadata and actionable error
state across scope rebinding/relaunch, even without upload capability. Recovered
items whose integrity is not yet validated must not say their bytes are safely
saved. Do not bulk-read every payload merely to render metadata lists.
Unreadable/corrupt metadata must not be interpreted as an empty queue; preserve it
and report a storage/recovery warning. Do not retain full payloads in published
lists or read all images to render the queue.

Only a matching stored server asset permits deletion: verify registered/confirmed
asset identity, exact job and expected organization, kind, content hash, MIME and
size, with uploadState=stored. A rejected PUT, ambiguous confirmation, cancellation
or context switch keeps the local copy. Current authority must also be checked
before register/PUT/confirm, including capability changes without API generation
change. Replays retain ID, bytes, hash and capture
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
If sign-out cleanup fails, preserve a separate warning through nil-identity
callbacks and show it on the signed-out screen; do not silently promise deletion.

Use isolated synthetic files and intercepted network requests. No actual customer
media uploads or check images. Run important persistence/identity/transfer/sign-out
tests and one native queue/scan presentation journey; preserve previous payment
fixes. Release qualification and a new TestFlight build follow review, with no
claim that native keyed cards, check deposit or Tap distribution are qualified.
