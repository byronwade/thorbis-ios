# Job estimate handoff design

Status: draft for coordinator and independent builder review; no product implementation yet.
Base: c42444c2b1f5667290f64c6988206c56100f8bfb, branch codex/job-estimate-handoff.

## Outcome

From a job's Estimates tab, a technician taps **Present estimates** and hands over once. The customer sees every verified estimate for that job together, can choose multiple independent estimates, reviews the selected set, and approves each through its existing canonical signing checkpoint. Already-approved estimates remain visible without being approved again. Only the required per-document signature/consent checkpoint repeats; the customer does not return to technician screens or authenticate between estimates.

This is independent estimates, not selecting multiple mutually exclusive packages inside one estimate. It is not a new atomic approval endpoint or one signature reused across documents.

## Verified current behavior

- PaperJobDetailView.swift:248 gives the Estimates tab a Build an estimate primary action. Rows at645 open individual EstimateDetailView. Show to customer is in Job actions at367.
- TechnicianFlow.swift:111 advances to Create invoice when any estimate is approved, before considering remaining sent estimates at114. Consequently an Approved + Sent job can hide its remaining approval work from the dominant next step.
- JobCustomerDocumentsView already lists job estimates/invoices inside CustomerModeContainer. CustomerJobDocumentBook is read-only paging with one selected document; each sent page starts a separate Review and sign flow. CustomerEstimatePresentation owns one EstimateRecord and defaults its completion to hand-back.
- JobDocumentsLoader.estimates unions the job's origin estimate with all paginated job-estimate links, deduplicates IDs, rejects links for another job and verifies returned estimate ID/organization/customer. Failed/unavailable reads remain partial, not empty. These rules remain authoritative.
- Plain job estimates use POST /v1/estimates/{id}/approve with revisionNumber and FieldSignatureInput(signerName,signedAt,imageMediaId). Signature media is a separately uploaded, confirmed job-bound PNG; current native code does not establish cross-document reuse rights.
- Estimates with options use CustomerIssuedEstimateRevision, commercial-document hash, per-estimate action token, and the existing public-document decision's nonce/hash/revision/option/signer/consent. Its drawn image is only a best-effort job attachment; typed electronic signature/consent is the decision evidence.
- Backend review confirmed multiple independent estimates per job and per-estimate signature uniqueness. There is no qualified batch endpoint; generic /v1/commands does not register estimate approval. No new route is authorized by this design.

## Design references and privacy

Use current golden rules/process and the existing Thorbis Mobile Paper file, token hash2803f4aa. Phone artboard23 Job details (estimates tab) provides the job hierarchy, per-record title/price/status and secondary Add estimate. Artboard36 Sign estimate provides per-document summary/consent/signature. Artboard38 presents mutually exclusive packages and must not become the independent-estimate selector. Artboard37 currently presents an invoice; do not claim it is a multi-estimate design.

The user explicitly corrected artboard23's dominant Build action: when estimates exist, make Present estimates dominant while keeping Add estimate one tap away. This is a documented native adaptation. Reuse shared Paper rows, type, tokens and native navigation; retain customer minimum56pt targets and17pt minimum text. Use explicit controls as well as optional swiping.

The user's screenshot is private. Do not copy its customer identity, image or job details into Git, mockups or evidence. Reproduce the Approved $190 + Sent $0 condition with anonymized native fixtures. A real canonical zero is valid; unloaded/invalid amounts must never become an invented zero.

## Staff entry and existing features

- On the job Estimates tab, Present estimates opens the new estimate overview directly in customer mode. With no estimates, Build an estimate remains primary. Add estimate remains visible and one tap from existing populated lists, subject to current creation permission/complete collection checks.
- A remaining eligible sent estimate must be considered before the automatic Create invoice shortcut caused merely by another approved estimate. Preserve prior invoice collection/review priority and actual job status transitions. This correction does not combine estimates into an invoice or redefine billing provenance.
- Keep individual estimate detail, draft editing/sending, options, decline/revision, share/PDF, generic Show to customer documents, invoice book/signing/payment, deposits and all existing job actions reachable. Do not change invoice aggregation or add-on/offer hold contracts.

## One customer navigation owner

Reuse CustomerModeContainer's single NavigationStack and owner-authenticated exit. The handoff model must live above the container's conditional hand-back screen, so Go back or a denied unlock preserves selected records, results and pending recovery. No second customer-mode container or global router.

Customer child Back, Done, explicit Next and swipe-back remain within customer-owned destinations. None may dismiss the outer cover or reveal staff controls. Hand back/technician unlock is always reachable, including during errors; only existing device-owner authentication may close the customer cover. One final unlock exits the batch, never an unlock after each document. Authentication cancellation keeps the handoff intact.

## Overview, selection and selected-set review

1. Refresh the complete current-job collection under a captured actor/session/workspace/API lease. Show all verified records together, including approved, sent, draft, declined and unavailable references. Show partial/loading state and a count that describes what is actually known.
2. Only fresh sent aggregates whose current exact revision is issued and reviewable can join approval selection. No preselection. Approved records remain visible/read-only and are excluded from new commands. Drafts are visible/read-only and never auto-issued by Present estimates; staff may explicitly review/send them through existing routes.
3. Selecting one estimate never deselects a different estimate. A package choice remains at most one option within its own estimate. Keep independent estimate selection keyed by estimate ID and package selection keyed by that estimate's option ID.
4. Do not enable Review selected while the collection is partial/unavailable or selected terms are unverified. Preserve valid selection through refresh, mark affected records Needs review, and offer a clear retry rather than claiming all records were loaded.
5. Load each selected exact immutable CustomerIssuedEstimateRevision and verify ID/organization/customer/location/current revision/status. Preserve canonical line/discount descriptions, price and currency. Explicitly choose an option where required. Show every selected estimate's full terms before continuing.
6. Show Selected work total only when every amount is verified, checked arithmetic succeeds and currency agrees. Otherwise use currency groups or no aggregate sum. Each document retains its own amount/status; the summary is not one invoice/bill. Do not infer an approved option that the API does not supply.

## Canonical per-document checkpoint

Adapt the existing CustomerEstimatePresentation through a required handoff context rather than rebuilding approval business logic. Its standalone behavior remains unchanged.

The context carries one frozen reviewed item, a stable per-document client asset ID, current-authority predicate, initial visible signer name and customer-only Back/Continue/hand-back callbacks. On entry, refetch current terms and compare with the exact reviewed item before preparing the existing approval path. A changed revision/option/content invalidates affected review; never substitute changed terms beneath an existing signature.

- Plain estimates: each document gets a fresh drawing and fresh confirmed image asset. Preserve the existing revisionNumber/signature request fields; do not invent a contentHash, batchId or idempotency request field. Retain the same asset ID/bytes/signer/time for retry of one exact unresolved attempt. Never reuse another estimate's strokes/image/consent.
- Option estimates: preserve per-document canonical token, content hash, nonce, consent version/text, option, normalized signer and exact decision semantics. No aggregate consent inference and no changes to offer/quote/hold qualification.
- A previously entered signer name may prefill the next document within the same verified handoff, but remains visible/editable. It is not consent. Clear drawing, uploaded-media state, token and consent when moving to another estimate.
- The selected-set Continue is the explicit request to enter the first signing checkpoint, so do not repeat the whole per-estimate review journey unnecessarily. Show that estimate's exact title/amount and required consent before signing. After confirmation, stay on its result until the customer explicitly chooses Next estimate or See approvals. No automatic reader advance.
- Back returns to selected-set review. Not now may return to the overview without silently declining anything. Existing individual decline remains reachable through existing document presentation; no bulk decline is introduced.

## Scope, immutable intent and partial results

Capture job ID, organization, customer/location association, actor, session generation and API origin/request generation. Revalidate complete job membership and current capabilities before each prepare/upload/decision, after awaits and before publishing. A same-customer document from another job is not eligible. A view-scope change retires the entire handoff and cancels owned tasks without exposing staff; existing owner-auth exit/recovery rules remain intact. Edit/approval capability loss removes approval controls and pending confirmation while retaining allowed read-only information.

A reviewed item contains the exact EstimateRecord identity and CustomerIssuedEstimateRevision plus chosen option. Plain approval binds through the existing revision identity/number and immutable terms; public action additionally binds its existing canonical content hash. Do not invent a plain-approval hash request field.

Track each selected estimate separately: not started, needs review, ready/signing, submitting, approved/already approved, or outcome unknown. Persisted server evidence is authoritative; this is in-memory handoff state, not a new offline mutation queue.

- Successful items remain visible and never get resent by retrying another item.
- A lost response is Outcome unknown, not Failed or All approved. Refresh that exact estimate/public action first. If the server confirms approved, exclude it from new commands; distinguish existing approval from evidence of this attempt where necessary.
- Retry only the still-unconfirmed exact current revision and exact retained attempt payload. If content changed or the result cannot be safely reconciled, require review/recovery instead of a new signature or blind replay. Do not mint a replacement token/asset merely because a response was lost.
- Partial success shows, for example, 1 approved · 1 needs confirmation, with a per-record recovery action. It never claims atomicity, rolls back confirmed approval, clears successful records or silently proceeds to billing.
- Selection/content changes invalidate affected pending review, but must not erase an unknown attempt's recovery identity. Already confirmed approvals remain immutable and visible.
- Approval is online. Offline/partial reads stay truthful and offer retry; no command-outbox or customer-mode payment changes.

## Acceptance evidence

Meaningful behavioral RED/GREEN coverage must prove two sent independent estimates can both reach canonical approval in one handoff; approved+sent keeps the remaining Present action; all pages and unavailable references are accounted for; another job for the same customer is excluded; draft presentation sends nothing; options remain exclusive within their own estimate; changed terms invalidate affected review; already-approved items never replay; lost/partial results reconcile without new identities; scope/capability loss prevents further requests; every plain document gets distinct confirmed signature media; public decisions retain exact token/hash/nonce/consent/option.

Actual native journey begins on job Estimates, takes one Present action, displays all cards, selects two, reviews the exact selected set, performs both canonical per-document checkpoints, explicitly advances, sees truthful results and exits through one final owner authentication. Assert staff screens remain inaccessible until that authentication. Include denied/canceled unlock, Back from child, unknown outcome recovery, phone/iPad and largest text/dark/Reduce Motion as relevant. Preserve existing invoice/book/payment and single-estimate regression checks.

No implementation or performance claim is made by this document. Historical saved-work relaunch uncertainty remains a separate preserved concern. The minor disabled Retry/Dismiss appearance can remain deferred; it must not distract from this functional batch.

## Builder/coordinator review

The coordinator approved the complete journey and authority bounds. Fresh builder check `/root/estimate_handoff_builder_check` returned “nothing important left unanswered.” Scope retirement clears the handoff's private contents and cancels its work inside the protected customer owner/recovery screen; it does not dismiss the outer cover onto staff controls. Ordinary composition choices are delegated to the implementation plan. No additional user approval menu is required.
