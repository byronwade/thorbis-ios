# Paper v2 → iOS port plan

Status: in progress (branch `paper-v2-tokens`). Written 2026-11-16.

- Phase 0 (tokens) — done, not yet built by CI. Shared components follow Paper too: screen canvas,
  20pt cards, Paper's type sizes with 34 Bold titles, blue pill commits, header circles, section
  labels with trailing counts, segments, list row sizes. Every screen built on them moves with them.
- Screen index: [paper-screen-index.md](paper-screen-index.md) (356 rows: 226 Update, 36 New,
  82 Needs API, 12 Not on iOS).
- New screens built: 67 Account and data, 68 Delete account (server refuses until it issues a
  re-authentication proof — BYR-446/449).
- Phase 1 (drawer and role menus) — done for the phone drawer: Paper's header, Search or ask,
  role order (29N/57N/58N), Tools / Manage / Business, footer with the person. Places Paper reaches
  from a hub (Estimates, Invoices, Needs attention, …) stay listed under **More** so nothing becomes
  unreachable. Not yet: iPad sidebar header/footer, Business settings row, Time clock, Truck stock,
  Receipts, Training, Pipeline, Marketing, Vendors (no screen or API yet), message unread counts.

The new "Thorbis Mobile" Paper files (about 420 phone screens, each with a tablet version, in dark
and light) replace "Thorbis — Schedule Redesign" as the Paper reference for this app. This plan says
how the Swift code changes to match them.

## 1. Navigation — bottom bar, drawer and sidebar

Bottom tabs (Paper 18A) shipped as the iPhone default on 2026-11-18 (`PhoneTabBar`: four places
for the role, then Menu (three lines), which opens the drawer). Settings › Menu and start screen › Navigation
offers the side drawer alone, and iPad keeps its sidebar. When this plan was written the code had
the drawer only. What changes below is the **contents** of the drawer and sidebar.

| Role (Paper) | Menu in Paper | In code today |
|---|---|---|
| Technician | Schedule, Jobs, Customers, Messages, Time clock · Tools: Price book, Truck stock, Receipts, Training | schedule, jobs, customers |
| Office | Dashboard, Schedule, Jobs, Money, Customers, Pipeline, Messages · Manage: Team, Vendors and POs, Properties, Equipment, Maintenance plans, Reports | schedule, inbox, customers, jobs |
| Owner | Dashboard, Money, Reports, Schedule, Messages · Business: Customers, Pipeline, Marketing, Maintenance plans, Properties, Equipment, Fleet, Vendors and POs, Business settings | home, schedule, money, customers |

Plan:
- Rename places to Paper's words (Inbox → Messages, Home → Dashboard, Billing → Business settings).
- Add the sections Paper shows (Personal / Tools / Business / Manage) in `PlaceSection`.
- Add the missing places as `MenuItem`s, gated by `permitted(session)` and the module registry, so
  a place only shows when its feature and API exist (see §4).
- **Roles:** the code derives 3 roles (technician, office, owner) from permissions. Paper has 8.
  Keep 3 base menus in code; Manager, Dispatcher and CSR use the Office menu, Apprentice uses the
  Technician menu without prices, Accountant uses Money and Reports only — all decided by
  permissions the API already returns. No new role enum.

## 2. Paper files — index them, don't merge them

Paper can't copy artboards between files, and the two base files are full. Merging would mean
rebuilding hundreds of screens by hand. Instead:
- Add `docs/design/paper-screen-index.md`: one row per Paper screen code with its Paper file,
  the Swift view or `PaperRoute`, the `--paper-preview-screen` name, and a status.
- Point `AGENTS.md` and `docs/design/README.md` at the new files and at this index.
- Freeze the two full Paper files (phone light, tablet main): text fixes only.

Status values: **Match** (code already matches) · **Update** (screen exists, layout or words
differ) · **New** (no screen yet, API exists) · **Needs API** (no route — see GAPS.md) ·
**Not on iOS** (banned by the Apple commerce rules or web-only).

## 3. Build order

Each phase is one PR (or a few), built and tested by the iOS GitHub Action, each with a What's new
entry, `--paper-preview` screen names and screenshot evidence, per ios-implementation-process.md.

1. **Shell:** drawer and sidebar contents, place names, role menus, Business settings layout.
2. **Field day (technician):** Today, Next stop, field mode steps (Driving › Arrived › Working ›
   Wrap up › Paid), job detail, photo viewer, change status, cancel job, can't start, running late,
   on break, voice note, add materials, wrap up.
3. **Estimates and invoices:** create estimate, line items, long descriptions and the text editor
   (formatting, Markdown, AI help), present, sign, send sheet, estimate/invoice/payment detail,
   discounts, revisions, customer pages (approved, paid, declined, tracking, review).
4. **Customers and messages:** customer detail tabs, linked records, conversation thread,
   new message, new/edit customer, properties, equipment.
5. **Money and office:** Money hub tabs, payments, payouts, bills, receipts, vendors and POs,
   payroll run, timesheets, time off.
6. **Owner and admin:** dashboard, reports, team, roles, invites, settings sub-screens, workflows,
   notification rules, checklists, marketing, maintenance plans.
7. **Patterns and states:** date picker, filter sheet, record picker, confirm, export, empty,
   loading, couldn't load, no access, offline.

## 4. Conflicts to settle before coding

1. **Visual tokens — decided 2026-11-16: Paper wins.** The owner chose Paper's tokens over the
   old golden-rule values: brand #2F6BFF, Inter weights up to 700, 34pt root titles, hairline
   separators inside grouped cards, Paper's dark (#1F1F1F canvas, #232323 card, #141414 sidebar)
   and light (#FAF9F6 canvas, #FFFFFF card, #F3F2EE sidebar) palettes. `Theme.swift`, the golden
   rules and the contrast/appearance tests change to match (Phase 0).
2. **Apple commerce rules.** Paper screens that sell or bill the Thorbis plan cannot ship on iOS:
   72 Subscription and billing, 15B Add payment method (for the plan), 10B Pick a phone number
   ($ monthly). They stay web-only, with an "Open on the web" line where needed.
3. **Missing API routes.** Many new screens need routes that don't exist (GAPS.md and parity):
   pipeline, marketing, workflows, banking, bills, payroll runs, vendors, call/message threads,
   customer-wide media, equipment/fleet sync. Those screens are built only when the route exists;
   until then the place stays hidden.
4. **Sample data.** Paper's sample data (Danielle Marlowe, JOB-2214, EST-1042 $340…) goes into
   `PaperPreview.swift` so previews match the designs.
