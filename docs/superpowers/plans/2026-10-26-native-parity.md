# Native parity implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox syntax for tracking.

**Goal:** Native Swift parity across the approved Thorbis products, verified and available on TestFlight.
**Architecture:** SwiftUI clients consume the canonical same-origin API; typed DTOs and actor/workspace-bound state mediate all views. Domain rules remain server owned. Preserve local-only semantics and feature gates.
**Tech Stack:** Swift 6, SwiftUI, Foundation URLSession, XCTest/Swift Testing, SQLite where canonical replication supports it, XcodeGen.
**Spec:** ../specs/2026-10-26-native-parity-design.md

## Global Constraints

- iOS 17 minimum, iPhone and iPad; native SwiftUI, no web wrapper.
- API origin https://app.thorbis.com; current route probes passed, authenticated flows still need verification.
- No production dev headers, arbitrary URL opening, software-plan commerce, fabricated operational data, or invented backend actions.
- Every workspace response is bound to the identity generation that requested it; membership changes erase old state before awaiting new work.
- Follow canonical pagination, arrival evidence, capability/feature and offline contracts.
- Preserve com.thorbis.field and validate Apple team T677262U5B before signing.

## Review Focus

- A stale response completing after sign-out/workspace change cannot restore old records.
- Pagination errors cannot silently present incomplete totals as complete.
- Redirects and malformed hosts cannot leak credentials or development authority.
- Repeated form taps and retries cannot duplicate business mutations.
- Local-only prototype features must never claim server delivery or financial settlement.

## Task 1: Typed API and session foundation

Files: modify Thorbis/Sources/API.swift; create ThorbisTests/APIClientTests.swift and test transport utilities; modify project.yml for test target.
Consumes existing Customer/Job/APIClient names used by current UI. Produces backward-compatible methods plus async restoreSession(), organization selection, and session generation.
- [ ] Write URLProtocol fixture tests for two-page jobs/customers, arrived payload containing arrival.method=manual, hostile loopback-like hostname rejection, non-loopback dev identity rejection, and default production origin.
- [ ] Run tests against baseline and observe intended failures.
- [ ] Implement endpoint validation, debug-only development identity, pagination with cursor-loop rejection, arrival payload, injected URLSession, structured errors and strict Swift 6 models.
- [ ] Add failing session tests using canonical auth fixtures: restore expired session, failed identity hydration remains signed out, sign-out revokes remote session and clears local auth, stale response cannot change current generation.
- [ ] Implement canonical auth hydration/membership flow after reading outputs/auth-contract.md; do not infer org from /v1/me Network account.
- [ ] Run full tests and simulator/device builds. Commit only this task's files after review.

## Task 2: Real field navigation and workflows

Files: App.swift, LoginView.swift, Screens.swift, new feature-specific files under Thorbis/Sources/Features, behavioral tests.
Consumes Task 1 client and identity generation. Produces real navigation, loading/error/empty flows and field mutations.
- [ ] Write failing tests for job filter/date ordering, session-bound store reset, completed/canceled job grouping, duplicate form submission, and failed create preserving input.
- [ ] Implement reachable create actions, correct grouping/filtering, real schedule data, exact allowed transitions and required evidence, keyboard-safe adaptive login, native TabView/search.
- [ ] Expand customer contacts/locations, assignment/schedule, notes/media, follow-ups and closeout from canonical contracts with request/response fixtures first.
- [ ] Test and review complete customer-to-job lifecycle including error recovery and identity switch.

## Task 3: Estimates, invoices, documents and authority

Files: feature-specific estimate/invoice/document models, services and views; fixture tests.
- [ ] Enumerate canonical DTOs and permitted action endpoints; write request fixtures for revision conflict and missing authority before implementation.
- [ ] Implement native lists/details/forms and documents, server-derived totals, eligible real-world collection only, reports and staff notices.
- [ ] Verify permission loss, retry/reconciliation, stale revisions and complete pagination; never synthesize settled payment state.

## Task 4: Offline, workspace breadth and separate products

Files: scoped persistence/sync layer, workspace settings/search/reports, separately scoped Network/customer/operator views and tests.
- [ ] Record exact canonical contracts per product before adding views; enforce distinct identity and permission scopes.
- [ ] Test workspace-bound local reads, registered command replay, authority expiry and conflicts; implement SQLite replica only to supported protocol.
- [ ] Port remaining matrix rows, including explicitly local-only tools, and separate products approved by user. Maintain evidence per capability in coverage document.
- [ ] Verify each matrix row with permitted/denied roles, native UI and contract tests. Do not treat absent APIs as implemented features.

## Task 5: Release and TestFlight

Files: project.yml, app icon catalog, PrivacyInfo.xcprivacy, release scripts, release evidence.
- [ ] Enable Swift 6 permanently, automatic signing and archive configuration; include required assets/privacy metadata based on actual API use.
- [ ] Run complete tests and accessibility/startup checks on iPhone/iPad; independent code review and resolve important findings.
- [ ] Verify Apple account/team/app record; archive, validate and upload; observe processed build and tester availability.
- [ ] Record exact build/version, upload and processing evidence; report incomplete scope honestly if blocked.

## Execution decisions

2026-10-26: User said “I approve everything”; proceeding without further design/plan approval. Interpreted full scope to include separate products as offered. Work in the task-specific fresh clone on branch codex/native-parity-testflight; no second checkout needed because this clone is already isolated from user's existing repositories. Audit agents may continue read-only independent research while implementation advances. Do not equate the first runnable beta with full parity.
