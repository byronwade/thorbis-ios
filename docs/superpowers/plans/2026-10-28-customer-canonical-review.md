# Canonical customer estimate review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make customer mode review the exact current issued estimate before any new approval.

**Architecture:** Decode immutable revision DTOs and validate their captured identity against a fresh aggregate read. Bind the public signing path to that reviewed revision and issued paper hash. Existing customer presentation owns the screens; no business write contract changes.

**Tech Stack:** Swift, SwiftUI, URLSession, XCTest/XCUITest; existing canonical Thorbis HTTP API.

**Spec:** docs/superpowers/specs/2026-10-28-customer-addons-design.md, C0. C1-C3 remain required follow-on stages of the full customer add-on outcome.

## Global Constraints

- Do not add an endpoint, provider, schema migration or live financial action in C0.
- Preserve drawn signatures, typed name, consent, decline, Back, Not today, technician hand-back and complete options.
- New decisions use current aggregate sent status and exact immutable issued revision; immutable DTOs never masquerade as EstimateRecord.
- Public action money is integer minor units despite Double decoding. Never round contradictory money to match.
- CustomerType and Guided CustomerPresentation remain the design owners: 20pt/22pt body, 34pt/40pt totals and 56pt targets, with Dynamic Type.
- Workspace/session changes and cancellation cannot publish or approve old context.
- Tap to Pay remains disabled pending its separate distribution qualification.

## Review Focus

- Same revision number on another estimate/customer/organization/location must never become this job's reviewed paper; Task1 identity regressions.
- An older issued revision or aggregate draft cannot enable a new approval; Task1 currentness regressions.
- A public hash, currency, total or option metadata mismatch must stop signing before final decision; Task1 mismatch regressions.
- An API-generation change during either read chain must stop the chain and leave no usable signing link; Task1 gated transport regressions.
- Customer UI must not briefly expose stale caller terms or auto-select a removed option; Task2 native loading/canonical-data and model regressions.

---

### Task 1: Immutable review and signing API contract

**Files:**
- Create: Thorbis/Sources/CustomerEstimateReview.swift
- Modify: Thorbis/Sources/CustomerPresentation.swift, existing in-person API extension
- Test: ThorbisTests/CustomerEstimateReviewTests.swift

**Interfaces:**
- Consumes: EstimateRecord, FieldLine, FieldEstimateOption, PublicEstimateAction, APIClient.requestGeneration and existing send/fieldEstimate/publicDocumentAction methods.
- Produces: CustomerIssuedEstimateRevision: Decodable, Equatable with id, estimateId, organizationId, customerId, locationId, revisionNumber, status, title, lines, options, totalAmount and currency.
- Produces: APIClient.customerIssuedEstimateRevision(for expected: EstimateRecord) async throws -> CustomerIssuedEstimateRevision.
- Produces: APIClient.openInPersonEstimateApproval(_ revision: CustomerIssuedEstimateRevision) async throws -> (token: String, action: PublicEstimateAction), replacing the unchecked id/revision overload and retaining the existing route order after review.

- [x] **Step 1: Write failing behavioral tests**

Use complete URLProtocolFixture aggregate/revision/paper/action responses. Assert returned canonical title/lines/total differ from caller data; exact route identity; rejection of foreign estimate/org/customer/location, superseded revision, changed current number/draft; rejection of public hash/revision/currency/total/option mismatch; rejection of malformed fractional public money without rounding. Gate a read, rotate API context, release it and prove no later route is sent. No live writes.

- [x] **Step 2: Run Task1 RED**

Run focused xcodebuild test with -only-testing:ThorbisTests/CustomerEstimateReviewTests, a fresh resultBundlePath and the existing owned iPhone simulator. Expected: absent new DTO/API compilation errors, then behavioral failures where applicable; zero selected tests is not evidence.

- [x] **Step 3: Implement the read-only DTO and guarded API chain**

Read current aggregate then exact revision, validate identity/status/revision, and capture/check API generation and Task cancellation around each await. On the signed path, validate the paper envelope source and revision, mint with its hash, read the token action, then require matching hash, revision, full option metadata/base scope, title, currency and amounts before returning it. Preserve API error meaning with concise repair guidance; do not expose internal payloads or tokens. Keep validation in the new focused source file and existing transport methods.

- [x] **Step 4: Run Task1 GREEN**

Run CustomerEstimateReviewTests and PublicEstimateActionTests together. Expected: all selected cases pass, zero failures/skips. Save xcresult summary and source fingerprints; no source edits while Xcode runs.

- [x] **Step 5: Commit**

Commit the verified contract, tests, spec and plan as `fix: bind customer review to the issued estimate`.

### Task 2: Present canonical data with recovery

**Files:**
- Modify: Thorbis/Sources/CustomerPresentation.swift
- Modify: Thorbis/Sources/PaperPreview.swift
- Modify: Thorbis/Sources/App.swift, DEBUG-only preview fault-control hit testing
- Modify: Thorbis/Sources/ReleaseNotes.swift
- Test: ThorbisTests/CustomerPresentationTests.swift
- Create: ThorbisUITests/CustomerEstimateReviewUITests.swift

**Interfaces:**
- Consumes: Task1 DTO and guarded API methods.
- Produces: CustomerEstimateFlow canonical revision adoption and existing screen flow, using canonical title/lines/options/currency/server total after loading. Existing EstimateRecord remains the captured aggregate context only.

- [x] **Step 1: Write failing model and native journeys**

Model assertions: canonical changed title, quantity, descriptions and server total drive review; preserved option ID uses canonical details; removed ID returns to choose with none selected. Native assertions: opening has no approval control until canonical read completes; contradictory local price/details are replaced by canonical values; a failed opening has Try again and a successful retry restores the correct review. DEBUG fixtures intercept all requests and still refuse non-GET writes.

- [x] **Step 2: Run Task2 RED**

Run focused CustomerPresentationTests plus CustomerEstimateReviewUITests. Expected: intended new adoption/readiness journeys fail on old presentation. Record exact execution count and assertions.

- [x] **Step 3: Wire canonical opening and signing**

Before new decisions, show `Opening your estimate…`, then existing option/review screens from the loaded revision. Failure shows a named recovery and Try again. Retain Not today/hand-back while opening or failed. Clear ink/consent/link state for a replaced review, retain only still-valid option IDs, and prevent stale API-generation actions. The drawn staff approval uses the reviewed revision; the public path uses Task1's exact link. Keep all current screens/actions and Paper sizing. Add today's visible-change release note.

- [x] **Step 4: Run Task2 GREEN**

Run CustomerPresentationTests, CustomerEstimateReviewTests, PublicEstimateActionTests, JobCommercialDocumentsTests, the new native journeys and WhatsNewTests. Expected: all selected tests pass, zero failures/skips. Export the canonical review and recovery screenshots without altering pixels.

- [x] **Step 5: Commit**

Commit as `fix: show canonical customer terms before signing`.

### Task 3: Verify and review the complete native change

**Files:**
- Create: docs/superpowers/execution/2026-10-28-customer-canonical-review.md
- Preserve: this plan's xcresults, source fingerprints, full review and rulings.

**Interfaces:**
- Consumes: Task1/2 completed implementation and source range from d834fa9.
- Produces: verified native source ready for a separate signed TestFlight release phase; full customer add-ons remain unfinished.

- [x] **Step 1: Run full frozen-source native scheme**

Run the full Thorbis scheme on the owned iPhone using a new xcresult. Expected: every executed case passes, zero failures/skips; record actual count and source fingerprints. Run the existing release-script checks if release inputs changed or their last evidence no longer applies.

- [x] **Step 2: Perform one fresh whole-branch review**

Use executing-plans' review package and requesting-code-review on the most capable available model. Supply spec, plan, Review Focus and ledger rulings. Regrade by user effect; resolve Important findings once with failing regressions then a passing full scheme. No re-review loop.

- [x] **Step 3: Commit verification record**

Record exact commands/results, accepted/deferred rulings and remaining C1-C3 scope. Commit as `docs: verify canonical customer estimate review`. Continue to the separately authorized archive/upload/group verification phase; do not mark the continuous app goal complete.
