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
