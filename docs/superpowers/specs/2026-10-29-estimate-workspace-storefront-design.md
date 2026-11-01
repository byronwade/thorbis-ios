# Editable estimate workspace and customer storefront

Status: coordinator design with fresh builder ambiguity resolved; owner-specific implementation plans follow. Not a shipped contract.
Authority: user steering on 29 October2026; golden rules/process; existing Paper Thorbis Mobile. Native source3f5d70e (delivered79), backend C1 foundation9cf341b1. Read-only evidence: [native audit](../../design/evidence/estimate-workspace/recon-native.md), [backend audit](../../design/evidence/estimate-workspace/recon-backend.md) and [hourly/draft primitives](../../design/evidence/estimate-workspace/recon-hourly-draft-primitives.md). Preserve prior customer-addons design and C1/C2/C3 boundaries.

## Outcome

A technician opens an estimate and edits it immediately in the same canvas that shows its work, prices and customer appearance. No preliminary read-only detail, Edit button or Revise sheet. Saving stays in that canvas. The server performs the appropriate draft/revision/change-order transition beneath this interaction; historical signed evidence is never overwritten.

The customer sees a job-specific shop: readable work and item details, optional published items to add to a cart, explicit quantity/package choices, a truthful review, required approval and a supported payment step. All independent estimates remain visible/selectable together; packages within an estimate retain their exclusive rules. Separate documents and their approvals/billing sources remain identifiable.

Paragraphs are first-class content. Estimates, invoices, job notes and every line item can contain long details. No prefix slicing, clipped canonical body, disappearing draft, or silent reduction to a short source label.

## Explicit user requirements

- Technician estimate views show and edit together, with revising the default persistence behavior rather than an extra action.
- Customer presentation protects document editing; customer cart choices remain explicit permitted interactions.
- Support very long paragraphs throughout the named surfaces, including each individual line.
- Give technicians substantially more control of customer presentation, including hours/hourly detail, quantities and descriptions, with immediate preview.
- Preserve every existing capability and keep common work direct. Apply Paper/shared components and native Apple navigation, typography, accessibility and recovery.

## Verified gaps

Native custom lines currently slice at200 characters; revised lines reject above200UTF16 and invoices above211Unicode scalars. Document-note and customer-profile fields are absent. Job notes already have multiline strings and a10,000UTF16 contract but cramped input viewports. Customer rendering largely wraps full strings already; do not replace that with clipped card geometry.

The canonical revise command creates a replacement draft, cannot update changed content in an existing draft, and refuses approved estimates. A new draft-save/concurrency contract is required. Approved work needs C2 change-order/addition authority. Swift must not widen status guards and pretend the server accepts it.

C1 optional offers are published/frozen but deliberately cannot yet be approved. Task3 quote/acceptance and Task4 admission, followed by C2 bill-once additions and C3 native storefront, remain. Shared Documents already owns hashed visibility; Estimate/Invoice projections currently emit no configurable profile. Reuse that machinery.

## Technician canvas

All estimate links converge on one workspace. Opening reads/seeds local editing state and causes no server mutation. Title, scope, quantities and supported prices/details are directly editable where current capabilities allow. Users without mutation authority retain a truthful authorized reader; client affordances never grant server permissions.

Use Paper PYO builder and V97 draft-editor hierarchy, plus existing catalogue search, recents, kind filters and continuous adding. Each line has a stable ID, short label, amount, multiline details and a disclosure for secondary pricing/source/presentation controls. Editing paragraphs can expand inline or open a full-height native editor with the same bound draft; it does not switch from reader mode into editing mode. Keep keyboard/focus/selection, scroll position, undo and unsaved state across these transitions.

One dominant action reflects state: Save changes, then the existing explicit send/present boundary. Customer Preview is directly reachable; document history/PDF/share/decline/other infrequent actions remain in a labelled menu. Preserve option packages, add/reorder/move/duplicate/remove/undo, price-book provenance/Edited/Reset, manual fallback, discounts and membership pricing. Preserve existing invoice and catalogue policies, including invoice repeated-add behavior distinct from estimate merge behavior.

Keep a durable actor/organization/document-scoped local working draft, using existing protected storage policy. Paragraphs, line IDs/provenance, appearance and the observed server version survive Back, backgrounding and process restart. A local draft is not a financial mutation queue: no implicit background send, issue or approval. Explicit online Save retains its exact operation identity/payload through unknown outcomes; later typing must not overwrite that pending intent. Revalidate authority and current versions before restore publication or retry. Unsupported local schema is retained for recovery, never replaced with an empty draft.

Show local unsaved, saving, server-saved, offline-unavailable, conflict and permission loss honestly. A save conflict retains all paragraphs/settings and names the changed version; never reload destructively without an explicit choice. Opening or changing a field does not issue/approve/send work. No financial mutations enter the operational FieldOutbox.

### Lifecycle under the same surface

- Initial or replacement draft: canonical versioned draft save supports repeated edits, not only identical replay.
- Sent/declined unapproved estimate: first save uses the canonical revision transition, then subsequent saves update that replacement draft. The user stays in the same canvas; prior issued paper stays in history. Sending freezes a new revision/hash and requests fresh customer approval.
- Approved estimate: edits seed a full-result proposed change-order draft, including changes/removals/substitutions to previously accepted work, not only an additions basket. Saving creates/reuses a canonical change proposal linked to the exact accepted source, then edits that proposal in the same canvas. The accepted record and original job origin are unchanged. Server-owned comparison/admission determines additions, reductions, substitutions, credits and schedule/deposit effects; the client never derives billable delta by subtracting totals. Existing C2 addition-only work is an intermediate slice, not complete support for this requirement. Required credit/refund authority is separately qualified before a reduction can reach billing/collection. Never call old revise on approved paper or copy lines into billing without admission.
- Issued invoices retain financial immutability. Their draft editor remains available under existing rules; corrections/payment/refund routes remain. This request does not authorize rewriting issued invoice history.

## Canonical draft-save boundary

Add an Estimates-owned draft update with a monotonic draft edit revision and an expected-version precondition, following the existing invoice draft concurrency pattern. Support initial drafts with no issued revision. Lock/authorize before exposing conflicts; validate tenant, customer, source/provenance, option/offer writer contracts and all pricing permissions. Save the complete owned editable contract atomically; omission by an unaware writer must not erase new content.

Retries carry a stable operation identity and exact normalized payload. Reuse existing durable command receipts where available; the implementation plan must identify the actual primitive before proposing another store. Same identity/payload returns the original result; changed payload/actor/scope conflicts. No mutation on open, no new draft per keystroke, and no loss of edits after create succeeds but job linking fails.

Publication separately freezes all customer-visible scope/details/settings into the immutable revision, commercial snapshot/hash and public projections. Draft version and issued revision are distinct concepts. New fields require explicit writer compatibility, successor migrations and actual role/upgrade/concurrency qualification. Historical absent fields keep legacy bytes/hashes/default behavior.

## Long content contract

Keep a concise item label/source identity separate from new optional customer-facing plain-text details. Do not overload Price Book originalDescription or drop provenance to store prose. Introduce optional document customer notes/details in the owning Estimate/Invoice contracts, distinct from internal job office notes.

Coordinator working targets for planning: line/option/offer details up to20,000UTF16 units; document/job-note body up to100,000UTF16 units. Preserve paragraph/newline content and Unicode; reject NUL/unpaired surrogate. These are proposed new limits, not claims that current APIs accept them. The plan must reconcile them with exact encoded-request/resource bounds before implementation; if one field exceeds a transport bound, use an owned bounded operation rather than silently slicing text. Keep existing262,144-byte HTTP cap until an independently qualified successor is designed. Aggregate limits must be explicit, measured and visible before issue/approval.

Do not silently normalize body meaning, collapse paragraphs, strip trailing sections or invent rich-text/HTML support. A versioned canonical plain-text representation must round-trip through persistence, drafts, copy/reorder/duplicate, revisions, API, public review, acceptance, accepted invoice source and exports. Legacy short descriptions remain valid and keep old hash behavior when new fields are absent.

Job running notes remain append-only with their existing queue/recovery semantics; correcting an old log adds a new note. Extend owning limits/queue budgets only with compatible reader/writer admission. Show field/document budget errors beside retained text, never discard input or advertise Saved after refusal.

Customer shop cards may show an explicit short preview and Read details; all paragraphs remain available through accessible expansion/full-height reading. Material accepted scope and required legal terms cannot disappear behind a presentation toggle. Technician controls edit the full text directly. Long lists use lazy/bounded native rendering, with restored context on return. PDF/export must paginate losslessly with continuation layouts and resource bounds; existing table-cell/body/fallback truncation is not acceptable for the new contract. Refuse publication truthfully if complete paper cannot be generated.

## Customer appearance settings

Initial settings belong to each estimate/revision, with bounded stable per-line overrides where justified. Company defaults, if introduced later, affect new drafts only. Store an owner/versioned profile and resolve it through existing shared visibility/presentation; do not use device-only preferences as commercial authority.

Expose supported settings in a quiet Customer appearance disclosure beside live Preview: inline detailed descriptions, quantities, unit rates/prices, line totals and hourly breakdown where backed by canonical unit/rate semantics. Item images/grouping may join only when published data and owner contracts exist. No working-looking switch without persistence/projection.

The item label, exact selected total/currency, required terms and accessible discounts/tax/credits/payment meaning remain understandable. Turning off inline descriptions changes summary density; full material scope stays available in item details/review. Internal cost, margin and private provenance remain excluded regardless of technician display settings.

Hourly information must reflect an explicit verified labor/unit/rate contract; never relabel arbitrary quantity as hours or change pricing by hiding a column. The first implementation plan must resolve actual existing unit semantics, fractional quantity/rounding needs and authoritative calculation before enabling this control. This is an unresolved engineering/business interface to settle from existing Thorbis behavior, not permission to invent floating-point money.

Profile/text changes invalidate affected draft preview/quote/signature readiness. Issued changes require new paper/hash; accepted historical settings remain immutable. Native, public web, snapshot renderer and direct PDF must agree; a hidden column in one renderer is not enough. Public JSON must exclude internal fields and apply the canonical customer projection.

## Customer shop, cart and checkout

Technicians control the published offering. Customers browse only authorized, frozen, customer-safe items and prices, not raw internal catalogue records. Included work is identified separately from optional extras; only explicit published quantity policies permit customer quantity changes. No preselected extras. Existing C1 limits/rules apply until qualified successors exist.

The shop preserves every current-job estimate and invoice. Cart state is grouped by independent estimate; complete options remain exclusive only within their estimate. Add/remove/quantity changes retain details and context, invalidate only affected quotes/consent and require a fresh canonical server quote. Unknown or failed quotes never become zero or a client-authoritative total.

Finish C1 Task3 exact non-consuming quote/append-only acceptance and Task4 held feature/API admission against the expanded immutable text/profile contract. Quote binds current revision, paper hash, token/nonce, normalized choices, exact customer-safe scope, currency/amount and consent. Approval recomputes under locks and persists exact evidence atomically; retries keep their original identity. Retain build79's one protected handoff, per-document signatures and canonical per-item recovery/results.

C2 must expand from its prior addition-only scope to full-result change proposals and source-aware billing/credit admission under the shared job lock, preserving original source revision, schedules, deposits, prior credits and invoice ownership. Unchanged accepted work is never billed again; reductions cannot silently refund or mutate issued paper. Approval/cart choice alone does not create billing authority. Checkout progresses from reviewed quoted work to approval, then the exact supported invoice/payment operation. Preserve clear invoice discount/payment/refund history. Payment-method readiness/entitlements remain separate gates; no fake collection success or invented provider UI.

## Delivery slices and dependency order

1. Canonical repeatable draft-save plus versioned long-text/profile owner contracts and legacy compatibility.
2. Complete paper/public/API/source-copy parity, paragraph/visibility bounds and lossless export.
3. Technician edit-first canvas on those contracts, long-text editors/job notes and persisted appearance preview; ship useful verified coverage for supported statuses, never claim approved editing before C2 exists.
4. Complete C1 Task3/4 exact cart quote/acceptance/admission, then C2 full-result approved-change/bill-once/credit authority; adapt the same technician canvas to those states. Addition-only is useful interim support, explicitly short of the full request.
5. Customer storefront/cart/review/approval/payment integration and accepted-scope confirmation, preserving the multi-estimate handoff.

These are dependency slices, not permission to label the full request complete after slice3. Owner-specific implementation plans must be concrete and independently testable. Backend remains held until relevant PostgreSQL/raw-SQL/RLS/upgrade/concurrency, protocol/paper and independent R3 gates pass. Native uses important affected tests/real phone+iPad journeys rather than repetitive basic CI. Frequent useful TestFlight batches retain exact delivery proofs.

## Acceptance evidence

Technician opens directly editable; no Edit/Revise detour; no mutation on open; repeated initial/replacement-draft edits persist with concurrency; first issued edit retains old paper; approved edits use a new admitted change order. Permission/scope changes stop requests/publication and preserve appropriate local recovery.

Many-paragraph EACH line, options, document notes and job notes retain exact text through Back/background/process restart/save/reopen/copy/duplicate/reorder and on customer/public/PDF/invoice-source surfaces. Include emoji/combining/non-Latin text, boundary byte/length cases, long unbroken tokens, negative credits,500-line scopes and renderer resource limits. No silent truncation, fabricated zero or stale overwrite.

Customer appearance survives reopen and frozen issue; legacy hashes unchanged; hidden/internal fields never leak; phone/iPad/large-text/keyboard/VoiceOver/focus/RTL and export agree. Shopping flows preserve no-preselection, exclusive package vs independent-document choice, exact canonical quotes, changed-selection invalidation, interrupted signing/payment recovery and owner-authenticated exit.

Physical-device and provider qualification is recorded separately; passing unit tests never certifies all-app design/performance or payment readiness. Private user screenshot identity stays out of fixtures/evidence.

## Builder check

Read the existing C1 plan and the source-backed audits. List only material unresolved interfaces that prevent a concrete implementation plan, and propose a source-backed resolution. Settle ordinary implementation choices within this design. User already authorized continuous implementation and opted out of approval/question menus; do not reintroduce those. No product code is authorized from this draft before the coordinator resolves the builder check and writes the concrete first plan.

## Coordinator builder-check resolution

Fresh builder check identified one material ambiguity: approved editing as additions-only versus full resulting scope. Resolved in favor of full-result proposals to match the user’s always-editable working canvas. Immutable accepted history and server billing/credit authority remain mandatory. Costs if implemented incorrectly are double billing or unauthorized deductions; those are required adversarial tests, not client-side assumptions. Ordinary field/API representation and hourly-calculation engineering remain delegated to concrete owner plans using the source-backed recon. No additional user approval menu is required under the prior opt-out.

## Adopted platform guidance

Use native multiline editing for long, editable paragraphs, with focus/keyboard/scroll behavior and full readable content; Apple distinguishes this from compact specific-entry fields. Keep the initial contract plain text with preserved paragraphs rather than promising a rich-text format the server does not store. [Apple text views](https://developer.apple.com/design/human-interface-guidelines/text-views), [SwiftUI TextEditor](https://developer.apple.com/documentation/swiftui/texteditor).

Keep frequent fields/actions visible and related secondary controls behind clearly labelled disclosures. One estimate-level Customer appearance section controls density, while item details remain available without hiding the primary work. [Apple disclosure controls](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls). Paper PYO/V97 remains the visual source; this is a native long-content adaptation, not a new visual skin.
