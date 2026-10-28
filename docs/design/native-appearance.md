# Native appearance continuation

Scope: Thorbis Field Management, SwiftUI iOS/iPadOS 17+, shared semantic colors and Settings appearance. Person: a field technician moving between outdoor daylight and a dark work area. Pattern: native Settings preference; existing Paper record/list surfaces consume the shared tokens.

References consulted 2026-10-26:
- https://design.thorbis.com/rules.md
- https://design.thorbis.com/files/DESIGN.md (warm light canvas, panel, well and ink)
- https://design.thorbis.com/skills/native (HIG-001–022)
- https://developer.apple.com/design/human-interface-guidelines/dark-mode
- https://developer.apple.com/design/human-interface-guidelines/accessibility

System appearance is the default. Settings exposes System, Light and Dark through a native picker, persisted on this device. Apple's Dark Mode topic prefers system-only appearance; Thorbis's explicit System/Light/Dark requirement is implemented with System as default. No web control is substituted for the native picker.

Paper's dark colors remain the reference. The light surface values are sRGB conversions of the published OKLCH tokens: canvas F7F4EE, panel FDFCFA, well EDE9E2, ink 201B14. The subtle dark label is raised from 8A8A8A to 949494 because its previous contrast on the field fill was 4.16:1, below Thorbis's 4.5:1 floor. Semantic text and border colors respond to Increase Contrast. This is an accessibility adjustment, not a new visual direction.

## Evidence matrix (not a full-app certification)

| Rule | Result | Evidence or remaining work |
| --- | --- | --- |
| HIG-001 | pass | App, OS range, source receipts and affected components above. |
| HIG-002 | not tested | Native picker retained; full navigation/platform review still required. |
| HIG-003 | pass | SwiftUI Picker uses system menu presentation. |
| HIG-004 | not tested | Picker row minimum 44 points; full effective target measurement remains. |
| HIG-005 | not tested | Appearance does not change routes; whole-app Back/state review remains. |
| HIG-006 | not applicable | No new sheet or draft transaction. |
| HIG-007 | not tested | Safe-area/keyboard regression coverage remains. |
| HIG-008 | not tested | Existing custom-font Dynamic Type requires full accessibility-size review. |
| HIG-009 | not tested | VoiceOver, Voice Control and keyboard runtime checks remain. |
| HIG-010 | not tested | Automated surface/text contrast checks added; screenshot and all semantic status/control pairs remain to verify. |
| HIG-011 | not applicable | No custom animation introduced. |
| HIG-012 | not applicable | No haptics introduced. |
| HIG-013 | not applicable | No text entry or domain mutation changed. |
| HIG-014 | not applicable | No new permissions, private data, or notification behavior. |
| HIG-015 | not tested | Preference persists via AppStorage; interruption and whole-app recovery remain. |
| HIG-016 | not tested | iPad window/selection and both-appearance checks remain. |
| HIG-017 | not tested | Existing symbols retained; long strings and RTL review remain. |
| HIG-018 | not tested | Physical-device performance evidence unavailable; no performance claim. |
| HIG-019 | not applicable | No media/capture changes. |
| HIG-020 | pass | Existing Theme namespace, native color adapter, no new dependencies/domain logic. |
| HIG-021 | pass | This matrix explicitly separates evidence and unverified behavior. |
| HIG-022 | not tested | No approved exceptions; remaining applicable gates prevent completion claims. |

Regression tests first failed for forced-dark surfaces and low-contrast subtle text in `outputs/appearance-red.log` (outside repo). Runtime verification and final test evidence to be appended after execution. This continuation is not uploaded as a new TestFlight build until release verification is complete.

Verification 2026-10-26: full Swift 6 strict-concurrency simulator suite passed, **107 tests, 0 failures**, `outputs/appearance-green.log`; xcresult `/private/tmp/Thorbis-Paper-DD/Logs/Test/Test-Thorbis-2026.10.26_22-19-34--0400.xcresult`. The two new tests resolve all shared informational text on five surfaces under both appearances and normal/high contrast; they do not certify status colors, translucent overlays or every control.

Native manual check: dedicated Thorbis Beta iPhone 17 Pro simulator, iOS 26.0, Debug build 3 with isolated read-only preview. Light OS appearance rendered warm light Jobs. Settings exposed Appearance/System; choosing Dark retained Settings, Done returned to Jobs, and terminate/relaunch retained Dark despite light OS setting. Screenshots: `outputs/paper/jobs-light.png`, `outputs/paper/jobs-dark.png` outside repository. Physical-device, iPad and assistive-technology checks remain outstanding.
