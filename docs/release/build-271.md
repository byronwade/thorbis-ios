# Build 271

Uploaded to TestFlight from `paper-v2-tokens` at a0719400 on 2026-11-18 (PR #563).

A crash fix, found from the Mac's crash reports while chasing UI test failures on build 270.

- Crash: `AnchoredPopover` read the key window inside `onGeometryChange`'s transform, which SwiftUI can run off the main thread while a screen slides in. The main-actor check trapped and closed the app when a screen with a top-bar menu opened (call and email threads among them). Reports go back to 2026-11-12. The transform now only reads the view's position.
- List totals (Money, Dashboard, Needs attention, vendors, member price) clamp instead of trapping on an absurd quantity or price (two reports from 2026-11-12).
- Largest text sizes: Schedule status glyph slot grows with the text; tech name and state stack; invoice line amounts and Messages times drop under the name.
- Stacked segmented choices no longer have overlapping touch areas.
- Menu counts are grouped; the unread badge caps at 999+.
- UI tests updated for the redesign (caller error label, price book picker focus, first Add item).

Not in this build: one signature for several estimates (back with its builder after a second review).

Checks: 1,375 unit tests pass (1 skipped); stock-control lint 0; large-company launch check passes for office. Six UI classes were re-run after the crash fix (65 of 66 passed, the one failure fixed afterwards and re-run). The full UI suite was still running on this code at upload. The crash is timing-dependent, so its absence in these runs is not proof. Not tried on a real phone or account.
