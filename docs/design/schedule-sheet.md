# Native schedule sheet

**App and audience:** Thorbis Field Management; a field technician scheduling or moving one job between visits. **Platform:** iOS/iPadOS 17+. **Profile and pattern:** Guided, native task sheet. **Reference:** current Thorbis Mobile Paper page `B-0`, artboard `RAG-0` (Schedule picker), exported in `paper-RAG-0.json`. **Design system:** design.thorbis.com.

## Behavior and layout

The job's Schedule action presents one native sheet over the current job. It follows the Paper header with a trailing close control, Today/Tomorrow/Pick date choices, four 44-point time rows (8:00, 10:30, 13:00, 15:30), two-hour window labels, and persistent Save and Cancel actions. Quick times and dates are suggestions the staff member can choose; the service does not perform calendar-availability matching. A native date picker handles arbitrary dates and a native time picker preserves custom-time entry. Selected time remains in the current calendar/time zone when the date changes. Keeping the same day preserves the selected instant through a repeated fall-back hour; moving to another day selects the first occurrence if that local time repeats. DST gaps are rejected instead of silently moving the selected time. When saving an unchanged appointment during the repeated fall-back hour, minute precision retains the selected UTC occurrence.

The Paper artboard uses a `20`-point top radius, 20-point horizontal padding, a 40-point title row, 28-point day chips, 44-point time rows, and 48-point primary action followed by a 44-point Cancel action. The trailing close control has a 44-point touch target around its 30-point visual. The iPhone sheet starts at a 430-point detent and can expand; the system grabber, safe area, swipe dismissal, and the native iPad presentation remain in charge. Dismissal is disabled while a save request is pending so the user cannot close the sheet before its result is known. Small visual chips sit inside 44-point touch targets.

On save, the native client sends the chosen instant, current IANA timezone, a two-hour arrival-window end supported by `JobScheduleRequest`, and the prior scheduled time precondition. A 409 explains that the job changed and asks the staff member to reopen and review. It never retries against a stale schedule. Once the API confirms a save, the detail immediately adopts the returned job. Store refresh returns an explicit applied/failed/superseded result; if refresh fails, the sheet remains in a confirmed, non-repeatable saved state and tells the staff member to close the sheet and refresh Jobs before changing the schedule again.

## Native evidence

Consulted 2026-10-26:

- [Thorbis Native contract](https://design.thorbis.com/skills/native): HIG-001–HIG-022; especially HIG-003, 004, 005, 006, 007, 009, 013, 015, 016, 017, 020 and 021.
- [Apple Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)
- [Apple Pickers](https://developer.apple.com/design/human-interface-guidelines/pickers)
- [Apple Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)

| Rule | Result | Evidence or remaining work |
| --- | --- | --- |
| HIG-001 | pass | App, supported OS, scope, Paper source and current Apple topics above. |
| HIG-002 | pass | Native system sheet and pickers govern presentation and input. |
| HIG-003 | pass | SwiftUI sheet, native date and time pickers, standard accessibility traits. |
| HIG-004 | pass | App-owned cancel, date chips, time choices and save have at least 44-point frames. Calendar controls are system-owned. |
| HIG-005 | pass | Schedule is a scoped task over its record; standard sheet dismissal returns to the same job. |
| HIG-006 | pass | Explicit cancel, save, visible grabber, standard swipe dismissal; swipe, close and cancel are disabled while a save is pending. No unsaved business write is discarded. |
| HIG-007 | pass | Native sheet and safe-area inset keep Save above the home indicator; tested on iPhone 17 Pro simulator. Keyboard opens only in native picker controls. |
| HIG-008 | not tested | Full Dynamic Type range and custom font scaling remain unverified. |
| HIG-009 | not tested | Buttons have action labels and selected traits. VoiceOver and Switch Control need device review. |
| HIG-010 | pass | Existing adaptive semantic palette; schedule screen inspected in dark mode. Light/high-contrast whole-app automated surface checks passed. Full screen contrast pairs still need review. |
| HIG-011 | pass | No custom motion; system sheet motion remains. |
| HIG-012 | not applicable | No haptics. |
| HIG-013 | pass | Native editing and time selection retained; errors stay in the sheet and no user input field is cleared. |
| HIG-014 | not applicable | No new permissions or sensitive-data display. |
| HIG-015 | pass | Pending save, explicit 409 conflict and confirmed-save/list-refresh failure are distinguishable. No silent retry. |
| HIG-016 | not tested | Adaptive iPad sheet and resizable-window behavior need simulator/device checks. |
| HIG-017 | not tested | System-formatted times and weekday dates; RTL and localization review remain. |
| HIG-018 | not tested | No physical-device performance measurements; no performance claim. |
| HIG-019 | not applicable | No media/capture flow. |
| HIG-020 | pass | Uses existing authorization gate, API contract, theme tokens and domain model. No new dependency or business rule. |
| HIG-021 | pass | Evidence separates simulator checks from untested runtime behavior. |
| HIG-022 | pass | No exceptions or waivers. |

## Verification

Eight schedule-selection/request tests cover local-day preservation, daylight-saving transitions including repeated fall-back instants and spring-forward gaps, the two-hour elapsed window, and the timezone/prior-schedule request. Two store-refresh tests cover its applied and failed outcomes. Full Swift 6 strict-concurrency suite: 117 tests, 0 failures, log `outputs/schedule-full-tests.log` (path relative to the iOS repository's parent output folder in this workspace).

Manual UI check: iPhone 17 Pro Thorbis Beta simulator, iOS 26.0, Debug, isolated read-only fixture. Opened the job's Schedule sheet; verified initial selected time, Today/Tomorrow selection, native Pick date calendar, trailing close, visible Save and Cancel actions, accessible selected labels, and 430-point presentation. The fixture rejects a Save with an explicit read-only error and sends no request to a server. Live server save, 409 and refresh-failure states remain covered by unit tests and code-path inspection, not live E2E. Screenshot is `../outputs/paper/schedule-sheet.png` relative to this repository.
