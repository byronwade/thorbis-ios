# Native UI evidence — 2026-10-27

**App:** Thorbis Field Management  
**Platforms:** iOS and iPadOS, SwiftUI  
**Supported OS:** iOS/iPadOS 17.0 and later  
**Affected screens:** Jobs/My Day, Schedule, Job detail, Invoice editor, Estimate revision editor, Customer detail and contact/location sheets, Price Book, workspace navigation/search, and iPad Schedule.
**Scope:** Production Jobs now opens on My Day. Custom controls in these surfaces have at least a 44 × 44 pt interaction frame while retaining their existing Paper artwork.

## Design and platform references

- Thorbis native rules: [design.thorbis.com/skills/native](https://design.thorbis.com/skills/native), including HIG-001–022; iOS platform guidance: [design.thorbis.com/platforms/ios](https://design.thorbis.com/platforms/ios).
- Apple Human Interface Guidelines topics consulted 2026-10-27: [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Layout](https://developer.apple.com/design/human-interface-guidelines/layout), [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars), [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets), and [Typography](https://developer.apple.com/design/human-interface-guidelines/typography). Apple returned JavaScript-only pages in this research client; this evidence record relies on the Thorbis native rule text and local SwiftUI implementation for the requirements below.
- Thorbis mark confirmed against `Thorbis-TanStack/apps/showcase/public/logo-source.png`: SHA-256 `07b9cb8803e215ad6a45b17daadd05ef27e0a72799c9cf0e83310a848273d737`, identical to `Thorbis/Resources/Assets.xcassets/ThorbisMark.imageset/ThorbisMark.png`. The 1024 px app icon is `Thorbis/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.

## Evidence matrix

| Rule | Result | Evidence or remaining work |
| --- | --- | --- |
| HIG-001 | pass | App, OS range, affected screens, rule IDs, Apple URLs, and consultation date are recorded above. |
| HIG-002 | pass | Existing Paper tokens, labels, and business meaning are preserved. Touch frames follow Thorbis's native minimum where static Paper artwork was smaller. |
| HIG-003 | pass | Changed interactions remain SwiftUI Buttons and Menus; no custom hit-test adapter or WebView was added. |
| HIG-004 | pass | Static source audit sets app-authored custom controls on affected surfaces to at least 44 pt in both dimensions. See `PaperComponents.swift`, `PaperNavigation.swift`, `PaperWorkViews.swift`, `PaperJobDetailView.swift`, `InvoiceLineEditorView.swift`, `EstimateRevisionEditorView.swift`, `PaperCustomerViews.swift`, `Screens.swift`, `ServiceLocationSheet.swift`, `WorkspaceViews.swift`, and `PaperTabletSchedule.swift`. The source frame audit is the evidence; screenshots alone do not prove target size. |
| HIG-005 | not tested | My Day remains a selectable Jobs destination and the iPad schedule retains list/detail columns. State restoration across navigation, rotation, and resizing still needs runtime checks. |
| HIG-006 | pass | Estimate revision uses a native SwiftUI sheet with an explicit Cancel action and a confirmation before discarding unsaved edits to reload a stale server revision. |
| HIG-007 | not tested | iPhone and iPad layouts were previewed. Keyboard, orientation, and resizable-window behavior still need explicit checks. |
| HIG-008 | not tested | Font choices and sizing were not changed. Dynamic Type through accessibility sizes remains unverified. |
| HIG-009 | not tested | Existing labels and selection traits remain. VoiceOver, Voice Control, focus order, and runtime accessibility bounds were not tested. |
| HIG-010 | not tested | The iPhone preview was checked in Light appearance. Dark mode, Increase Contrast, Reduce Transparency, and contrast pairs on every affected state remain unverified. |
| HIG-011 | not applicable | No custom motion or transition changed. |
| HIG-012 | not applicable | No haptic behavior changed. |
| HIG-013 | partial | Estimate fields retain native text input and interactively dismiss the keyboard while scrolling; keyboard overlap and focus recovery still need device testing. |
| HIG-014 | not applicable | No permission request or protected-data access changed. |
| HIG-015 | partial | Invoice payment loading failures expose retry; a successful collection remains locked until invoice and full payment history reconcile. Automated interruption/retry coverage passes, while device-level network interruption remains untested. |
| HIG-016 | not tested | A 13-inch iPad simulator showed the adaptive schedule list and detail layout. Split View resizing, rotation, and draft preservation are still unverified. |
| HIG-017 | not tested | SF Symbols remain in use. RTL and localized long-string layout still need review. |
| HIG-018 | not tested | Simulator validation does not establish physical-device performance. |
| HIG-019 | not applicable | No media capture or upload behavior changed. |
| HIG-020 | pass | Estimate request encoding follows the existing revision route and source/option schemas. No server contract, token namespace, dependency, or web wrapper was introduced. |
| HIG-021 | pass | This matrix records evidence and untested areas separately. Unresolved applicable checks continue to block full mobile completion. |
| HIG-022 | partial | Independent review of invoice-payment retry, refund reconciliation, and issue-refresh state passed. App-wide visual and accessibility review remains open. |

## Verification

- `xcodebuild test -project Thorbis.xcodeproj -scheme Thorbis -destination 'platform=iOS Simulator,id=2A143E1A-3061-46D1-8BE4-DF1768C4B681' -quiet`: passed, 170 tests, 0 failures, iPhone 17 Pro / iOS 26.3.1. Result bundle: `/Users/byronwade/Library/Developer/Xcode/DerivedData/Thorbis-dmuwxdzkujngcfxjqjbnvsarbv/Logs/Test/Test-Thorbis-2026.10.27_03-35-33--0400.xcresult`.
- `xcodebuild -project Thorbis.xcodeproj -scheme Thorbis -configuration Release -destination 'generic/platform=iOS' -quiet build`: passed.
- Read-only iPhone previews: `/private/tmp/thorbis-my-day-after-hit-targets.png` and `/private/tmp/thorbis-invoice-editor-after-hit-targets.png`.
- Read-only iPad 13-inch schedule preview: `/private/tmp/thorbis-ipad-schedule-rotated.png` (landscape orientation).

This evidence covers the listed UI adjustments only. It is not an app-wide HIG certification or proof of full Paper/TanStack parity. Physical-device, assistive-technology, Dynamic Type, dark/high-contrast, orientation/resizing, and independent review gates remain open.

## Invoice payment history and recorded collection

- The issued invoice detail now shows a complete-history payment count, read-only payment detail, a Paper-style add control, and a fixed `Collect payment` action. The full-height SwiftUI sheet records a tender already collected using Card, ACH, Cash, or Check; the sheet states that it does not charge a card or bank account.
- The displayed balance remains derived from the latest server `InvoiceRecord`. The form blocks overpayment and stays locked after a successful POST until the full payment history and refreshed invoice `amountPaid` agree. Retries reuse the same amount, method, and idempotency key after an uncertain transport or server failure.
- Screens were inspected in the iPhone 17 Pro / iOS 26.3.1 read-only fixture: `/private/tmp/thorbis-invoice-detail-payment-preview.png` and `/private/tmp/thorbis-invoice-payment-entry-preview.png`.
- Verification on 2026-10-27: full simulator suite passed, 161 tests and 0 failures on iPhone 17 Pro / iOS 26.3.1 (`/tmp/ThorbisReviewFixTests.xcresult`); `xcodebuild -project Thorbis.xcodeproj -scheme Thorbis -configuration Release -destination 'generic/platform=iOS' -quiet build` passed.
- An uncertain payment intent persists only its amount, tender type, and idempotency key, scoped to organization and invoice. A definitive 4xx response or successful server-history reconciliation clears it. A fully refunded record without `netAmount` contributes zero; an issued invoice response remains authoritative if the follow-up refresh fails.
- This slice is not proof of full feature parity. Processor-backed card collection, hosted pay links, refunds, and other audited app areas remain outside this implementation.

## Estimate revision and option packages

- Sent and declined estimates can be revised into a replacement draft under `estimate.create`. The native editor submits the reviewed revision number, preserves manual and Price Book source identity across the primary scope and all option packages, and supports up to eight alternatives. Approved estimates remain on the server-supported change-order path.
- A stale revision conflict preserves the local form and offers an explicit reload. The read-only iPhone 17 Pro fixture is `/private/tmp/thorbis-estimate-revision.png`; it verifies presentation and disabled-save state only, not an authenticated server mutation.
- Contract tests verify `/v1/estimates/:id/revise`, exact Price Book revision encoding, option data, limits, and no automatic retry on a 409. The current 170-test simulator suite and Release compile are recorded in `docs/release/beta-coverage.md` after merge verification.
