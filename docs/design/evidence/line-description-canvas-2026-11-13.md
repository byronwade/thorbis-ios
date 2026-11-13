# Technician line description canvas — held test-first work

The existing invoice and estimate editors use `BuilderLineRow`: an inline, vertical
text field capped visually at eight lines. The technician needs a full-height place
to read and edit the same description, with a clear path back to the invoice or
estimate. The customer's document reader stays read-only.

The proposed canvas must write through to the existing line draft rather than keep
a second unapplied working copy. Closing the canvas must not discard edits; the
existing parent editor's explicit discard confirmation still governs abandoning
the whole draft. Capture and revalidate actor, organization, document identity,
session generation and capability before showing or modifying sensitive text.
The canvas must not silently apply text to a different line after a list change.
No capability may be fabricated, and current server validation limits remain in
force until a real, versioned end-to-end backend and sync contract is available.

`InvoiceCatalogQuickEditUITests.testDescriptionCanvasWritesDirectlyIntoInvoiceDraft`
is the intended regression. At this checkpoint it is unrun: the hosted baseline
is queued/running and the local Mac has inadequate disk headroom. A missing control
must fail only after the preview has loaded the correct editor and line.

Known independent blocker: `RootView().id(session.generation)` retires the editor
and its local draft on session replacement. Write-through to the parent fixes no
process-death or root-replacement recovery. Do not merge or describe this as
draft-safe until authority changes, transient refresh, save errors, cancellation,
line removal/reorder, Dynamic Type and iPad have been verified. Preserve the
existing confirmed edit/Price Book actions and current offline behavior.

## Hosted checks and held scope (November 13)

Run 43377867745 passed both direct draft-editing tests at product commit 82ed194e.
Run 43378113208 failed the long-summary baseline because the disclosure was absent;
commit f580cc51 adds the disclosure. Run 43379523298 passed the two direct editing
checks but its summary check failed on an ambiguous repeated button label; commits
dabcf622 and 9f463d40 add contextual accessibility labels and select the edited
line in the test. Run 43379161770 failed the transport-retirement baseline as
expected; commit 4892a225 closes the canvas when the API origin or request
generation changes. Run 43380625802 exercises those four checks against 4892a225;
its result must be checked separately, and it does not cover 9f463d40.

A separate invoice editor test, run 43380735210, demonstrated that switching the
API origin still permits the canvas to reopen under stale parent authority. The
job document association scope does not carry API-origin or authorization
provenance. An experimental parent gate is retained in the separate
`codex/invoice-origin-scope-held-1113` worktree; it is incomplete and must not be
merged. Source-bound provenance or an appropriately authorized read is needed,
including offline handling, revocation and benign refresh. A request that was in
flight when its scope changed may already have reached the server: its result is
unknown and requires reconciliation before retry, rather than a claim that it was
cancelled. Draft preservation across root replacement remains unverified.

VoiceOver, large Dynamic Type, iPad, document/revision changes and the final
integrated release have not been verified. This branch is not a TestFlight build.
