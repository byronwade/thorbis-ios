# Thorbis iOS golden rules

Adopted by the user on 28 October 2026 for the entire iOS application, including
iPad adaptations. These rules govern new features, bug fixes, cleanup and review.
They describe the required direction; they do not certify existing implementation.

> Quiet chrome. Dominant work. One obvious next action. Place before database ID.
> System UI stays native. State is never hidden. Offline work is real work.

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
   *Redesign, 31 October 2026 (drawer):* the iPhone navigates with a side drawer
   in the style of the Claude and ChatGPT iOS apps; the floating tab bar and the
   More screen are gone. Every place root (Today, Jobs, Customers, Home, Inbox, …)
   leads its header with a round menu circle at top left, keeping its own circles
   (filter, +) on the right; an edge swipe from the left opens the drawer on roots
   only, so pushed screens keep the system back swipe. The drawer pushes the place
   right as a rounded card (tap or drag it to close; Reduce Motion fades instead).
   It lists, on its own ground with no wells: the business name and a search
   circle; the job on now; Pinned — the person’s pinned places (Edit menu, up to four; role
   and company layouts still apply); Places — every other permitted place and the records
   kept on this phone; Edit menu; and Recents (jobs with their `StatusGlyph`,
   customers as words). Section labels are semibold in the primary colour. A small
   brand dot marks unread Inbox, Needs attention with items, a recent that changed
   and saved work that needs the person; the menu circle wears the same dot. At the
   bottom an ink "New job" capsule (long press for the other creates) sits left and
   a gear circle right (Settings, Edit menu, business switcher). Saved-work status
   lives on the menu circle's VoiceOver value and a drawer row that opens the
   review. At accessibility sizes the drawer is full width with its own close
   circle. VoiceOver: the circle reads "Menu", the open drawer is a modal group
   that the escape gesture closes, and focus moves to the drawer and back. iPad at
   regular width keeps its sidebar.
7. **Match the surface to the task.** Durable job/customer/site/equipment/document
   records belong in navigation destinations. Assignment, payment and completion
   are focused transactions. Small local choices use native menus/pickers;
   contextual information uses a sheet/inspector. Use full-height editing when
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
   *Redesign, 31 October 2026 (owner: "bland and hard to navigate"; target Linear
   mobile):* grouped sections are the norm — a semibold section header with its
   count above rows on one rounded well (`Theme.well`, radius 14), with inset
   hairlines between rows (`Well`, `WellList`, `WellDivider`, `SectionHeader`).
   Job rows lead with a Linear-style `StatusGlyph` in place of the trailing word:
   its shape (not only colour) carries the state and VoiceOver reads the word. The
   lead card and chips still show the word.
   Avatars (`InitialsAvatar`) and property chips (`PropertyChip`) are allowed.

## Visual and interaction system

10. **Use semantic tokens and shared components.** Keep light, dark, system,
    increased-contrast, disabled and focus states consistent. Use the existing
    Thorbis palette and official logo. The 4/8/12/16/24/32/48 spacing rhythm and
    approximate content radii are semantic guidance, not scattered constants.
    Respect native margins and Paper geometry; document a needed adaptation.
    *Redesign, 31 October 2026 — these lifted earlier rules; do not revert them:*
    the palette is crisp and neutral (light: white ground, #F4F4F5 wells,
    #63636B secondary text, 8% black hairline; dark: #0E0E10 ground, #1A1A1D
    wells, #9A9AA3 secondary) instead of the warm cream; semibold (600) is allowed
    for screen titles, row titles, section headers and amounts (bold and heavier
    resolve to 600); the ramp gains a 34pt display step for tab-root titles. Status
    hues (`Theme.status*`) each have a glyph colour, a text-safe colour and a
    tinted surface. `scripts/tests/contrast.py` and `AppearanceTests` hold every
    text token at 4.5:1 on its grounds in light, dark and Increase Contrast.
11. **Let system chrome be system chrome.** Use native typography and geometry in
    tabs/toolbars/navigation. Use accessible Inter and the existing money/mono
    styles in content. Liquid Glass belongs to supported system navigation/action
    chrome; do not coat static forms/cards in glass or imitate unavailable APIs.
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
