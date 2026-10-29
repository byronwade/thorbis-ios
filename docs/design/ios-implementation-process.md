# iOS implementation and review process

Apply the [golden rules](ios-golden-rules.md) to every screen, feature and bug fix.
The [full supplied reference](references/ios-field-management-guidelines-source.md)
is retained as context; the concise rules resolve its examples against this repo.

## Before changing a flow

1. Read root AGENTS.md, the golden rules, relevant existing contracts, and the
   current Paper Thorbis Mobile artboard/direct style export. Classify the surface
   and reuse the closest shared native component/pattern. Research a materially
   unresolved interaction; record what was adopted/adapted/rejected. Do not
   repeatedly research an already decided shared pattern.
2. Describe the person, role/capability, place, task, one next action and durable
   saved/sync state. Map the full journey and existing feature/action inventory.
   Identify what stays direct and what can move into a labelled disclosure.
3. Identify authoritative data, current tenant/job/document boundaries, local
   persistence/outbox behavior, revision/idempotency contracts and unavailable
   states. Name API/schema/provider gaps before adding controls. Keep feature
   capabilities and server checks intact; do not invent business rules in Swift.
4. Write a proportionate spec/plan for substantive behavior. Include original
   requirements, exact acceptance evidence, failure/recovery states, accessibility
   and rollout constraints. Apply these rules to existing in-progress plans too.
   Separate required target behavior from current capability and research ideas.

## During implementation

- Reproduce bugs and add meaningful regression coverage before fixes. Follow the
  repository's TDD workflow for behavior; human prose and trivial reversible
  documentation edits do not need source-text tests.
- Reuse/configure shared components and semantic tokens before adding a variant.
  Keep views focused, state ownership narrow and record IDs stable. Preserve
  drafts and navigation position; cancel/ignore results from a former session,
  workspace, job, document or selection.
- Make loading, empty, partial, stale, pending, failed, conflict and denied states
  real and recoverable. Verify local persistence before saying saved, and server
  evidence before saying confirmed. No mock data or read-only preview escapes to
  production. No new online-only constraint on supported field work.
- Verify one-handed use, native Back/sheets/keyboard, actual long descriptions,
  visible action and amount, per-record status and explicit gesture alternatives.
  Keep all current features and advanced actions reachable.
- Review the shared change across its consumers so estimates, invoices, payments,
  customers, jobs, catalog, settings, media and later features stay consistent.
- Update the implementation record with evidence and open gaps. Do not silently
  weaken a rule to make a test, screenshot or release pass.

## Before review and release

Use a compact evidence table in the feature's execution record:

| Check | Evidence required |
| --- | --- |
| Complete journey and feature retention | Before/after entry, action, exit and secondary-action inventory |
| Paper/shared component consistency | Exact source/artboard, adopted native adaptation and rendered screenshots |
| Identity and authority | Tenant/job/document/version/permission regression results |
| Money and signatures, when affected | Exact reviewed terms, reconciliation, idempotency and immutable receipt tests |
| Offline/recovery, when affected | Local save/relaunch, pending/conflict/error/retry and uncertain-result evidence |
| Accessibility and adaptation | Large Dynamic Type, VoiceOver/focus, contrast/motion, phone/iPad and RTL/long text as relevant |
| Reliability/performance | Relevant tests, representative data, device/runtime measurements; no inferred pass |
| Privacy and permissions | No sensitive analytics/log payloads, contextual permissions and valid denial recovery |
| Release | Fresh full native scheme, source fingerprints, notes, archive/signing and distribution boundary checks |
| TestFlight delivery | Unique build, successful upload, completed processing and intended group access |

Record pass/fail/not-tested/not-applicable with concrete evidence and a reason.
Review scope must match the claim. A scoped docs change does not require an app
archive; a customer flow release does. A passing unit suite does not prove device
accessibility, exact Paper parity, provider readiness or production rollout.

Use the repository's independent review workflow for substantive implementation.
Fix material findings with regression evidence; preserve explicit limitations.
Do not publish a build with knowingly unfinished scaffolding or failing required
checks. Keep qualified useful batches moving to TestFlight without waiting for
every future feature, and report the exact available build.

## Ongoing work at adoption

- Build 1.0 (75) is the last verified delivered baseline. This documentation update
  does not represent a new TestFlight build or whole-app conformance.
- The job document book, swipe/explicit navigation, discount breakdown and scoped
  payment history remain in progress under
  [their plan](../superpowers/plans/2026-10-28-job-document-book.md). Regression
  tests currently reproduce missing behavior; unfinished scaffolding is not ready
  to ship. Resume by making those tests pass, then implement the full journey.
- Customer/technician catalog offers, exact quote/acceptance, approved additions
  and bill-once billing remain required under the
  [customer add-on design](../superpowers/specs/2026-10-28-customer-addons-design.md).
  Backend C1 work is preserved separately; no completion/exposure claim.
- Keep broader Paper/TanStack parity, offline coverage and qualification gaps in
  [source and coverage](README.md). Preserve the bulk demo-data kit and its
  unanswered destination decision; do not import into a guessed tenant.
