# Thorbis Mobile source and coverage

Source: [current Thorbis Mobile page in Paper](https://app.paper.design/file/01KY0S86CYXENWSH216F3ZB058/B-0), token hash `2803f4aa`, exported 2026-10-26. JSON files contain original Paper JSX, not hand-measured screenshots. Inter and Geist Mono are bundled with their OFL licenses.

## Implemented presentation

- Shared colors/type, compact screen headers, pill navigation, workspace drawer, search and settings presentation.
- Login and password-reset request; schedule and empty state; jobs and a Paper-styled My Day list; customer list/detail with contact create/edit, primary promotion and removal plus service-location management; job overview/media/activity/estimate/invoice tabs; price book; new-job composer; estimate/invoice detail, estimate creation, and a Paper-aligned estimate revision and option-package editor.
- iPad schedule: 244-point sidebar, 350-point list, selected detail pane. Narrow windows fall back to compact navigation.
- Production screens use live records and retain capability checks, revision preconditions, and existing mutation handlers. OS safe areas/status bars replace static OS chrome in the artboards.

## Not full design or product parity

The page contains 133 artboards, including unimplemented workflows and several empty iPad frames. Build 3 does **not** constitute an exact match to every artboard or parity with the full TanStack product.

- Google/Apple sign-in and self-service signup in Paper have no supported staff native flow here. Login retains email/password and a real reset request; account invitation remains administrator-managed.
- Schedule records lack coordinates/address/ETA, so map/navigation/ETA controls are not fabricated. Customer list uses real job counts rather than invented addresses.
- Native messaging is device-local drafts, not delivered team chat; offline PowerSync remains unconfigured. No fake unread or offline-working badges.
- Time clock, receipt/material scanning, onboarding/setup, role dashboards/payroll, vendors/POs, inventory/maintenance and other separate-product flows are not implemented by this presentation change.
- Customer billing/history/notes and some job commercial summaries have no loaded native contract. These display honest unavailable states instead of sample balances/history.
- The scheduling flow now uses Paper's native date/time sheet; its evidence and server constraints are in [schedule-sheet.md](schedule-sheet.md). Customer contact create/edit reuses the Paper sheet grammar, and customer rows support primary promotion and confirmed removal. Service locations use the same Paper sheet grammar for create/edit and support removal, validated coordinates, and server-backed access/parking fields. Paper has no dedicated contact or location editor artboards, so those forms follow the shared Paper components without claiming screenshot parity to a missing design. Assignment, follow-ups, closeout, document viewing, local records and parts of media/financial workflows still retain native controls and have not all been matched pixel-for-pixel. Paper's estimate-approval and appointment-text switches have no contact-level persistence contract and are not presented as working controls.
- Financial screens retain server-backed actions only; no decorative signing/payment controls or invented tax/stock/category data.
- SF Symbols substitute for exported SVG line icons. Dynamic Type, localization, actual record lengths and device safe areas can alter geometry.

## Verification

The 2026-10-27 My Day default and 44 pt native interaction-frame evidence is recorded in [native-ui-evidence-2026-10-27.md](native-ui-evidence-2026-10-27.md). It covers the changed surfaces and leaves whole-app and physical-device checks open.

DEBUG-only `--paper-preview --paper-preview-screen schedule|jobs|my-day|customers|job|customer|menu|estimate-revision` fixtures allow populated visual checks without credentials. Every fixture request is intercepted; writes and unknown routes fail, and Release excludes the harness. Preview is visibly labeled sample data/read only. The My Day visual check is at `outputs/paper/my-day.png`; the estimate revision fixture was inspected at `/private/tmp/thorbis-estimate-revision-review-fixed.png`.

Final build/test/upload evidence belongs in `docs/release/build-3.md`. Do not claim exact whole-app parity based on the preview or passing unit tests.
