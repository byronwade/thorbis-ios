# Job Overview simplification and accessible controls

28 October 2026 · Thorbis Field Management · SwiftUI · iOS/iPadOS 18+

Implementation starts at `7adf174`; debug marketing version 1.0, project build 17.
These changes implement the [continuous UX goal](continuous-ux-goal.md) for one
job flow and its shared controls. This record does not certify the entire app
or a TestFlight release.

## Sources

Consulted 28 October 2026: [Thorbis Native](https://design.thorbis.com/skills/native)
(D-025, HIG-001–HIG-022), [Apple Menus](https://developer.apple.com/design/human-interface-guidelines/menus),
[Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons),
and [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars).
Apple platform behavior and accessibility take priority over fixed web geometry.

## Feature access map

| Existing capability | Access after this change |
| --- | --- |
| On my way, Mark arrived, Start work | Primary action when permitted and server-allowed; all permitted transitions remain in the status menu |
| Dispatch | Job Detail primary action for a scheduled job when assignment permission and the server allow it; status menu remains |
| Pause, resume, reverse/cancel transitions | Existing status menu and handlers; permitted Resume remains primary on paused Job Detail |
| Wrap up | Primary on in-progress work; More → Wrap up at other stages; opens the existing checklist |
| Schedule / change time | Existing time chip, or More → Schedule… including unscheduled jobs |
| Assign technician | More → Assign technician… with the same assignment permission |
| Follow-ups | More → Follow-ups |
| Show to customer | More → Show to customer, with the same customer-edit capability |
| Copy ID / share | More → Copy job ID / existing Share toolbar control |
| Call, Text, Directions | Header shortcuts; vertical, scrollable rows at accessibility text sizes |
| Estimates, invoice/payment, photos, activity | Existing pinned record tabs and destinations |
| Notes, equipment, access details, customer record | Existing Overview content and links |

No API mutations were added. Closeout, pause evidence, queued-state precedence,
server transitions, and permission checks retain their existing authority.

## Automated checks

iPhone 17 Pro Simulator, iOS 26.0 (23A343), arm64, 28 October 2026:

- Baseline payment/preview checks: 57 passed.
- Action policy plus filtering, outbox and API checks: 68 passed.
- Four new hosted layout tests: failed first on fixed primary/tab/chip heights
  and unbounded FlowRow content; passed after adaptive layout changes.
- Enlarged contact-row UI test: failed first on the shared horizontal row;
  passed after vertical layout. Standard More and Wrap up navigation also pass.
- Focused action/layout/appearance/native checks: **20 passed, zero failures**.
  [Machine-readable summary](evidence/2026-10-28-job-overview/focused-tests.json).
- Full app scheme: **323 passed, zero failures, zero skipped**, including all three native UI tests and the scroll-reachability check. [Machine-readable summary](evidence/2026-10-28-job-overview/full-tests.json).
- `git diff --check`: passed. The final review is recorded below when complete.

The native tests use read-only DEBUG preview fixtures. They prove local
navigation and layout, not a successful live dispatch, payment, or closeout.
Existing Swift 6 build warnings concern widget/test fixture actor isolation
and a deprecated UITraitCollection initializer; this batch does not claim a
warning-free build.

## Native visual observations

Inspected Simulator screenshots separately from automated assertions:

- [Standard light Overview](evidence/2026-10-28-job-overview/overview-light.png).
- [Native More menu](evidence/2026-10-28-job-overview/more-menu.png).
- [Wide iPad Schedule and record](evidence/2026-10-28-job-overview/ipad-wide.png), iPad Pro 13-inch (M5), iPadOS 26.0. The raw Simulator framebuffer is rotated; the three-column view and inner More toolbar are visible.
- Largest dark text: [before](evidence/2026-10-28-job-overview/accessible-before.png)
  and [after](evidence/2026-10-28-job-overview/accessible-dark.png).

The [native scroll check](evidence/2026-10-28-job-overview/accessible-scrolled.png) confirms Directions remains reachable. The enlarged layout requires scrolling to subsequent content; the primary
action remains pinned. A screenshot alone does not establish focus order,
gesture behavior, or physical-device performance.

## Native applicability matrix

Scope and artifacts for every row: the debug app and Simulator identified
above, 28 October 2026, this branch's Job Overview, Schedule primary action,
InkCommit, PaperTabs, Chip, FlowRow, and PaperQuickActions.

| Rule | Result | Evidence or remaining check |
| --- | --- | --- |
| HIG-001 | Pass | App, platform, supported OS range, components and source receipts recorded above |
| HIG-002 | Pass | Native menu/navigation retained; fixed baseline geometry yields to Dynamic Type |
| HIG-003 | Pass | Native Menu, Button, NavigationStack, and existing schedule sheet; native interaction tests |
| HIG-004 | Not tested | Existing 44 pt hit-area wrappers retained; UI tests establish reachability, not measurement of every affected target |
| HIG-005 | Not tested | More → Schedule and Wrap up navigation verified; interactive Back, restored selections, and deep links require manual checks |
| HIG-006 | Not tested | Schedule presents and cancels natively; interruption and populated-draft recovery not manually exercised |
| HIG-007 | Not tested | Safe-area inset retained and enlarged primary visible; keyboard and rotation combinations remain |
| HIG-008 | Not tested | Four layout regressions and largest-text Job Overview pass; shared-component callers and all supported OS sizes need wider native coverage |
| HIG-009 | Not tested | Labels queried by native UI tests; VoiceOver focus, Voice Control, and Switch Control require manual checks |
| HIG-010 | Pass | Existing semantic tokens, appearance/contrast tests, standard light and enlarged dark screenshots |
| HIG-011 | Not applicable | No custom motion added or changed |
| HIG-012 | Not applicable | No haptic behavior added or changed |
| HIG-013 | Not tested | Existing input handlers retained and Schedule cancel verified; populated draft/error recovery remains |
| HIG-014 | Not applicable | No permission requests, data collection, privacy boundaries, or authorization policy changes |
| HIG-015 | Not tested | Outbox/API and action-policy tests pass; real offline/reconnect and consequential server confirmation not exercised natively |
| HIG-016 | Not tested | Wide iPad layout visually checked; resizable windows, multitasking, pointer, keyboard, and enlarged tablet text remain |
| HIG-017 | Not tested | Existing symbols retained and long labels wrap in hosted tests; localization and RTL remain |
| HIG-018 | Not tested | No representative physical-device launch/scroll/memory measurements |
| HIG-019 | Not applicable | No media, capture, decoding, or upload changes |
| HIG-020 | Pass | Shared tokens and presentation policy; existing permission gates, identifiers, API handlers and outbox retained; policy/API tests |
| HIG-021 | Pass | Automated, visual and untested evidence explicitly distinguished; unresolved checks block release certification |
| HIG-022 | Pass | No exception claimed; source receipts, review scope and retest gaps recorded; reconsult before release |

## Remaining product work

Apply the same review loop to the rest of the app without removing features.
Prioritize common job/customer workflows, estimate and invoice/payment work,
then the long tail of More and Settings. Measure access to existing commands
before relocating them. Keep frequent actions direct and use contextual menus
and disclosures for secondary detail. Complete the untested native checks
before declaring mobile release readiness.
