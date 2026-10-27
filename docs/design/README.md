# Thorbis Mobile source and coverage

Source: [current Thorbis Mobile page in Paper](https://app.paper.design/file/01KY0S86CYXENWSH216F3ZB058/B-0), token hash `2803f4aa`, exported 2026-10-26. JSON files contain original Paper JSX, not hand-measured screenshots. Inter and Geist Mono are bundled with their OFL licenses.

## Paper redesign (branch claude/paper-redesign)

- iPhone navigation is a native `TabView` with Paper's technician dock: Schedule, Jobs, Customers, More and a system Search tab. iOS 26 draws it as Paper's floating pill; the deployment target is iOS 18 for the search tab role. The overlay menu and the Done-sheets for Schedule and Customers are gone. Inbox, Estimates, Invoices, Price book, Revenue, drafts and on-device records live in More.
- Tab roots use Paper's 34/700 large title with a filter circle and account avatar; Paper's compact 22pt switcher title is retired (one header grammar). Segment tabs are pills; the gutter is 20 pt.
- Schedule's Next up band carries the old Arrive tab's On my way commit. Week groups by day. Paper's Map tab is replaced by Unscheduled until job records carry coordinates.
- Job, customer, estimates, invoices and price book screens use the native navigation bar (system back and swipe-back) with Paper record headers below it.
- Leading coloured rails (Next up underline, week bars, composer caret) are removed per design.thorbis.com D-018.
- Every type-ramp step scales with its nearest Dynamic Type style; lanes use `@ScaledMetric` and rows stack at accessibility sizes. `Theme.brandText` (#5285FF dark, #2558E0 light) replaces brand blue as text and tint for 4.5:1 contrast.

## Implemented presentation (before the redesign)

- Shared colors/type, compact screen headers, the native Jobs/Arrive/Inbox tab bar with More workspace navigation, workspace selector, search and settings presentation; signed-in workspace navigation uses the official Thorbis mark, while login and customer estimate headers use the mark-and-wordmark lockup.
- Login with the official Thorbis logo lockup and password-reset request; schedule and empty state; jobs and a Paper-styled My Day list; customer list/detail with contact create/edit, primary promotion and removal plus service-location management; job overview/media/activity/estimate/invoice tabs; price book; new-job composer for title, description, and customer, followed by job-detail scheduling and assignment; estimate/invoice detail, payment collection and reasoned full refunds with pending-status recovery, estimate creation, Paper-aligned estimate revision and option-package editor, and a token-scoped native customer estimate decision screen.
- iPad schedule: 244-point sidebar, 350-point list, selected detail pane. Narrow windows fall back to compact navigation.
- Production screens use live records and retain capability checks, revision preconditions, and existing mutation handlers. OS safe areas/status bars replace static OS chrome in the artboards.

## Not full design or product parity

The page contains 133 artboards, including unimplemented workflows and several empty iPad frames. Build 15 does **not** constitute an exact match to every artboard or parity with the full TanStack product.

- Google/Apple sign-in and self-service signup in Paper have no supported staff native flow here. Login retains email/password and a real reset request; account invitation remains administrator-managed.
- Manual job creation submits only the supported customer, title, and notes fields. Priority and the attachment, mention, checklist, and camera controls in Paper do not have matching job-create API fields, so the composer does not imply that they are saved. The API's `job.locationId` is organization branch scope, not a customer service-address ID; schedule and technician assignment use the existing job-detail actions after creation.
- Schedule records lack coordinates/address/ETA, so map/navigation/ETA controls are not fabricated. Customer list uses real job counts rather than invented addresses.
- Native messaging is device-local drafts, not delivered team chat; offline PowerSync remains unconfigured. No fake unread or offline-working badges.
- Time clock, receipt/material scanning, onboarding/setup, role dashboards/payroll, vendors/POs, inventory/maintenance and other separate-product flows are not implemented by this presentation change.
- Customer billing/history/notes and some job commercial summaries have no loaded native contract. These display honest unavailable states instead of sample balances/history.
- The scheduling flow now uses Paper's native date/time sheet; its evidence and server constraints are in [schedule-sheet.md](schedule-sheet.md). Customer contact create/edit reuses the Paper sheet grammar, and customer rows support primary promotion and confirmed removal. Service locations use the same Paper sheet grammar for create/edit and support removal, validated coordinates, and server-backed access/parking fields. Paper has no dedicated contact or location editor artboards, so those forms follow the shared Paper components without claiming screenshot parity to a missing design. Assignment, follow-ups, closeout, document viewing, local records and parts of media/financial workflows still retain native controls and have not all been matched pixel-for-pixel. Paper's estimate-approval and appointment-text switches have no contact-level persistence contract and are not presented as working controls.
- Financial screens retain server-backed actions only; no decorative signing/payment controls or invented tax/stock/category data.
- Paper has no dedicated estimate-signature artboard. Customer decisions use the shared Paper palette and the native HIG contract; HTTPS link activation still depends on fixing the app-domain AASA response and Associated Domains entitlement.
- SF Symbols substitute for exported SVG line icons. Dynamic Type, localization, actual record lengths and device safe areas can alter geometry.

## Verification

The 2026-10-27 native primary-tab and 44 pt interaction-frame evidence is recorded in [native-ui-evidence-2026-10-27.md](native-ui-evidence-2026-10-27.md). It covers the changed surfaces and leaves whole-app and physical-device checks open.

DEBUG-only `--paper-preview --paper-preview-screen ...` fixtures allow populated visual checks without credentials, including `invoice-payment-refund`, `invoice-payment-refund-form`, `invoice-payment-refund-confirmation`, `invoice-payment-refund-pending`, and `invoice-payment-refund-reconciliation`. Every fixture request is intercepted; writes and unknown routes fail, and Release excludes the harness. Preview is visibly labeled sample data/read only. The My Day visual check is at `outputs/paper/my-day.png`; estimate revision and customer decision fixtures were inspected at `/private/tmp/thorbis-estimate-revision-review-fixed.png` and `/private/tmp/thorbis-public-estimate-v2.png`.

Final build/test/upload evidence belongs in the versioned `docs/release/build-*.md` notes. Do not claim exact whole-app parity based on the preview or passing unit tests.
