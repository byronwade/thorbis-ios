# Simplification audit, 2026-10-30 (BYR-1592)

Byron: "Go through and actively find ways to simplify everything: navigation, buttons, ease of
access to information, screens. As simple and basic as it can be, but still showing all the
information and all the steps. This is a technician's, owner's or CSR's dashboard, but they must be
able to present information to the customer quickly and easily: all the estimates, display stuff,
show a catalog of items the customer can select from, show the customer's information so the
customer can edit it, same with invoice information."

Audited `origin/release/104-integration` at `b596565`, read-only. Rules cited: golden rules
([ios-golden-rules.md](ios-golden-rules.md), "GR-n"), the [modern pass](2026-10-30-modern-pass.md)
("MP-n"), and the design.thorbis.com families already used in code and the
[2026-10-28 audit](ux-audit-2026-10-28.md): MA (mobile app), CP (customer presentation), TF
(technician flow), JS (job screen).

Evidence: every `--paper-preview-screen` in `PaperPreview.swift` (65 names) captured on iPhone 16e
(DEBUG preview data), plus two flag variants. Tap counts below are **derived from code paths**
(`AppBottomBar`, `AppMenu`, `JobMenu.groups`, `PaperJobDetailView.primaryAction`), not measured on a
device. This doc does not overlap the in-flight custom-button and job–customer-linking work; where a
finding touches those files it says so.

Already planned elsewhere and **endorsed, not re-ranked here**: modern-pass "Next passes" (collapse
the job header on scroll, fold Estimates into Invoice as "Money", customer Call/Text/Directions with
Email in •••, list search in the bottom drawer, one-column forms with the save above the keyboard,
larger customer option cards). Findings below extend those where the screenshots show more.

---

## 1. Role journeys

Default bar for every role today: **Schedule · Jobs · Customers · [switcher]**, then round **Search**
and **+**. Everything else is in the pop-up menu (switcher tap, or tap again). A company layout from
the server can replace the tabs (`MenuLayout.refreshCompanyLayout`), but the built-in default is the
same for all roles.

### Technician

| # | Task | Current path (code-derived taps) | What's in the way |
| --- | --- | --- | --- |
| T1 | Start the day | Launch → Schedule · Today (0). "Now" card carries the job's next step | Schedule Today lists **all** non-closed jobs for the day (`JobFiltering.schedule` ignores assignee); "mine" lives on Jobs › Assigned. Two "today" lists, neither is "my day" |
| T2 | Get to a job | Schedule → job row (1). Or current-job chip above the bar (1) | On Jobs the chip repeats the first "In progress" row directly above it; on More/menu it covers the last rows (see F9) |
| T3 | On my way / arrive / start | Job › Overview → bottom bar "On my way" (1 each). Bar only on Overview | Bar disappears on the other four tabs; on Activity/Photos the step moves into ••• (2). Directions is a separate button in the header |
| T4 | Show estimates, get approval | Job → Estimates tab (1) → **Present estimates** (1) → unlock-free handoff → customer approves → hand back (Face ID). ≈3 staff taps | Four other "show to customer" doors lead to different containers (F1). From Overview, it's ••• → Show to customer (2) and that one is **read-only** |
| T5 | Customer edits their info | Job → ••• (1) → **Customer details** (1) → customer edits → hand back → review → save | Not reachable from inside the estimate/invoice handoff; the customer must hand the phone back, tech unlocks, opens ••• again (F2) |
| T6 | Add catalog items | Job → Estimates → Add estimate / Build estimate (2) → price-book search sheet → items → Review estimate | Works for the tech. The **customer** cannot browse or pick (backend, F4) |
| T7 | Invoice and collect, with discounts | Job → Invoice tab (1) → Create invoice / Review and send (1) → Collect payment (1) → method (1) → commit (1) ≈5 | No labelled discount/credit on invoices or at collection (F12); "Get customer signature" and "Show to customer" sit in a list below the fold on invoice detail (F13) |
| T8 | Wrap up | Job › Overview bar "Wrap up job" (1) → closeout checklist | Fine when on Overview. Closeout preview errors in DEBUG (F27) |

### Owner

| # | Task | Current path | What's in the way |
| --- | --- | --- | --- |
| O1 | See how the business is doing | Bar switcher → menu (1–2) → Money (1) or Reports (1) | Money and Reports are both "numbers" places with overlapping cards (collected, approval rate); neither is on the bar by default (F6) |
| O2 | What needs me | Menu → Needs attention (2) | Not on the bar; no count on the menu row; Inbox, Needs attention and Job notices are three similarly named places (F7) |
| O3 | Find a customer | Customers tab (1) → filter circle → search; or Search circle (1) | Two different searches with different scopes (F10) |
| O4 | Reschedule / assign | Job → ••• (1) → Reschedule / Reassign (1) | Fine for one job. From Schedule there is no row-level reschedule/assign; Unscheduled is a tab inside Schedule, not something the owner sees on "Needs attention" counts |
| O5 | Approve/inspect estimates | Menu → Estimates (2) → row (1) | List is fine (search at the bottom). Estimate detail shows member price twice (F16) |
| O6 | Collect an overdue invoice | Menu → Invoices (2) → row → Collect | Fine; Needs attention also lists it (duplicate entry is acceptable) |
| O7 | Manage team / roles | Menu → Team & permissions (2) | Fine |
| O8 | Set up company, payments, menu | Menu gear → Settings sheet; or iPad "Workspace tools"; or More › Account | Three overlapping account surfaces (F8) |

### CSR / office

| # | Task | Current path | What's in the way |
| --- | --- | --- | --- |
| C1 | Take a call, find or add the customer | Search circle (1) → type; or Customers → + (New customer) | + changes meaning by tab (New job / New customer / New estimate); long-press holds the rest, which is undiscoverable (F11) |
| C2 | Book a job | + (1) → New job sheet → Customer / When / Tech chips → Create | Sheet opens on an empty title; Customer chip is not first though customer is what a CSR has (F21) |
| C3 | Fill unscheduled work | Schedule → Unscheduled tab (1) → job → ••• → Schedule (2) | Three taps per job; no "Schedule" action on the row (F15) |
| C4 | Reassign | Job → ••• → Reassign (2) | As O4 |
| C5 | Read job notices / assignments | Menu → Inbox (2) | Name collides with "Job notices" (settings) (F7) |
| C6 | Send an estimate | Estimate detail → Send estimate (bar) | Fine |
| C7 | Customer updates details on the phone | Customer → **Customer review** (bottom-left) | Button reads "Customer review", menu reads "Show to customer", VoiceOver reads "Show to customer", job ••• reads "Customer details" — one action, four names (F2) |
| C8 | Draft a message | Menu → Message drafts (2) | Fine, but sits in the menu next to server places with no "on this phone" cue on the row itself (F19) |

---

## 2. Navigation map

**iPhone** (`PaperNavigation.phoneShell`, `AppBottomBar`, `AppMenu`)

| Destination | How it's reached | Notes |
| --- | --- | --- |
| Schedule (Today/Week/Map/Unscheduled) | Bar tab | `my-day` preview == Schedule › Today (duplicate name) |
| Jobs (Assigned/All jobs/Recent) | Bar tab | Overlaps Schedule › Today for a tech |
| Customers | Bar tab | |
| Needs attention, Inbox, Estimates, Invoices, Billing schedules, Price book, Money, Reports, Team & permissions, Job notices, Message drafts | Menu (switcher) → row; switcher slot remembers the last one | Inbox = notices feed; Job notices = who-gets-notified settings |
| Fleet, Equipment, Agreements | Menu → "On this phone" rows (`LocalWorkspaceSection`) | Device-only records next to server records |
| Settings (sheet) | Menu gear; More › Account rows | |
| Search | Search circle; menu "Search" row | Menu row duplicates the circle beside it |
| Customize menu | Menu "Edit"; More › Account; Settings | Three doors |
| What's new | Auto sheet; More; Settings | Three doors (fine for a rare item) |
| More (`MoreView`) | `primaryTab = .more` (local sections push here) | Visually identical to the menu (`menu`/`more` previews match) |
| Job → Overview/Estimates/Invoice/Photos/Activity | Push from any list, search, chip, recent | Five tabs; header repeats on every tab |
| Job ••• | Visit (transitions, Reschedule, Add to Calendar, Assign) · Money (Create invoice, Deposit) · Finish (Wrap up, Follow-ups) · Record (Show to customer, Customer details, Email, Copy ID) | Customer hand-off is in the last group |
| Customer → Overview/Jobs/Records/Activity | Push | "Customer details" is a collapsed disclosure inside Overview |
| Estimate detail, Invoice detail, Billing schedule | Push from lists, job tabs, attention | |
| Customer mode containers | see §4 | Five entry points, three containers |

**iPad** (`sidebar`, width ≥ 1000): Search, Schedule, Jobs, Customers, Message drafts, Price book,
**Workspace tools** (opens Settings), account. Estimates, Invoices, Needs attention, Money, Reports,
Team are not in the sidebar and the person's Customize menu layout is not applied.

**Duplicates**: Schedule Today vs Jobs Assigned; menu vs More; Settings vs More › Account; Search
circle vs menu Search row; Money vs Reports; Inbox vs Job notices (name); five "show to customer" doors.
**Dead ends / stale**: `side-menu` and `side-menu-search` previews render the pop-up menu (the side
menu is gone); `job-assign` preview renders Schedule; `job-closeout` renders "This request is not
part of the design preview"; `invoice-payment-refund-form` stays on "Opening your workspace…";
`estimate-draft-detail` and `public-estimate` needed a second launch to render.

---

## 3. Ranked findings

`[B]` = needs a backend contract; do not fake it in Swift (GR-4, GR-24).

| # | Screens | Problem | Simpler design | Rule |
| --- | --- | --- | --- | --- |
| F1 | Job ••• "Show to customer", Job › Estimates "Present estimates", Estimate detail "Show to customer", Invoice detail "Show to customer", Customer "Customer review" | One idea — hand the phone to the customer — has five doors, three containers (`JobCustomerDocumentsView` read-only book, `JobEstimateHandoffView` multi-approve, `CustomerEstimatePresentation`/`CustomerInvoicePresentation` single doc) and the same label means different things. The read-only book is what Overview's ••• opens, so the tech can open the version where the customer *can't* approve | One **Customer view** entry per job, promoted out of ••• to a visible header button next to Call/Text. It opens one container whose home lists every estimate (approve one or many, already-approved stay visible), every invoice (detail, payments, sign), and "Your details". Estimate/invoice detail "Show to customer" deep-link into that same container on that document. Retire the separate read-only book as an entry (keep its browsing as the home list) | GR-22, GR-7, GR-3, MP-6 |
| F2 | Job ••• "Customer details", Customer "Customer review", all customer-mode containers | Self-edit is a separate cover. Inside estimate/invoice handoff there is no way to "fix my email"; the customer hands back, the tech unlocks and re-opens. Four labels for one action | Add **Your details** as a row on the Customer view home (F1), running the existing `CustomerSelfEditView` draft/hand-back review. One label everywhere: "Customer view" (staff side) and "Your details" (customer side) | GR-22, GR-2, CP |
| F3 | Job header (all five tabs) | Customer link, title, status, time, tech, Member pill, Balance due card, Call, Text, Directions all repeat on every tab; on Invoice the $340 appears in the header and the row below it; Activity's composer starts ~60% down the screen | Header shows place/title/status once; on non-Overview tabs collapse to one line (title · status). Balance due only on Overview and Invoice-as-summary, never twice. Call/Text/Directions become one row of three equal circles (extends modern-pass "collapse on scroll") | GR-5, MP-5, MP-2 |
| F4 | Customer mode | Customer cannot browse a catalog or pick optional extras; no screen exists | Ship only after BYR-1580 offers/quote/acceptance: customer "Add-ons" step inside an estimate, nothing preselected, quote recomputed server-side. Until then, show nothing — no client-only cart `[B]` | GR-23, GR-4 |
| F5 | Schedule Today vs Jobs Assigned; `my-day` | Two near-identical "today" lists; Schedule ignores assignee so a tech sees the whole company's day | Make Schedule › Today role-aware: technicians default to **Mine** with a one-tap "Everyone" toggle; Jobs keeps the board (All/Recent) and drops "Assigned". Rename the tab "Today" for technicians via the company layout | GR-6, GR-2 |
| F6 | Default bar | Same Schedule/Jobs/Customers for every role; owners' Money/Attention and CSRs' Inbox/Unscheduled are 2 taps deep | Role defaults when no company layout exists: Tech = Today · Jobs · Customers; CSR = Schedule · Customers · Inbox; Owner = Today · Needs attention · Money. Still customizable (`MenuLayout.maxTabs` 4). Uses existing capabilities only | GR-2, GR-3, GR-6 |
| F7 | Menu: Inbox, Needs attention, Job notices | Three places with overlapping names; "Inbox" subtitle "Job notices and assignments" collides with "Job notices" (a settings page) | Rename **Job notices → Notification rules** and move it into Settings › Workspace. Keep Inbox (feed) and Needs attention (work). Show a count on Needs attention's row when known | MP-7, GR-17 |
| F8 | Settings sheet, More › Account, iPad Workspace tools | Company, Customize menu, What's new, sign-out in two or three places; iPad calls it "Workspace tools" | One **Settings** (account, company, payments, customize, what's new, sign out). More keeps only places. iPad sidebar row says "Settings" | MP-7, GR-2 |
| F9 | Current-job chip on Jobs, More, menu | Chip duplicates the first In-progress row on Jobs and covers "What's new"/account rows on More; MP rule "nothing overlaps" | Hide the chip on Jobs when the job is visible in the list; reserve its height as bottom inset on every root that shows it | MP goal, GR-9 |
| F10 | Search circle, Customers filter circle, Schedule filter circle, Jobs field | Schedule's circle is a filter glyph labelled "Filter schedule" but toggles a **search** field; Customers same; Jobs has an always-on field; global search is the round button | One search: the bottom-bar Search. List headers keep a real **filter** (status/assignee) only. Remove per-list search toggles; global results scope to the current list first (extends modern-pass "search into drawer") | MP-2, MP-5, HIG labels |
| F11 | Bar + | Meaning changes by tab; the other create actions hide in long-press | + always opens a small menu: New job, New customer, New estimate (permission-filtered). One tap more for the default but discoverable, no hidden gesture | GR-8 ("never gesture-only"), GR-3 |
| F12 | Invoice editor, Collect payment | No labelled discount/credit on invoices or at collection; estimate editor has credit lines behind `estimate.discount`; invoice editor accepts signed prices with no discount wording | Add "Add discount" (description + amount) to the invoice editor and show it as "Discounts and credits" (the customer invoice already renders that row). Confirm the invoice-lines contract accepts credit lines and the capability name first `[B]` | GR-24, GR-22 |
| F13 | Invoice detail | Signature is a row; "Show to customer" and "View PDF" sit under an "Actions" header below the fold; collect is a footer only on the job tab | Bottom bar carries the one next step (Send → Collect $X → Get signature); everything else in •••. Same grammar as estimate detail | MP-6, GR-8 |
| F14 | Job tabs (5) | Overview/Estimates/Invoice/Photos/Activity; Photos and Activity both hold visit evidence | Endorse modern-pass **Money** (Estimates + Invoice). Merge Photos into Activity as a filter chip ("Photos") with the camera button kept → 3 tabs: Overview · Money · Activity | GR-9, MP |
| F15 | Schedule › Unscheduled, Week | Scheduling a job is row → job → ••• → Schedule (3) | Rows on Unscheduled get a trailing "Schedule" button and long-press Assign; same sheet as today (`showSchedule`) | GR-3, GR-7 |
| F16 | Estimate detail | Total $970 and Member price $824.50 stacked on the right inside the lines card, plus the big $970 total above; option totals repeat | One amount per side: "Total" big at top (member price as its supporting line when member), lines card ends at its subtotal. Same on the public estimate page: $1,575 at the top and again as "Estimate total"; its "Choose an option to approve" commit sits disabled before any option is on screen | MP-4, MP-5, GR-24 |
| F17 | Job header pills | Member · 15% off is a pill but neither tappable nor a status | Plain text fact with a star in the customer line ("Danielle Marlowe · Member") (modern pass already plans "Member into the customer line") | MP-3 |
| F18 | Customer detail | Address, phone, email are behind a collapsed "Customer details" disclosure; Call/Text/Email/Directions above; two commits at the bottom (Customer review, New job) | Show the details as a quiet always-open list (address first); keep 3 action circles; one bottom commit **New job**, Customer view in the header (F1) | GR-5, MP-6 |
| F19 | Menu "On this phone" (Message drafts, Fleet, Equipment, Agreements) | Device-only records sit as peers of server places; only the group header says so | Keep, but the row subtitle reads "On this phone · not shared" and the screens carry the existing local-only banner | GR-16, GR-17 |
| F20 | Menu | "Search" row duplicates the Search circle next to it | Drop the row (the circle stays) | MP-5 |
| F21 | New job sheet | Opens on an empty title; Customer / When / Tech are small chips after the description | Order by what a CSR has: Customer (search) → Problem → When → Tech; create stays at the bottom | GR-26, MP forms |
| F22 | iPad sidebar | Different place list than phone; Estimates, Invoices, Attention, Money, Reports, Team only reachable via "Workspace tools"; Customize menu ignored | Sidebar = same `menuPlaces` as the phone menu, grouped Work/Business/On this phone | GR-2, GR-12 |
| F23 | Money vs Reports | Two "numbers" screens; both show collected/approval/jobs | One **Business** place with Money · Operations · Schedule tabs (Reports already has tabs) | GR-9 |
| F24 | Collect payment | Card link, Check, Cash, Other are a good list; Tap to Pay stays gated | No change in shape; Tap to Pay stays a provider gate `[B]` | GR-24 |
| F25 | Customer presentation, choose step | "Choose Repair" control is a secondary-style button inside each card and the commit "Choose an option" is disabled below | Make the whole option card the tap target (56pt+) with price first (endorses modern-pass "larger option cards") | CP, GR-13 |
| F26 | Follow-ups | Segment "Notify office / Schedule a return visit" then two empty fields; disabled grey commit | Fine structurally; label the fields above, not as placeholders (endorses modern-pass forms pass) | GR-26 |
| F27 | DEBUG previews | `side-menu*` stale; `job-assign`, `job-closeout`, `invoice-payment-refund-form` don't render their screen; `--paper-preview-job-documents` shows the plain job (the cover needs a tap) | Fix or drop these names so future audits capture real screens | GR-31 |
| F28 | Approvals across several estimates → invoice | Approving a second estimate on a job doesn't flow into one bill | Requires accepted-additions and bill-once authority (BYR-1580) `[B]`; keep separate documents visibly separate until then | GR-22, GR-24 |

---

## 4. Customer-presentation gaps

| User asked for | Exists today | Entry points (exact) | Gap |
| --- | --- | --- | --- |
| **All estimates** for the job | `JobEstimateHandoffView`: list every verified estimate, select several, review, sign each; approved ones stay visible. `CustomerEstimatePresentation`: one estimate, choose option → review → sign | Job › Estimates tab bar **Present estimates**; job Overview bar when step is `.presentEstimates`/`.showEstimate`; Estimate detail bar **Show to customer** (draft on a job is issued on hand-over) | Not reachable from Overview except via ••• → Show to customer, which opens the **read-only** book. Make one Customer view (F1) |
| **Display stuff** (job documents) | `JobCustomerDocumentsView` "Your job documents": estimates + invoices, swipeable book, invoice signing and "hand back to pay" | Job ••• → **Show to customer** (Record group, last) | Buried in •••, read-only for estimates; becomes the home of Customer view (F1) |
| **Catalog the customer selects from** | Technician-only price-book search in estimate/invoice editors. Customer side: none | — | Needs BYR-1580 offers, server quote and acceptance guard `[B]` (F4). No client cart |
| **Customer edits their info** | `CustomerSelfEditView`: customer edits name/phone/email/address/preferences; staff unlock, review diff, audited save | Job ••• → **Customer details**; Customer page bottom **Customer review** (VoiceOver: "Show to customer"); Customer ••• **Show to customer** | Not inside the estimate/invoice handoff; four labels (F2) |
| **Invoice information** | `CustomerInvoicePresentation`: lines, Total, Amount due, Sign for the work, Done; book shows dated payments/refunds and "Discounts and credits" | Invoice detail **Show to customer** (under Actions, below fold); job ••• Show to customer → invoice in book | No discount *entry* on invoices (F12 `[B]`); collection stays staff-side by design (correct) |
| Payment in front of customer | Collect payment: send link, check, cash, other; refunds with pending/reconciliation states | Job › Invoice footer **Collect payment**; Invoice detail | Tap to Pay gated `[B]` |

---

## 5. Batches

Ordered so each is one PR, independent of the in-flight custom-button and job–customer-linking work
(if those land first, rebase; F3/F17 touch the job header both may edit).

**Batch A — Customer view, one door** (F1, F2, F18 header button, F25)
Job header gets "Customer view"; one `CustomerModeContainer` home listing estimates (handoff model),
invoices (book), and Your details (self-edit). Estimate/invoice "Show to customer" deep-link into it.
Customer page: details open, one commit. Files: `PaperJobDetailView.swift`, `JobBrief.swift`
(`JobMenu.groups`), `JobCustomerDocumentsView.swift`, `JobEstimateHandoffView.swift`,
`CustomerSelfEdit.swift`, `CustomerPresentation.swift`, `FinancialViews.swift`,
`PaperCustomerViews.swift`, `ReleaseNotes.swift`, tests for handoff scope/hand-back.

**Batch B — Navigation by role** (F5, F6, F7, F8, F20, F22, F23)
Role-aware Today, role default bars, one Settings, rename Job notices, sidebar mirrors the menu,
Money+Reports as Business. Files: `MenuLayout.swift`, `AppMenu.swift`, `PaperNavigation.swift`
(sidebar, `PaperRoute`), `PaperWorkViews.swift`, `JobFiltering.swift`, `Screens.swift` (`MoreView`),
`SettingsView.swift`, `ReportsView.swift`, `WorkspaceViews.swift`, `ReleaseNotes.swift`.

**Batch C — Job screen calm** (F3, F9, F14, F17, F16)
Collapsed header off Overview, no repeated balance, chip rules, three job tabs, one amount per side
on estimate detail. Files: `PaperJobDetailView.swift`, `JobOperationsViews.swift`, `AppMenu.swift`
(`CurrentJobChip`), `PaperNavigation.swift`, `FinancialViews.swift`, `PaperComponents.swift`.

**Batch D — One search, one create, faster scheduling** (F10, F11, F15, F21, F26)
Bar search only, real filters, + menu, Schedule on Unscheduled rows, New job field order. Files:
`AppMenu.swift` (`AppBottomBar`), `PaperNavigation.swift`, `PaperComponents.swift` (`PaperHeader`),
`PaperWorkViews.swift`, `PaperCustomerViews.swift`, `Screens.swift` (`NewJobSheet`),
`JobOperationsViews.swift`.

**Batch E — Money that needs contracts** (F4, F12, F13, F24, F28) `[B]`
Invoice bottom-bar step grammar (F13) can ship alone; discount entry after the invoice-lines credit
contract is confirmed; customer add-ons and bill-once after BYR-1580 server work. Files:
`FinancialViews.swift`, `InvoiceLineEditorView.swift`, `InvoiceLineEditorState.swift`,
`InvoicePaymentCollection.swift`, `CustomerPresentation.swift`, plus API/OpenAPI changes in
`services/api`.

Housekeeping with any batch: F19 local-record subtitles, F27 preview fixes in `PaperPreview.swift`.

## Evidence

Contact sheets (local, not committed): `scratchpad/audit/sheet-01..06.png` and
`sheet-customer-money.png` from the BYR-1592 audit run. Device: iPhone 16e simulator, DEBUG
preview data. Not checked: iPad at real width, large Dynamic Type, VoiceOver order, dark mode.
