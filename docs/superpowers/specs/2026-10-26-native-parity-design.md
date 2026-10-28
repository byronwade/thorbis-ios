# Thorbis native Swift parity and TestFlight design

## Outcome

Extend the existing `byronwade/thorbis-ios` app into a native Swift iPhone and iPad client with the functionality of the Thorbis TanStack staff workspace, then distribute a verified build through TestFlight using the established Rebuzzle signing/upload process. Preserve backend business rules and existing product gates. Do not replace the app with a web wrapper.

The user requested all TanStack functionality in mobile Swift. The builder's proposed interpretation is the staff workspace in `apps/web`, including its explicitly local-only tools with the same honest limitations. Separate Network/community, public customer portal, operator console, and marketing applications are separate products and are outside this parity target. This boundary needs confirmation.

## Observed starting point

- iOS revision `811faf60fdcc929618292341c5081e84d65421db`: five Swift files, 791 lines; basic jobs/customers and sign-in; numerous inert controls; no tests, durable replica, organization selection, icon catalog, or signing configuration.
- TanStack reference revision `448c238a11245d525d42cc542ce5fe9a512415ff`: 28 registered web destinations and 274 API paths across several products. Endpoint count is not the screen scope.
- Baseline simulator build and unsigned Release device build using Swift 6 with complete concurrency checking both passed on Xcode 26.3 / Swift 6.2.4. App installed and launched on iPhone 17 Pro simulator. These checks do not validate real data flows.
- The older configured hostname `https://api.thorbis.com` returns HTTP 404 `DEPLOYMENT_NOT_FOUND` on 2026-10-26. Discovery found `https://app.thorbis.com`: `/v1/me` returns JSON `{me:null}`, `/api/auth/get-session` returns JSON `null`, and `/v1/jobs` correctly returns canonical HTTP 401 problem JSON without authentication. Vercel confirms production deployment `dpl_9JGbhK9UEDg86SrbP7FwtgUEojcG` is ready. Use this same-origin API once repository routing corroboration is recorded; authorized-workspace end-to-end testing remains necessary.
- Detailed source evidence and feature matrix: workspace `outputs/parity-audit.md`.

## Product behavior

### Foundation

Use SwiftUI, native navigation and controls, iOS 17 minimum initially, and Swift 6 complete concurrency checking. Keep the current visual identity; adapt list, record, and navigation patterns to iPhone and iPad, Dynamic Type, VoiceOver, and light/dark behavior defined by the canonical design contracts. The builder owns reasonable layout details within those contracts.

Production uses a fixed validated HTTPS API origin. Debug identity is compiled only for debug builds and accepts exact loopback hosts; it never sends development authority to production. Restore and validate sessions, select authorized memberships, revoke sessions on sign-out, and synchronously clear workspace state when identity or membership changes. Reject late responses from the previous identity. Use evaluated capabilities and feature exposure to shape navigation; the server authorizes every operation.

Adopt typed API models, keyset pagination, structured errors, cancellation, and request fixtures. Persist permitted read models in a workspace/actor-bound SQLite store. Only canonical registered commands may queue offline, with stable command identity, visible pending/rejected state, and domain conflict policies. Money, permission changes and other online-only operations remain online-only. Never improvise a local substitute for server authorization or financial rules.

### Working field workflows

Implement actual Today/My Day/schedule views and job filters; complete customer contacts and locations; job create, assignment, scheduling, dispatch, manual arrival evidence, start/pause, notes/media, follow-ups, closeout and completion. Implement estimates, immutable revisions, eligible invoicing and customer collection, PDF documents, activity and staff notices. Arrival must include canonical `arrival.method`; completion follows server closeout policy. No button or tab may imply an action that does nothing.

### Staff workspace breadth

Implement search, saved views, reports, gated Price Book, settings and role administration, and entitled progress billing. Preserve scope differences between owner, dispatcher and technician. Reports must not present a partial local page as complete financial totals.

Match existing device-local Inbox drafts, Team/Fleet/equipment/agreements records, workflow drafts, and deterministic Agent interactions with their existing semantics and clear local/draft status. Do not invent message delivery, workflow execution, QuickBooks sync, payroll, or shared roster services that the reference does not have. Preserve feature gates rather than exposing internal work.

### Mobile exclusions required by repository contract

Exclude Thorbis software-plan purchase, pricing, upgrade, renewal, external checkout and hidden compiled commerce actions. Operational invoices for real-world services remain eligible only when canonical provenance permits collection. Typed outbound intents must constrain links. Do not add arbitrary URL opening.

## Implementation and review sequence

1. Establish a release-capable foundation and regression tests for pagination, arrival encoding, session hydration, membership switching, stale-response isolation, and fail-closed feature state.
2. Implement the complete field-job workflow in independently verified slices, including native offline/reconnect behavior.
3. Implement remaining staff workspace parity, preserving local-only semantics and gates. Track each matrix row as implemented, verified, gated, or blocked with evidence.
4. Review auth/tenant boundaries, offline replay, mutation idempotency, money and media handling; test owner/dispatcher/technician permissions and revoked sessions.
5. Build and run iPhone/iPad tests; verify real service workflows; prepare signed archive, icon assets, privacy declarations and release metadata. Upload to the correct Thorbis App Store Connect record using Rebuzzle's proven team/signing setup. Confirm processing and tester availability explicitly.

No claim of full parity is allowed until every in-scope matrix row has validation evidence. A compile or upload alone does not meet that requirement. A preliminary internal beta, if requested, must clearly state incomplete coverage.

## Release dependencies and decisions

The user directed discovery of the backend from the repository; live discovery found `https://app.thorbis.com`, so a new backend deployment is not currently required. Discover existing authorized workspace/test account and Apple record through available tooling; ask only for missing access, never for secret values in chat. Use existing team `T677262U5B` if current Apple access confirms it is the intended Thorbis team. Preserve bundle identifier `com.thorbis.field` if available to that team; do not silently change identity if it conflicts.

Backend deployment is not assumed authorized by a Swift-port request when it would require selecting new paid services or changing production infrastructure. Produce a concrete deployment proposal if no working backend exists.

## Acceptance evidence

- Swift 6 builds and focused tests pass; archive signing and validation succeed.
- Real authenticated user can execute an entire job lifecycle with customer, schedule, evidence, estimate/invoice and authorized collection.
- Cross-workspace switching, session expiration, permission loss and stale network responses cannot reveal prior workspace records.
- Pagination, offline/reconnect, retry, conflict and rejected-command states behave according to contracts.
- Every in-scope feature matrix row has explicit evidence, including local-only limitations.
- iPhone and iPad navigation, accessibility and privacy prompts work.
- App Store Connect confirms the uploaded version/build processed and available to intended testers; external review is separately reported if applicable.
