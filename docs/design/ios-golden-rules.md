# Thorbis iOS golden rules

Adopted by the user on 28 October 2026 for the entire iOS application, including
iPad adaptations. These rules govern new features, bug fixes, cleanup and review.
They describe the required direction; they do not certify existing implementation.

> Quiet chrome. Dominant work. One obvious next action. Place before database ID.
> System UI stays native. State is never hidden. Offline work is real work.

## Design direction (v2, 31 October 2026) — read this first

**Linear grammar on design.thorbis.com tokens; the drawer is an owner-approved
exception.** The owner asked for "linear.app mobile app and design.thorbis.com".
Linear's mobile app sets the layout grammar (quiet titles, circles, text tabs,
grouped sections by space, property chips, a composer, anchored popovers).
design.thorbis.com (`docs` copy: the site's text) is the law for tokens, depth,
controls, forms, words, places and states. "Linear grammar. Not Linear dress":
no Linear purple, no issue row, no status rings as decoration. The site says
"iOS is a tab bar and a stack"; the owner overrides that one rule for this app
and keeps the side drawer (rule 6). Everything below that predates v2 yields to
these points where they disagree:

- **Tokens** (`Theme.swift`): dark is the first drawing — canvas oklch 14.5%,
  panel 20.5%, cream type, a cool grey body, a dimmer marker. Light is the warm
  cream sheet (canvas `#F7F4EE`, panel `#FDFCFA`). One electric-blue accent
  (`Theme.brand`, oklch 55.8% 0.188 264.4) for selected, focus and the one live
  thing — never a wash. Status hues are the site's success, error, info and
  warning, tuned in lightness only. Place marks are olive, forest, pumpkin, burnt
  and the accent mixed down. `scripts/tests/contrast.py` holds 4.5:1 text, 3:1
  marks, both themes and Increase Contrast, with 0 failures.
- **Type:** Inter Regular 400 and Medium 500 only (`Theme.allowed` maps heavier
  to 500). Staff screens use a compact ramp (`Theme.onRamp`): body and row titles
  15, supporting lines 14, chrome 13 Medium, captions 12, sheet titles 16–17,
  detail titles 24, root titles 26; money hero 30. Customer-facing presentation
  keeps its 17pt / 56pt floors through `Theme.customerFont`.
- **Depth:** Rest (the sheet is planar), Sink (fields and selects: `Theme.field`,
  one step darker, inset, 1px rim — `fieldWell()`), Lift (the ink commit: radius
  10, 1px rim, 1px light from above, 1px drop; press sinks), Overlay (menus and
  popovers only: the panel with a real shadow). There is no fifth.
- **No separators:** never a line between rows, under a heading or as a 1px box
  around a section, and never a coloured side rail. A 1px rim belongs only to a
  field, a commit, a chip or a photo. Tone, type and space separate things.
- **Status is a word** (`StatusLabel`: a small mark in the hue, then the word).
  A row never shows colour without its word. Rows lead with the street (time in
  a tabular column); the status word sits in the subtitle or at the trailing edge.
- **Places:** a route for durable records; a modal (`ThorbisModalSheet`, a clean
  system sheet on the panel with detents, 17pt Medium title, close circle, one
  ink commit in the pad) for one task; an anchored popover (`ThorbisMenu`) for
  one local choice — status, tech, payment method, the ••• overflow. Never
  pre-disable a commit: let them press it and say what is missing under the
  field; if it truly must be off, a sentence says why.
- **Motion:** 120ms ease-out for menus, chips and segments; no bounce or stagger
  on routine work; the drawer and sheets may use the system spring; respect
  Reduce Motion. Haptics stay.
- **Words:** Job, stop, tech, truck, Dispatch, Arrive. Placeholders are examples
  ("Mike Reyes"); empty states name the one action.

Keep the [complete supplied guidelines](references/ios-field-management-guidelines-source.md)
as context, including their role tables, component specifications, entity model,
wireframes, flows, conflict policies, privacy guidance and quality targets.
Use the [implementation process](ios-implementation-process.md) on every change.
The source is preserved verbatim. Its imported citation markers are not resolved
source evidence; verify platform/API/version claims before relying on them.

## Authority and consistency

1. **Give each source a clear job.** Thorbis owns operational vocabulary, content
   hierarchy, semantic tokens and truthful work states. Paper Thorbis Mobile owns
   the referenced layouts. Apple owns native navigation, controls, permissions,
   accessibility and platform behavior. Linear Mobile is a reference for density,
   grouping and progressive disclosure. Security guidance reinforces server
   authority and privacy. Do not invent a blended visual skin.
2. **Keep one app and one component language.** Adapt role priorities through
   capabilities, scope, filters and saved views. Reuse shared components and state
   vocabulary across every feature; do not build a different mini-app per role.
3. **Keep every feature reachable.** Simplification changes hierarchy and
   disclosure, not capability. Keep frequent work direct; put secondary/advanced
   details behind labelled menus, disclosures or sheets. Do not add a menu step
   to a frequent action just to make the screen emptier.
4. **Respect canonical ownership.** The Swift app is a thin client of existing
   domain/API contracts. Client permissions are presentation, never authorization.
   Preserve tenant, object, capability, revision and relationship checks. Example
   entities, capability names and endpoints in the supplied research are concepts,
   not permission to replace actual contracts or invent server fields.

## Field workflow and navigation

5. **Design for the person beside the work.** Each main field screen should make
   place, problem, next action and saved/sync state understandable immediately.
   Lead job identity with the real address/place when available, then the problem;
   time, technician and status support it. Keep database IDs secondary. Never
   fabricate an address, ETA, coordinate, unread count or operational fact.
6. **Keep navigation shallow and native.** Use system tabs, navigation stacks,
   back/swipe-back, sheets, search, safe areas and adaptive window behavior.
   Jobs/Today is the field-work home direction; Current/Arrive, Inbox and Search
   are meaningful destinations. Preserve existing routes while deliberately
   aligning navigation; the sample tab diagram is not a completed migration.
   *Redesign, 31 October 2026 (drawer, simplified after build 125):* the iPhone
   navigates with a side drawer in the style of the Claude and ChatGPT iOS apps;
   the floating tab bar and the More screen are gone. The drawer is reachable from
   every screen of a place: roots lead their header with a round menu circle at
   top left (their own circles — filter, + — stay right), and pushed screens (job,
   customer, estimate, invoice, …) show the same circle at top left with a compact
   back chevron beside it. An edge swipe opens the drawer on roots only; on a
   pushed screen it stays Back. Sheets, full-screen covers and customer mode never
   show the circle. Picking a place opens it (the place showing returns to its
   root); every place keeps its own stack, so a job left open is still there when
   the person comes back. The drawer is about 80% of the screen and pushes the
   place right as a slightly dimmed card with the device's corner radius, a soft
   shadow and a hairline edge in dark mode, on a gentle spring (Reduce Motion
   fades). *v2:* the drawer is an owner-approved exception to "iOS is a tab bar
   and a stack"; it wears the v2 tokens — the panel tone, a modest 17pt Medium
   business name, Medium place words in body grey that lift to cream for the
   place showing, and place marks in soft hues, outlined at rest and filled for
   the place showing (no wash on the row). Keep it calm — it lists only: the business name (one
   line) and a search circle; at most five places for the person's role (no
   header; about 44pt rows) — technicians Today, Jobs, Customers, Inbox; office Schedule, Jobs,
   Customers, Money, Inbox; owners Home, Jobs, Customers, Money, Inbox (Home
   carries the day, so the schedule sits under All places rather than a second
   "today" row); then "All places", which folds every other place and the records
   kept on this phone in and out in place (16pt words, remembered on the phone).
   Places pinned in Edit menu join the list while it has room and only then form
   a small Pinned section. Recents lists up to five jobs and customers as plain
   words, with a `StatusLabel` (mark and word) only on a job under way. Only two dots exist: unread
   Inbox, and saved work that needs the person (on the gear); the menu circle wears
   a dot for either. At the bottom a 48pt ink "New job" capsule (long press for
   the other creates) sits left and a gear circle right (business switcher, saved
   work, Add a business, Settings, Edit menu). The current job leads Today, and
   saved-work status stays on the screens' banner and the gear and menu circles'
   VoiceOver values — neither is a drawer row. At accessibility sizes the drawer
   is full width with its own close circle. VoiceOver: the circle reads "Menu",
   the open drawer is a modal group that the escape gesture closes, and focus
   moves to the drawer and back. iPad at regular width keeps its sidebar.
7. **Match the surface to the task.** Durable job/customer/site/equipment/document
   records belong in navigation destinations. Assignment, payment and completion
   are focused transactions. Small local choices use native menus/pickers;
   contextual information uses a sheet/inspector. *v2:* one local choice is an
   anchored popover (`ThorbisMenu`), one task is a modal sheet (`ThorbisModalSheet`). Use full-height editing when
   text entry needs room. Maps supplement a usable list.
8. **Give each step one dominant action.** Keep the action, consequence and amount
   clear. Preserve its label and geometry during progress. Secondary actions stay
   quieter. Guided work is sequential but escapable; ordinary Back remains native.
   Never auto-advance a reader or make a required action gesture-only.
9. **Use planar work surfaces.** Establish hierarchy through alignment, proximity,
   type and spacing before borders, shadows or cards. Group lists rather than
   creating an equal-button dashboard. Reserve cards for bounded objects such as
   media or a financial summary. Status is always a word, with color/symbols as
   reinforcement. Keep list scope, filters, position and saved views on return.
   *v2 (31 October 2026):* grouped sections are the norm — a 13pt Medium section
   header with its count above rows on one panel (`Theme.well`, radius 14), with
   no line between rows and no box around the group (`Well`, `WellList`,
   `SectionHeader`; `WellDivider` now draws nothing). Rows lead with the street and
   carry the status as a word with its small mark (`StatusLabel`). Avatars
   (`InitialsAvatar`, in place-mark hues) and pill chips (`PropertyChip`, a 1px rim)
   are allowed.

## Visual and interaction system

10. **Use semantic tokens and shared components.** Keep light, dark, system,
    increased-contrast, disabled and focus states consistent. Use the existing
    Thorbis palette and official logo. The 4/8/12/16/24/32/48 spacing rhythm and
    approximate content radii are semantic guidance, not scattered constants.
    Respect native margins and Paper geometry; document a needed adaptation.
    *v2, 31 October 2026 — supersedes the earlier neutral palette:* the
    design.thorbis.com tokens above (Linear dark greys, the warm cream light
    sheet, one electric-blue accent, olive/forest/pumpkin/burnt place marks),
    weights 400 and 500 only, and the compact staff ramp with no 34pt step. Status
    hues (`Theme.status*`) each have a mark colour, a text-safe colour and a
    tinted surface. `scripts/tests/contrast.py` and `AppearanceTests` hold every
    text token at 4.5:1 and every mark at 3:1 in light, dark and Increase Contrast.
11. **Let system chrome be system chrome.** Use native typography and geometry in
    tabs/toolbars/navigation. Use accessible Inter and the existing money/mono
    styles in content. Liquid Glass belongs to supported system navigation/action
    chrome; do not coat static forms/cards in glass or imitate unavailable APIs.
    Our sheets and popovers set `presentationBackground` to the panel, so iOS 26
    never wraps them in glass.
    *User direction, 30 October 2026:* navigation and action buttons use Thorbis
    custom controls, not the system's default buttons — the round back
    (`ThorbisBackButton` via `thorbisDestination`), round icon circles
    (`PaperCircleButton`/`PaperCircleLabel`, `ThorbisMenu`) and the text pill
    (`ThorbisToolbarItem` + `ThorbisBarButtonStyle`) for Done/Cancel/Save. System
    navigation behaviour stays native: the navigation bar, swipe-back, sheets and
    their dismissal. Do not add stock bar buttons or `ToolbarItem` without the
    Thorbis wrapper.
12. **Scale and reflow.** Use Dynamic Type and semantic text styles/metrics;
    never transplant fixed desktop 12/13/14px type into essential phone content.
    Keep the same information architecture across appearances, phone widths and
    iPad windows. Descriptions and important text wrap; reserve media geometry.
13. **Keep targets comfortable.** Staff controls have at least 44pt nonoverlapping
    hit regions. CustomerPresentation retains its stronger 56pt target floor,
    17pt smallest text, 20/22pt body and 34/40pt totals. Use current shared styles
    rather than shrinking them to match a static screenshot.
14. **Use native symbols and restrained feedback.** SF Symbols are the default;
    give icon actions accessible names and consistent optical weight. Preserve
    system transitions. Custom microstates should be fast and purposeful, honor
    Reduce Motion and avoid ornamental delays. Combine words/visuals and optional
    haptics; no toast or haptic alone proves a consequential operation succeeded.
15. **Make access and language first-class.** Test VoiceOver order, Voice Control
    names, focus restoration, large text, Increase Contrast, Reduce Motion and
    alternatives to color/maps/gestures. Use String Catalogs and locale-aware
    dates, currencies, units, addresses and plural forms. Localize full sentences
    and support RTL; keep machine timestamps/codes normalized internally.

## Offline, data and recovery

16. **Make cached work useful immediately.** The target architecture is a durable
    tenant/actor-scoped local read model with a transactional mutation outbox.
    Where a workflow is not yet supported offline, say so honestly. Do not claim
    an offline implementation from a memory cache, spinner or optimistic label.
17. **Make saved state truthful.** Local saved, queued, sending, server-confirmed,
    stale, partial, failed, conflicted, authentication-expired and offline are real
    states. Pending completion says “Done locally · Sync pending”, not simply
    “Done”. Never present an unloaded history as empty or zero.
18. **Keep writes recoverable and idempotent.** Reuse canonical stable operation
    IDs, revision preconditions, durable receipts and retry semantics. Persist
    local work and its pending operation atomically where the domain supports it.
    Do not change an uncertain payment's idempotency identity during a retry.
    Use cursor/delta synchronization and bounded payloads, not full-workspace
    downloads as a substitute for a defined sync contract.
19. **Resolve the actual conflict.** Preserve notes/photos and nonconflicting
    work. Explain the changed fact and required choice. Append independent
    evidence where safe; version-check contacts, assignment and financial edits;
    let the server validate status transitions. Signed evidence is immutable.
    Do not silently use last-write-wins for consequential records.
20. **Treat background work as opportunistic.** Use supported background tasks
    and transfer APIs without assuming exact execution times. Record metadata and
    attachment transfers have separate durable progress. Captured media appears
    locally with an upload state, survives interruption and remains job-bound.
21. **Put recovery beside the failure.** Field error beneath the field, row retry
    beside the object, persistent page banner for offline/partial state, focused
    transaction recovery for payment failure, and proper sign-in recovery for an
    expired session. Name the next useful action. Preserve drafts and work across
    transient failure; do not hide information behind a generic error toast.

## Customer documents, money and evidence

22. **Hand over only the current job.** Customer mode exposes every verified
    estimate and invoice for that job, with all-document overviews, explicit
    navigation and swipe convenience. Let the customer select and approve
    multiple independent estimates in one continuous handoff. Keep already
    approved estimates visible without approving them again; retain each
    document's required review, signature and consent. Complete package choices
    within one estimate retain their own selection rules. Show each invoice's
    own dated payments/refunds, original discount/credit descriptions, total,
    paid amount and remaining balance. Keep separate documents and complete
    package choices distinct; do not imply their totals are automatically one bill.
23. **Keep customer decisions explicit.** Show exactly what is being accepted and
    the full price before consent/signing. Use current issued revision/hash and
    canonical server quote/acceptance where required. Choosing an option or extra
    is not approval. No preselected extras; a change invalidates prior review and
    consent. Retain Back, Not today, clear confirmation and authenticated staff
    hand-back. Keep signature drawing outside document-swipe navigation.
24. **Preserve financial authority.** Use checked integer minor units and labelled
    amounts. Distinguish discounts from credits and received payments from new
    collections. Verify exact invoice/tenant/history identity and reconciliation;
    partial/refunded/pending/failed are distinct states. No false success, duplicate
    charge or client-authored billing authority. Offline money/signing is permitted
    only under an existing verified domain contract. Tap to Pay and other provider
    gates remain in force until separately qualified.
25. **Keep evidence immutable and private.** Bind signatures to signer, exact
    document/version, timestamp and audit context. Keep costs, margins, internal
    notes, provenance, provider IDs and other jobs out of customer mode. Payments,
    signatures and important state changes need durable server evidence, not just
    transient presentation. Validate jurisdiction-specific requirements separately.

## Capture, privacy and quality

26. **Keep forms purposeful.** Persistent labels, appropriate keyboards,
    optionality, example placeholders and inline validation on blur/commit. Small
    choices stay small; large technician/customer sets get searchable selection.
    Reuse real system capabilities rather than asking for avoidable manual input.
27. **Request permission when needed.** Camera for Take photo, system Photos
    picker for choosing media, microphone only for audio/video, notifications
    after their value is clear, location When In Use by default and precise/Always
    access only for a justified supported workflow. Denial has a usable recovery
    path. No broad permission bundle at first launch.
28. **Protect data through its lifecycle.** Keychain for small secrets; protected,
    minimized local business data; ATS-compatible transport; bounded media URLs;
    authoritative server authorization/audit; session revocation and cache/outbox
    cleanup under the existing policy. Never replace actual Better Auth/session
    contracts with the source's conceptual OAuth example merely for consistency.
29. **Interrupt sparingly and measure privately.** Notifications name a meaningful
    assignment/schedule/message/approval change and lead to durable in-app state.
    Live Activities represent active time-bounded work. Analytics measure workflow
    health and failures; exclude names, addresses, notes, photos, signatures,
    tokens and unnecessary precise location. Keep logs redacted and privacy
    disclosures aligned with actual collection and included SDKs.
30. **Make performance measurable.** Target cached Today usefulness < 500ms,
    cached job opening < 300ms, local status feedback < 100ms, local search < 100ms,
    thumbnail feedback < 500ms and healthy sync acknowledgement around 2s without
    blocking local work. These are product targets, not Apple requirements or
    measured achievements. Profile representative devices/data, scrolling,
    lifecycle, battery and memory; use available diagnostics appropriately.
31. **Prove behavior and presentation.** Use relevant unit, persistence, sync,
    API/authorization, native journey, accessibility, localization, network-chaos,
    lifecycle and permission tests. Test representative many-record datasets,
    sunlight/one-handed field use and supported phone/iPad sizes. Automated audits
    complement manual assistive-technology/device checks.
32. **Ship honest, useful increments.** Record what changed, bugs reproduced/fixed,
    screenshots, checks, gaps and release risks. Add user-facing release notes.
    Upload useful verified TestFlight batches; verify processing and intended
    tester access. Build/test/merge/upload/exposure are different facts. Never call
    the entire app complete from one screen, preview or passing test suite.

## Applying research to this repository

- Platform/version claims in the imported source, including iOS 27 wording, are
  research claims to verify against official documentation and the installed SDK.
  They do not raise the deployment target or authorize dependency changes.
- The source's sample data models, wrapped error JSON, sync endpoint, auth flow,
  role/capability names and framework options are illustrative. Preserve actual
  domain owners, schemas, Better Auth, RFC9457 problems and guarded commands.
- General 44pt/16pt/approximate-radius guidance never lowers a more specific
  accessible customer rule or replaces a measured Paper/shared native component.
- Existing unsupported fields, offline workflows and unqualified payments stay
  explicit gaps, with accountable follow-up; do not draw working-looking controls
  or claim conformance before implementation and verification.

The full reference remains available for details. A future deliberate change to a
golden rule updates this document, its process and affected shared components in
the same review; avoid accumulating conflicting instructions in feature files.
