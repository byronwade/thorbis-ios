# Job Estimate Handoff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Present every estimate for one job together and let the customer approve multiple independent estimates within one protected handoff, using required canonical per-document signing.

**Architecture:** A small handoff model owns selection, frozen reviewed terms, per-document progress and the current-authority lease. The existing CustomerModeContainer owns navigation/exit, and CustomerEstimatePresentation gains an explicit handoff context so its existing per-document APIs/signature logic remain canonical. An App-owned presenter retains the model above session phase/generation changes and the container's hand-back branch, preserving protection and progress when authentication is canceled or the customer goes back.

**Tech Stack:** Existing Swift6/SwiftUI/ObservableObject, Foundation, XCTest/XCUITest; iOS18 minimum and pinned dependencies unchanged.

**Spec:** `../specs/2026-10-29-job-estimate-handoff-design.md`

## Global Constraints

- All means the complete verified current-job collection, including all pages and unavailable references; unloaded/partial is not empty.
- Independent estimate selection is separate from one exclusive package selection within an estimate.
- Plain estimates each require a fresh drawing and fresh confirmed image asset for their exact revision; never share strokes/image/consent across documents.
- Option estimates retain the existing per-document token/hash/nonce/option/signer/consent/decision semantics. No new aggregate consent or batch API.
- Never send approvals through generic /v1/commands. Do not add request hash/batch/idempotency fields to existing direct approval bodies.
- Already-approved records remain visible and never join new approval commands. Drafts are read-only in the new presentation and never auto-sent.
- Preserve job/org/customer/location association, actor/session/API generations and live capabilities around requests and publication.
- Customer child Back/Done/swipe remains customer-only. Scope retirement clears private contents inside the protected owner/recovery screen; it never dismisses the outer cover onto staff UI.
- Existing owner authentication exits the handoff once; denied/canceled authentication preserves progress. No repeated authentication between estimates.
- Lost response is unknown, not failed/all approved. Retry only unconfirmed exact current intent after reconciliation; never replay confirmed approval.
- Preserve all existing estimate detail/edit/send/decline/revision/PDF/share, generic documents, invoice/payment and job actions.
- Existing Paper artboards23/36 and shared components govern; artboard38 package alternatives are not independent estimates. Customer targets remain56pt and minimum text17pt.
- User screenshot identity/photo stays private. Native fixtures are anonymized and isolated; no customer/provider network fallback.
- No new SDK/backend/offline queue, invoice aggregation or offer/hold changes. Preserve build78 evidence and source freeze.
- Important affected checks and native journeys, not repetitive full scheme/CI. No permission menus; coordinator controls integration/release.

## Review Focus

- Approved+sent must still offer Present; an ineligible first option estimate cannot hide a later eligible plain estimate.
- Partial pages, empty money lines and changed membership must not become All estimates, a fabricated zero, or another job's approval.
- An approval response lost after server commit must preserve its exact attempt and reconcile without new signature/token identity.
- Back/Done, canceled unlock and workspace change must not expose staff or erase confirmed/unknown results.
- Selecting a second estimate must not replace the first; selecting a package must affect only that estimate, and changed terms must invalidate affected review.

## Recorded decisions and review

Coordinator approved the full design and authority bounds. Fresh builder check `/root/estimate_handoff_builder_check` returned “nothing important left unanswered.” Clarification: view-scope invalidation retires contents inside the protected customer owner/recovery state, not the outer cover. Any submitting/unknown per-document intent and its exact payload are owned by the retained handoff model (or a retained per-document controller beneath it), not only ephemeral child-view state; Back, canceled hand-back or child recreation cannot replace its asset/bytes/signer/time/token/nonce. No blocking product question remains.

---

### Task 1: Complete current-job multi-estimate presentation and approval handoff

**Files:**
- Create `Thorbis/Sources/JobEstimateHandoffState.swift`: selection/review/result types and focused observable handoff model.
- Create `Thorbis/Sources/JobEstimateHandoffView.swift`: all-estimates overview, selected-set review, explicit per-document progression and result/recovery UI inside the existing customer navigation owner.
- Modify `Thorbis/Sources/PaperJobDetailView.swift`: populated Estimates primary action, visible one-tap Add estimate, model ownership above customer hand-back conditional, existing cover branch and dismissal refresh.
- Modify `Thorbis/Sources/TechnicianFlow.swift`: job-level Present step for eligible remaining sent work before the any-approved invoice shortcut; preserve existing invoice priority/transitions and explicit individual draft behavior.
- Modify `Thorbis/Sources/CustomerPresentation.swift`: explicit handoff context/mode, current-term/authority guards, per-document completion/Back, retained exact uncertain attempt and fresh per-document media; preserve standalone behavior and existing canonical methods.
- Modify `Thorbis/Sources/PaperPreview.swift`: DEBUG-only anonymized stateful exact-route fixtures and receipts for actual encoded approvals/media confirmation/partial outcomes. All other writes remain intercepted/denied.
- Modify `Thorbis/Sources/ReleaseNotes.swift`; update `docs/design/ios-golden-rules.md` rule22 only to clarify independent estimates versus package alternatives if necessary.
- Create `ThorbisTests/JobEstimateHandoffTests.swift` and `ThorbisUITests/JobEstimateHandoffUITests.swift`.
- Extend `ThorbisTests/TechnicianFlowTests.swift`, `CustomerPresentationTests.swift`, `CustomerEstimateReviewTests.swift`, `JobCommercialDocumentsTests.swift` where the changed responsibility belongs.
- Record `docs/superpowers/execution/2026-10-29-job-estimate-handoff.md` and separate design evidence. Do not overwrite build78/saved-work evidence.

**Interfaces:**
- Consume existing `JobDocumentCollections.loadEstimates(scope:api:isCurrent:)`, `JobDocumentRead.records/freshIDs/isComplete/unavailableIDs`, `JobDocumentScope`, `TechJobFlow.canShow`, `CustomerIssuedEstimateRevision.validate(for:)` and current API methods. No replacement collection or approval engine.
- Produce `JobEstimateReviewedItem: Equatable` containing the fresh `EstimateRecord`, exact `CustomerIssuedEstimateRevision` and optional selected option ID. Public-action content hash remains on its existing prepared action; plain approval uses immutable revision identity/terms without an invented hash request field.
- Produce `JobEstimateHandoffOutcome`: confirmed approved (including already-approved server state), needs review, or outcome unknown. Keep per-document outcome and exact current attempt keyed by estimate ID/revision; never collapse partial results to one Boolean.
- Produce `@MainActor JobEstimateHandoffModel: ObservableObject` initialized with `job: JobRecord`, `customerName: String`, `documents: JobDocumentCollections`, `api: APIClient`, `session: SessionController`. Expose `refresh() async`, `setSelected(_:selected:)`, `chooseOption(estimateID:optionID:)`, `reviewSelected() async`, `reconcile(_:) async`, `retire()` and read-only rows/selection/review/results/authority state.
- Model captures actor, job scope, normalized origin, session generation and API generation. Each reviewed item's expected location comes from its own fresh estimate and existing revision validation; do not invent a missing job-location field or loosen canonical association checks. Refresh current job membership before committing each selected item.
- Produce `CustomerEstimateHandoffContext` for one reviewed item: initial visible signer name, stable per-document client asset ID, live current/approval predicates, outcome callback and customer-only Back/Continue/hand-back callbacks. The batch path must supply this context explicitly; standalone initialization remains compatible.
- Adapt `CustomerEstimatePresentation` to enter the required signing checkpoint after selected-set review, refetch and compare the expected immutable terms, and call its existing direct/plain or public/options methods. Its normal standalone choose/review/sign/done path remains unchanged. Do not duplicate approval business logic in the handoff model.
- For direct success, verify the returned exact record; for public success refresh/reconcile its exact estimate before publishing the handoff's confirmed result. A failed refresh after an uncertain response stays unknown. Existing per-document request payload/token/asset identity is retained for eligible retry.
- Produce `JobEstimateHandoffView(model:handBack:)`, reusing the existing CustomerModeContainer NavigationStack. `PaperJobDetailView` retains the model until authenticated cover dismissal; model retirement is a protected recovery state, not a nil-model fallback into staff/generic content.
- Add `TechJobStep.presentEstimates` (no single-estimate ID). Use it for any eligible sent estimate before the approved-work invoice shortcut. Keep `.showEstimate(id:)` only for the existing explicit individual draft path; no new Present path auto-issues drafts.
- For native fixtures inject the existing `MediaTransfer(api:storageSession:)` via the handoff adapter; production uses its normal transfer. The DEBUG transport must intercept storage PUT as well as API calls, verify exact synthetic asset/document identity and emit sanitized request/result receipts. No MediaTransfer production semantics or SDK changes are required.

- [x] **Step 1: Write behavioral REDs against the current exclusive/shortcut behavior.**

Add test scaffolds only as needed to compile; a missing type is not sufficient RED. Required assertions:

| Test | Required behavior |
| --- | --- |
| `testApprovedAndSentPrefersPresentBeforeCreateInvoice` | Existing approved+sent job returns job-level Present; paid/owed invoice priority remains unchanged. |
| `testTwoSentEstimatesRemainIndependentlySelected` | Select A then B leaves both selected; choosing A's option does not change B. |
| `testIneligibleFirstEstimateDoesNotHideEligibleSentWork` | Missing option-token permission on A does not hide an eligible plain B. |
| `testCompleteMembershipIncludesEveryPageAndRejectsForeignJob` | Later-page records appear; foreign job/same customer and contradictory identities never enter commands. |
| `testApprovedDraftUnavailableAndRealZeroStayDistinct` | Approved/draft/unavailable rows remain visible but unselectable; a verified canonical zero stays zero; unknown money stays unavailable. |
| `testChangedSelectionOrRevisionInvalidatesAffectedReview` | Prepared approval cannot survive a changed selected set or document terms; confirmed outcomes remain. |

Run the affected selectors and retain actual assertion failures before behavior implementation. Existing fixture/parser stubs may compile new types, but must not implement the behavior before RED.

- [x] **Step 2: Implement the focused state/model and staff entry.**

Use existing complete collections and canonical issued revision reads. Store no new business records or offline queue. Keep collection partial/loading explicit; block selected approval until complete and verified. Make Present dominant for populated Estimates, Add estimate visible in its header, and preserve every existing menu/detail route. Model ownership must survive CustomerModeContainer's hand-back/Go back branch.

- [x] **Step 3: Add meaningful canonical checkpoint/recovery REDs, then adapt the existing per-document view.**

Required tests:
- `testTwoPlainApprovalsUseDistinctConfirmedSignatureAssets`: A and B each encode their own exact revision and fresh image reference; no signature/consent crosses documents.
- `testOptionsKeepExactPerDocumentTokenHashNonceConsentAndOption`: unchanged existing canonical preparation/decision fields; no aggregate consent or command endpoint.
- `testLostResponseReconcilesWithoutReplayingConfirmedEstimate`: first success + second unknown remains per-item; retrying B sends no approval for A and preserves B's exact eligible intent.
- `testSupersededOrUnlinkedEstimateCannotRetryOldApproval`: refetch/review required; no stale request after membership/content change.
- `testScopeOrCapabilityChangeStopsPrepareUploadDecisionAndPublication`: actor/workspace/API change, A→B→A and approval revocation stop subsequent requests and private content; outer customer owner stays protected.
- `testBackAndCanceledUnlockRetainSelectionResultsAndUnknownIdentity`: model remains above conditional hand-back content; no outer cover dismissal before owner auth.

Use real API/URLProtocol fixtures and stored media confirmation responses; never replace approval with setting a local Approved flag. Keep original exact caller-scope validation tests. Guard before/after every await. Preserve a submitted-but-unconfirmed attempt until canonical reconciliation; no blind new token/asset after connectivity loss.

- [x] **Step 4: Implement the customer overview/review/checkpoints/results.**

Show all cards with explicit independent selection, exact price/status and no default selection. Drafts remain read-only. Display selected scope/amounts and option choices before signing. Preserve customer typography/56pt controls. Reuse existing sign/consent UI and canonical methods through the handoff context; only required per-doc signing repeats. Customer explicitly chooses Next estimate after confirmation, never automatic reader advance. End with per-document results and one owner-authenticated hand-back. All child Back/Done/swipe stays customer-only; live invalidation renders protected recovery rather than exposing staff.

- [x] **Step 5: Make the actual native journey RED, implement bounded DEBUG fixtures, then GREEN.**

Create anonymized fixtures with two sent estimates, approved+sent, draft and a foreign-job record; no private screenshot data. Intercept exact existing GET/POST/media PUT/confirm routes and expose sanitized receipt proof of the encoded identities, two distinct signature media IDs and per-item states. Fixtures may simulate a lost response after a recorded commit; no provider/customer network fallback and no production preview exposure.

Required native cases in `JobEstimateHandoffUITests`:
- `testJobEstimatesPresentsAllAndApprovesTwoWithinOneHandoff`: one primary entry, all cards, select two, exact selected-set review, real drawings/encoded canonical approvals, explicit Next, truthful results, one final owner auth.
- `testApprovedAndSentKeepsBothVisibleWithoutReapproval`: no command for already approved; remaining sent can approve; draft presentation makes no send request.
- `testPartialApprovalAndLostResponseRecoverOnlyUnconfirmedItem`: receipt proves no replay/new identity for successful paper and unknown is not All approved.
- `testChildBackDoneAndDeniedUnlockNeverExposeStaff`: return/review/Go back preserve progress; staff becomes hittable only after the one final successful authentication.
- `testWorkspaceRetirementKeepsProtectedOwnerAndNoOldDocuments`: no stale cards or requests, no unauthenticated staff exposure.
- `testLargeTextAndTabletRetainAllCardsPricesActionsAndSignatureIsolation`: phone/iPad portrait/landscape, largest Dynamic Type/dark and explicit navigation without signature swiping.

- [x] **Step 6: Qualify important affected checks and inspect native Paper alignment.**

Use xcodegen only for new files; preserve Package.resolved and StripeTerminal5.8.1. Run focused `JobEstimateHandoffTests`, `TechnicianFlowTests`, `CustomerPresentationTests`, `CustomerEstimateReviewTests`, `JobCommercialDocumentsTests`, applicable signature/media/API tests and `WhatsNewTests`; add exact selectors when implementation exposes an affected boundary. Run the new native journey and relevant existing document book/signing/payment regression cases, not a repetitive full scheme by default.

Use the existing owned iPhone/iPad destinations, one Xcode owner, existing package cache/derived data, and unique outside-derived xcresults. Wait the same handle through result-import epilogues; zero selected tests is not a pass. Inspect full-screen screenshots (app-cropped landscape images can mislead), VoiceOver labels/focus, child Back/native dismissal completion, large text and Reduce Motion. Record actual scope/counts and unresolved physical-device/assistive-technology/RTL gaps; do not infer performance targets were measured.

- [x] **Step 7: Record evidence, self-review and hand off for independent whole-task review.**

Update execution/evidence and a unique new release note. Clarify golden rule22: multiple independent estimates can be chosen together while packages within one estimate remain exclusive and per-document approval/evidence stays canonical. No other golden rule change.

Record exact source/test hashes, behavioral RED/GREEN counts, real native receipts/screenshots, complete feature inventory and boundary gaps. Verify DEBUG fixture exclusion later in Release and clean only owned synthetic fixtures. Preserve historical saved-work relaunch uncertainty as a separate issue. Small disabled saved-work link styling may remain deferred.

Coordinator owns review, integration/commit/PR and the next unique TestFlight build. Do not stage, commit, push, archive or upload until directed; no user permission menu is required for the already-authorized normal workflow.

## Self-review

All specification sections map to Task1: entry/retention (Steps1–2), immutable review/selection/authority (Steps1–3), required signing and protected navigation (Steps3–4), real native behavior (Step5), adaptation/regressions/release evidence (Steps6–7). Review Focus cases each have an explicit named test. New types are a narrow adapter around existing methods, not an approval engine or backend contract. No blocking interface or product ambiguity remains; builder check and coordinator's protected-owner clarification are recorded above.

### Approved production owner lifetime clarification

Coordinator authorized the bounded App ownership adjustment after verifying `App.appContent` replaces `RootView().id(session.generation)` and changes phase branches. The new handoff alone uses an App-owned `JobEstimateHandoffPresenter` and stable outer ZStack cover, above those branches. Reuse CustomerModeContainer; invalidation permanently retires private contents while the protected owner remains. Only successful existing owner authentication clears the active presenter. Generic invoice/document covers and session/resync/router semantics remain unchanged. Actual production workspace-generation, signed-out and workspace-selection transitions must prove staff stays hidden, including denied unlock. Retained exact attempts survive child Back and cancelled handback; invalid scope clears private data, and authenticated exit releases the retained owner with weak callbacks. This supplements the approved flow, not a global router.

### Approved canonical result and protected child corrections

Coordinator approved retaining the existing PublicEstimateActionPatch acceptance when present, otherwise reading the same retained token's full action. Confirm selected packages only against canonical accepted state, bound revision/hash/option/currency/total. Bare approved aggregate remains visible without inferred package price or signer. No replacement token, endpoint or consent version. The scoped destination environment calls the same guarded CustomerModeContainer unlock function; only authenticated owner exit clears the App presenter. Tests must count actual authentication attempts, require exactly one hittable stable owner-exit control, and verify semantic staff visibility after success. Label-mismatch failures are locator failures; earlier selected-review/first-confirmation stops remain preserved as unexplained intermediates.
