# Thorbis 1.0 (70)

28 October 2026 · TestFlight beta · processed and available to Internal Testers

## Source and scope

Source: `52cac6d`, based on main `663c622`. Build 69's `0c83429` is an
ancestor of this baseline. The initial checkout was older; its archive was
interrupted before upload. Its smaller primary-action policy was removed.
The release preserves main's onboarding, estimate builder and price search,
complete technician estimate/payment flow, contextual job menu, job brief,
booking call, contacts, site details, past visits, equipment and job hours.

The additional changes let primary controls, tabs and metadata grow with
Dynamic Type, allow chips to wrap, constrain oversized flow content, and
stack contact shortcuts at accessibility sizes. Main's fitted tabs, trailing
fade, money hierarchy and Reduce Motion behavior remain in place.

The [continuous UX goal](../design/continuous-ux-goal.md) remains the product
direction. The What's new sheet includes readable controls and booking-call
coverage, plus the existing notes for newer main features.

## Verification and delivery

- [x] Confirm latest processed build in App Store Connect: 69.
- [x] Confirm Internal Testers includes both existing testers; their reported
  installed versions were 69 and 63. No access expansion was needed.
- [x] Preserve the latest main features rather than upload the older checkout.
- [x] Scoped adaptive-layout changes received a fresh review with no blocking
  issues; integration preserves main's own actions and domain policies.
- [x] Integrated full scheme: **389/389 passed, zero failures/skips** on iPhone 17 Pro Simulator, iOS 26.0. [Summary](../design/evidence/build-70/tests.json). The first integrated runs exposed test-fixture/readiness assumptions, corrected with a DEBUG-only working-job fixture and targeted scrolling.
- [x] Inspected [guided payment](../design/evidence/build-70/guided-payment.png), [job menu](../design/evidence/build-70/job-menu.png), [enlarged dark text](../design/evidence/build-70/accessible-dark.png), [scroll reachability](../design/evidence/build-70/accessible-scrolled.png), and [wide iPad](../design/evidence/build-70/ipad-wide.png).
- [x] Release archive succeeded at `/private/tmp/thorbis-70-integrated.5FVKb2/Thorbis.xcarchive`; app and widget both contain build 70.
- [x] `codesign --verify --deep --strict` passed for `com.thorbis.field`, version 1.0 (70).
- [x] App Store Connect accepted the upload at 12:31 EDT; Xcode reported `Uploaded Thorbis` and `EXPORT SUCCEEDED`.
- [x] Apple finished processing; build 70 appears in the processed build list.
- [x] Build 70 is assigned to **Internal Testers**, whose membership includes both existing testers. Automatic distribution for Xcode builds is enabled. [App Store Connect build](https://appstoreconnect.apple.com/teams/1f7ffdae-c53e-4d57-a97b-cc8cbc4760a8/apps/6827337706/testflight/ios/d92397cb-fad9-4d6d-8c4e-26ced0219f79).

No backend deployment or schema migration is included. The preceding beta
remains available for comparison; a blocking regression warrants expiring
this beta and producing a corrected build.

## Native evidence limits

Thorbis Field Management, SwiftUI, iOS/iPadOS 18+, Xcode 26.3. Source receipts:
[Thorbis Native](https://design.thorbis.com/skills/native), D-025 and
HIG-001–HIG-022; [Apple Menus](https://developer.apple.com/design/human-interface-guidelines/menus),
[Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons),
and [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars),
consulted 28 October 2026.

The native matrix in the [initial verification record](../design/ux-batches-29-30-verification.md)
documents the same shared-layout concerns and remaining checks. Current
release results are recorded above separately. This beta does not establish
whole-app accessibility or physical-device release certification. VoiceOver,
Voice Control, Switch Control, resizable iPad/keyboard/RTL coverage, live
consequential server operations and representative device performance still
need explicit native checks. No exception to those checks is claimed.

## Native applicability for this beta

Current automated/visual scope: source `52cac6d` plus DEBUG-only fixture and
UI-test corrections; debug build 17 on iPhone 17 Pro/iOS 26.0 and wide iPad
Pro 13-inch (M5)/iPadOS 26.0, 28 October 2026. Release archive 1.0 (70)
excludes all preview fixtures.

| Rule | Result | Evidence or remaining check |
| --- | --- | --- |
| HIG-001 | Pass | App, source, platform, OS range, artifacts and source receipts recorded here |
| HIG-002 | Pass | Native controls retained; text determines enlarged geometry |
| HIG-003 | Pass | Native Menu, Button, NavigationStack and schedule presentation; three native UI tests |
| HIG-004 | Not tested | Reachability passes; every affected target's effective hit area has not been measured |
| HIG-005 | Not tested | Menu/schedule/closeout navigation passes; interactive Back and restored deep links remain |
| HIG-006 | Not tested | Schedule cancellation passes; interruption and populated-draft recovery remain |
| HIG-007 | Not tested | Primary action remains visible at largest text; keyboard and rotation combinations remain |
| HIG-008 | Not tested | Four responsive-layout tests and largest-text preview pass; shared callers and older OS versions need broader native checks |
| HIG-009 | Not tested | Named controls work in XCTest; VoiceOver focus, Voice Control and Switch Control remain |
| HIG-010 | Pass | Appearance/contrast tests plus current light/dark screenshots; semantic tokens preserved |
| HIG-011 | Not applicable | No new custom motion; main's Reduce Motion implementation preserved |
| HIG-012 | Not applicable | No new haptic behavior in the adaptive-layout changes |
| HIG-013 | Not tested | Existing editing handlers retained; keyboard/draft/error recovery combinations remain |
| HIG-014 | Not applicable | No new privacy boundaries, permission requests or authorization policies |
| HIG-015 | Not tested | API/outbox/technician policy tests pass; real offline/reconnect and server confirmation remain |
| HIG-016 | Not tested | Current wide iPad visually checked; resizable windows, multitasking, pointer, keyboard and enlarged tablet text remain |
| HIG-017 | Not tested | Existing symbols retained, note symbols and long-label layout tested; RTL/localization remain |
| HIG-018 | Not tested | Representative physical-device launch, interaction, scrolling and memory measurements remain |
| HIG-019 | Not tested | Booking-call payload/recording-path tests pass; physical audio playback/interruption behavior remains |
| HIG-020 | Pass | Current main's full domain contracts, capability gates and technician flow preserved; all 389 tests pass |
| HIG-021 | Pass | Automated, visual, signed-build and unverified outcomes distinguished; no whole-app completion claim |
| HIG-022 | Pass | No exception claimed; pending native checks remain release-certification work |

## Upload diagnostics

Xcode export succeeded. It reported a non-blocking missing StripeTerminal
framework dSYM for UUID `6B66F53A-307E-3AD8-AC4E-A2E5AF652AE9`; this can limit
symbolication of SDK-internal crash frames. Archive/upload logs remain at
`/private/tmp/thorbis-70-integrated.5FVKb2/`. A stale-account session warning
preceded the successful upload; the final accepted transfer is the outcome.
