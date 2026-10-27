# Native Swift parity audit

Audit date: 2026-10-26. Read-only product audit of `thorbis-ios` against `Thorbis-TanStack`. This is source/contract evidence, not a live production validation or release approval. Paths below are relative to the workspace root.

## Executive finding

The Swift app is a small online scaffold, not mobile parity. It reads and creates customers/jobs and exposes part of job progression. It has four tabs, several selection controls with no content/filter behavior, no durable sync, no organization selection, and no effective capability projection. The web registry declares 28 destinations; their maturity differs substantially. Copying every route as if it were a production-backed feature would reproduce demo/local-only behavior and overstate parity.

The canonical OpenAPI contains 274 paths, including separate Network/community APIs, public customer document flows, internal provider/administrative operations, and staff operations. That number is not a native-screen target. The first product scope should be the staff workspace in `apps/web`, with explicit decisions for separate Network/customer-facing products.

## Feature matrix

Legend: **API-backed** means canonical endpoints/domain contracts exist; it does not establish production availability. **Local/prototype** means actual interactions exist but do not commit canonical shared records. Feature/permission/entitlement gates remain authoritative.

| Capability | Web evidence and maturity | Swift state | Implementation priority |
|---|---|---|---|
| Sign-in, membership, workspace | Better Auth; membership choice and setActive; synchronous clearing of tenant data on identity change (`apps/web/src/organization-session.ts`) | Cookie sign-in; no restore/membership selection; local cookie deletion only | P0 |
| Permissions and feature exposure | Server effective decisions project primary/More destinations; `/v1/features`; fail closed on unavailable authority (`navigation/registry.ts`) | Static tabs/actions regardless of capability | P0 |
| Local reads/offline | Canonical SQLite read model, registered idempotent commands, scoped token/binding (`contracts/sync/constitution.md`) | HTTP arrays in memory; no queue/replica | P0 architecture, staged implementation |
| Today/My day | Registered primary surfaces; assigned visit workflow in web | Schedule shows all active first-page jobs | P1 |
| Schedule/unscheduled/dispatch | Schedule, assignment, office-review/follow-up booking API actions; web board and routing | Today/Week/Map selection does not change results; no time/assignee model | P1 |
| Jobs | List/detail/create/assign/schedule/progress/complete/cancel; closeout policy/evidence; notes/follow-ups | List/create/detail; en-route/arrival/start button only | P1 |
| Customer CRM | Create/update/archive/restore, contacts, service/billing locations, lifecycle; strict schemas | Search/create/detail, job history, contact and location add; customer/contact edit, archive/restore and full lifecycle parity remain absent | P1 |
| Properties | Customer-location-backed data plus UI composition (`features/properties.tsx`) | Absent | P1 after customer locations |
| Estimates | Draft/send/approve/decline/revise, immutable revisions, option signing, PDF/action tokens | Job Estimates segment inert | P1 |
| Invoices/payments | Draft lines use revision-safe `/v2/invoices/:id/lines`; issue, payment/refund/card collection, PDFs | Job Invoice/customer Billing segments inert | P1; collection requires mobile provenance contract |
| Notes, photos/media, activity | Append notes; metadata-first upload/confirm/download/archive; before-after sets; authorized audit timeline | Segments inert; no capture/upload | P1 |
| Staff notices | Canonical `/v1/staff/notices`, bounded unread-state/acknowledgement, exact-job authority | Absent | P1 |
| Reports/Money | Revenue/payment/activity/schedule/operations APIs + XLSX; web guards incomplete local aggregates | Absent | P2 |
| Search/collections/saved views | Query catalog, Filter AST, search catalog/events, saved views/favorites/defaults/sharing | Absent; job filters don't apply | P2 |
| Price Book | Real immutable revisions/create/revise/archive API, but `price_book` is **internal** | More row inert | P2, preserve gate |
| Settings/team access | Organization profile/facts, roles/revisions/member assignments/overrides/assignees API | More workspace chevron inert; no settings | P1 identity, P2 admin |
| Team | Web combines built-in dispatch roster with device-local additions; feature comment says no roster domain | Absent | P3 local parity or backend work, do not claim roster sync |
| Fleet, agreements/equipment | Real device-local record interactions/seed records, not canonical shared domain parity (`device-records.ts`, feature files) | Absent | P3; explicitly label local scope |
| Inbox/messages | Draft/queued local store; sent history is seeded; no provider delivery or scheduler (`features/inbox/store.ts`) | More Messages row inert | P3 draft parity; real delivery is separate backend scope |
| Workflows | Device-local draft studio pending workflow kernel; local templates/runs/approvals | Absent | P3; not production automation |
| Agent | Deterministic fact/record/navigation resolver over AI SDK transport; model runtime future (`agent-transport.ts`) | Absent | P3 deterministic parity; do not imply LLM backend |
| Payouts/QuickBooks | Financial evidence UI; QuickBooks explicitly not connected and no sync button (`features/money.tsx`) | Absent | P3 informational parity; connectors separate |
| Progress billing | Billing schedules/deposits/retainage API; **beta + required entitlement** | Absent | P2 only for eligible workspace |
| Time clock | Swift advertises inert More row; not in canonical destination registry | Inert label | Do not invent functionality from label |
| Network/community/requests | Separate public/member/contractor APIs and app; not staff workspace destinations | Absent | Separate product decision, not silently included |

## Concrete Swift defects and mismatches

1. **Arrival action is rejected by canonical domain.** `API.swift:84` encodes only `{to}`. OpenAPI `JobProgressRequest` requires `arrival: {method}` exactly for `arrived`; `domains/jobs/src/commands.ts:1026` throws conflict without it. Supply explicit manual evidence; do not infer geofence.
2. **Pagination is dropped.** `Items<T>` stores only `items`; jobs/customers calls do not send continuation. API lists use `{items,nextCursor}`. Counts and customer-job association can be incomplete after the first page.
3. **Schedule is not a schedule.** `Screens.swift:31` filters all nonterminal jobs, treats first as next, and never applies Today/Week/Map. `Job` has no scheduled time, assigned user, duration, or service-location fields. Cannot truthfully show an appointment order.
4. **Assigned/All/Recent does not filter.** `JobsView` binds a `filter` string but builds groups from the same store array. Its fixed groups also omit paused/canceled and any unrecognized state.
5. **Record segments are cosmetic.** Job Overview/Estimates/Invoice/Media/Activity and customer Overview/Jobs/Billing/Media/Activity never branch their content. More entries are text rows, not navigation controls; phone/message glyphs are not actions.
6. **Incomplete execution workflow.** `nextStep` recognizes only en_route/arrived/in_progress. No pause reason/next-action, cancel, follow-up, closeout evidence, completion invoice, or complete endpoint. `allowedTransitions` is state-machine evidence, not sufficient authorization to offer actions.
7. **Auth state can publish before hydration succeeds.** `signIn` sets `.session` before `/v1/me` completes. That Network account projection is not a substitute for workspace membership activation and effective authorization. No startup get-session flow; production default points at loopback unless configured.
8. **Sign-out does not revoke the server session or clear business arrays.** It deletes all shared cookies and sets auth to none, while Store arrays remain. Introduce an actor/workspace generation boundary, scoped session handling, cancellation/stale-response rejection, and local-store erasure before identity change.
9. **Development identity origin validation is substring-based.** `isLoopback` uses contains(`localhost`/`127.0.0.1`), so an arbitrary hostname containing either substring qualifies. `useDevIdentity` has no internal origin guard. Parse exact URL host and bind dev-header emission to allowed loopback origins.
10. **Errors and retries need contract behavior.** Customer create uses `try?`, discarding a validation/authorization failure. Creation controls permit repeated submissions. Problem model lacks stable code/conflict metadata. No command identity or reconciliation UX exists.
11. **Not all current schemas are expressible in committed OpenAPI.** For example the job detail response uses generic `2XX: Success`, so full DTO generation alone cannot prove parity. Use domain projections and HTTP contract fixtures to complete client contract tests.

## Canonical requirements to preserve

- Native remains a thin client: no duplicate financial totals, entitlement logic, state-machine authority, or backend business rules. Domain action endpoints are intentional.
- Authentication selects an authorized membership; no user-supplied tenant header in production. Identity/workspace changes must withhold old caches, drafts and queued admission synchronously, cancel stale requests, and bind all replies/queues to the original actor/workspace.
- Feature release, entitlement, permission, scope and temporary authority are separate. Read effective decisions and snapshots; use them to shape UX only. API always re-evaluates.
- Replicated entities read from local SQLite; offline writes are registered commands with stable client command ID, actor/workspace binding, conflict policy and visible rejected/reconciliation states. Server-only payment instruments/full audit history never replicate.
- Native sync tokens include endpoint/token/expiry/scope/binding and may contain a hard `authorityExpiresAt`; expire local authority rather than treating cached rows as permanent access.
- Respect current release gates: offline_sync beta; Price Book, job SMS, direct settlement and several undo/restore behaviors internal; progress billing beta plus explicit entitlement. Catalog prose may lag individual implementation; use evaluated server feature state.
- Money stays integer minor units/server-derived. Invoice line replacement is revision-safe v2; issued paper is immutable. Payment state may be pending/reconciliation rather than immediate settled success.
- Customer collections require canonical real-world-services provenance for Apple eligibility. First binary excludes Thorbis software-plan pricing/purchase/upgrade/renewal/external-checkout actions, including compiled-but-hidden code.
- All routes/links require structured mobile manifest and typed outbound intents. Camera/microphone/photos, SDKs, Required Reason APIs and actual data practices need privacy inventory and archive-derived evidence.

## Recommended implementation sequence and acceptance evidence

**P0: trustworthy foundation.** Production HTTPS configuration; exact loopback dev restriction; persisted session hydration and membership selection; session revocation; identity generation isolation; capabilities/features projected navigation; typed API/error/pagination contracts. Add fixtures proving arrival, two-page lists, membership switch, signed-out restore, permission loss and stale response rejection. Establish SQLite/replication and command queue design before adding many mutation forms.

**P1: complete field job loop.** Native Today/My day/schedule and correct filters; customer contacts/locations; assign/schedule; en-route ETA/manual arrival/start/pause; notes and photo evidence; follow-ups; closeout/checks/complete; estimates/invoices and qualified customer collection; PDFs/activity/staff notices. Test a single job from creation through completion and payment against real canonical test services, plus offline disconnect/reconnect and conflict recovery.

**P2: workspace breadth.** Search/queries/saved views, reports with complete-book safeguards, gated Price Book, full role/settings administration and eligible progress billing. Test at owner/dispatcher/technician scopes, feature held/off, no-membership and revoked-authority states. Native iPad must preserve selection/navigation state across layouts.

**P3: intentionally separate maturity.** Match device-local Inbox/Team/Fleet/equipment/agreements/workflow studio and deterministic Agent only if product wants those exact local semantics. Adding real delivery, payroll/timeclock, QuickBooks, workflow execution or shared roster is new backend product work, not a Swift-only port.

**Release evidence.** Build and test iPhone/iPad, accessibility/Dynamic Type, background/reconnect, media permissions and failure recovery; archive with production bundle identity/signing, inspect privacy/SDK content, upload to App Store Connect, verify processed TestFlight build and tester availability. TestFlight upload/processing, compliance questionnaire and external beta review are distinct milestones. Repository code cannot prove Apple agreements, team roles, valid signing assets, App Store Connect record, privacy URLs or a processed build. Keep release status unverified until observed evidence exists.

## Source and audit limitations

Primary inspected evidence: `thorbis-ios/Thorbis/Sources/{API,App,Screens}.swift`; `thorbis-ios/AGENTS.md`; `Thorbis-TanStack/services/api/openapi.json`; `services/api/src/routes/manifest.ts`; `services/api/AGENTS.md`; `apps/web/src/navigation/registry.ts`; `apps/web/src/organization-session.ts`; `packages/features/src/catalog.ts`; `contracts/{api/http,sync/constitution,mobile/mobile}.md`; `apps/mobile/AGENTS.md`; web feature/local-store sources cited above.

Both repositories have CodeGraph indexes. Child MCP CodeGraph calls repeatedly refused with root-only elicitation despite parent successful status queries. CLI has no explore command; used CLI `codegraph query/context` as fallback, then targeted reads where results were absent or truncated. No product source was changed. No live API/UI tests, Apple account checks, or submitted archive were performed by this audit.
