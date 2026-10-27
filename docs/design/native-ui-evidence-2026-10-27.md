# Native UI evidence — 2026-10-27

**App:** Thorbis Field Management  
**Platforms:** iOS and iPadOS, SwiftUI  
**Supported OS:** iOS/iPadOS 17.0 and later  
**Affected screens:** Login and logo lockup, signed-in workspace navigation, native Jobs/Arrive/Inbox tabs and More destinations, new-job composer, Jobs/My Day, Schedule, Job detail, Invoice editor and payment/refund details, estimate revision editor, customer estimate decision link, Customer detail and contact/location sheets, Price Book, workspace search, and iPad Schedule.
**Scope:** The iPhone Jobs tab opens on the full jobs workflow and the Arrive tab opens on My Day. The iPad retains its schedule/sidebar/detail layout. Custom controls on the listed surfaces use at least a 44 × 44 pt interaction frame while retaining their Paper artwork.

## Design and platform references

- Thorbis native rules: [design.thorbis.com/skills/native](https://design.thorbis.com/skills/native), including HIG-001–022; iOS platform guidance: [design.thorbis.com/platforms/ios](https://design.thorbis.com/platforms/ios).
- Apple Human Interface Guidelines and developer topics consulted 2026-10-27: [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Layout](https://developer.apple.com/design/human-interface-guidelines/layout), [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars), [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets), [Typography](https://developer.apple.com/design/human-interface-guidelines/typography), and [Supporting associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains). Apple requires the AASA file at the domain root with no redirect. The live `https://app.thorbis.com/.well-known/apple-app-site-association` currently redirects into the `/app` SPA and returns HTML, so HTTPS links are not yet registered as Universal Links.
- Thorbis mark confirmed against `Thorbis-TanStack/apps/showcase/public/logo-source.png`: SHA-256 `07b9cb8803e215ad6a45b17daadd05ef27e0a72799c9cf0e83310a848273d737`, identical to `Thorbis/Resources/Assets.xcassets/ThorbisMark.imageset/ThorbisMark.png`. The native login and customer estimate headers use the official blue mark with the Thorbis wordmark, matching the lockup in `Thorbis-TanStack/apps/showcase/src/components/Logo.astro`; the signed-in workspace selector uses the same verified mark. The 1024 px app icon is `Thorbis/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.
- Paper source review found no customer estimate-signature artboard. This native screen follows the design.thorbis.com native contract and its shared Paper palette, with the issued estimate kept as a static document preview. The web flow reference is `PortalFlow` and `PortalApproval` in the TanStack customer document-action page.

## Evidence matrix

| Rule | Result | Evidence or remaining work |
| --- | --- | --- |
| HIG-001 | pass | App, OS range, affected screens, rule IDs, Apple URLs, and consultation date are recorded above. |
| HIG-002 | pass | Existing Paper tokens, labels, and business meaning are preserved. Touch frames follow Thorbis's native minimum where static Paper artwork was smaller. |
| HIG-003 | partial | App interactions are native SwiftUI controls. The issued estimate alone uses a JavaScript-disabled, nonpersistent WKWebView preview. The current pattern sanitizer strips common active elements and direct remote `src`/`href` attributes, and clicked navigation is blocked; CSS, `srcset`, protocol-relative, and other resource references have not been dynamically verified. |
| HIG-004 | pass | The customer action screen has a 44 pt close target, 48 pt primary and secondary actions, and 68 pt option rows. The refund reason form has a native destructive confirmation, full-payment amount, and 44 pt action targets. Existing app-owned controls are covered by the source audit in `PaperComponents.swift`, `PaperNavigation.swift`, `PaperWorkViews.swift`, `PaperJobDetailView.swift`, `InvoiceLineEditorView.swift`, `InvoicePaymentCollection.swift`, `EstimateRevisionEditorView.swift`, `PaperCustomerViews.swift`, `Screens.swift`, `ServiceLocationSheet.swift`, `WorkspaceViews.swift`, and `PaperTabletSchedule.swift`. |
| HIG-005 | partial | The app routes the Thorbis custom scheme and the current HTTPS path when delivered to the app. Live HTTPS Universal Links remain unavailable until the domain serves a valid AASA file without redirects and the App ID has the matching entitlement. |
| HIG-006 | pass | Estimate revision uses a native SwiftUI sheet with explicit Cancel and stale-edit recovery. Declining a customer estimate now requires a native confirmation. |
| HIG-007 | not tested | iPhone and iPad layouts were previewed. Keyboard, orientation, and resizable-window behavior still need explicit checks. |
| HIG-008 | partial | Native controls use scalable Thorbis font tokens and the system text input. The fixed printed estimate preview does not reflow with Dynamic Type; accessibility-size verification remains open. |
| HIG-009 | partial | Option selection, brand mark, name field, close action, disabled approval reason, and save/error announcements have accessibility labels or traits. VoiceOver, Voice Control, focus order, and runtime bounds remain untested. |
| HIG-010 | partial | Light appearance was visually checked, including disabled approval contrast. Dark mode, Increase Contrast, Reduce Transparency, and all-state contrast still need verification. |
| HIG-011 | not applicable | No custom motion or transition changed. |
| HIG-012 | not applicable | No haptic behavior changed. |
| HIG-013 | partial | Customer signer and change-request fields use native text input, name autofill, a 120-character signer limit, and a 500-character request limit. Refund reasons use native text input and enforce the server's 3–2,000 character limit. Transient failures preserve drafts; keyboard overlap, Dynamic Type, and device focus recovery remain untested. |
| HIG-014 | partial | Refund reasons and outcomes are stored in device-only Keychain and never sync to iCloud. Physical-device locked/first-unlock behavior and Keychain recovery are not verified yet. |
| HIG-015 | partial | Customer estimate states cover loading, unavailable/stale links, retryable errors, pending decisions, and confirmed decisions. Refund screens distinguish completed, pending, reconciliation-required, and uncertain outcomes and retry only on explicit user action with the saved reason. Simulator tests cover response recovery; device-level interruption remains untested. Invoice collection remains locked until invoice and full payment history reconcile. |
| HIG-016 | not tested | A 13-inch iPad simulator showed the adaptive schedule list and detail layout. Split View resizing, rotation, and draft preservation are still unverified. |
| HIG-017 | not tested | SF Symbols remain in use. RTL and localized long-string layout still need review. |
| HIG-018 | not tested | Simulator validation does not establish physical-device performance. |
| HIG-019 | not applicable | No media capture or upload behavior changed. |
| HIG-020 | pass | Public approval reuses `/v1/public/document-actions/:token` and its canonical approve, decline, and request-changes bodies. Public requests disable employee-session cookies; staff APIs remain on their existing transport. |
| HIG-021 | pass | This matrix records evidence and untested areas separately. Unresolved applicable checks continue to block full mobile completion. |
| HIG-022 | partial | Customer estimate and payment refund screens have been reviewed in read-only iPhone 17 Pro previews. Universal Link activation, physical-device behavior, dark/high-contrast states, assistive technology, and app-wide review remain open. |

## Verification

- Latest full `xcodebuild test -project Thorbis.xcodeproj -scheme Thorbis -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`: passed, 215 tests, 0 failures, iPhone 17 Pro / iOS 26.3.1. Result bundle: `/Users/byronwade/Library/Developer/Xcode/DerivedData/Thorbis-dmuwxdzkujtkngcfxjqjbnvsarbv/Logs/Test/Test-Thorbis-2026.10.27_06-54-26--0400.xcresult`.
- Release iPad Pro 13-inch (M5) simulator build passed. Read-only shell fixtures: `/private/tmp/thorbis-primary-tabs-build15.png` (Jobs/Arrive/Inbox phone tab bar) and `/private/tmp/thorbis-ipad-primary-nav-after.png` (iPad schedule sidebar/list/detail). Preview screenshots contain sample data and do not validate authenticated workflows.
- `xcodebuild build -quiet -project Thorbis.xcodeproj -scheme Thorbis -configuration Release -destination 'generic/platform=iOS'`: passed on 2026-10-27. Build 14 archive at `/private/tmp/Thorbis-14-release.xcarchive` passed strict code-signature verification and uploaded successfully to App Store Connect at 5:41 AM EDT; Apple reports that processing has started. Build 15 archive and upload evidence is in `docs/release/build-15.md`.
- Read-only iPhone previews: `/private/tmp/thorbis-my-day-after-hit-targets.png` and `/private/tmp/thorbis-invoice-editor-after-hit-targets.png`.
- Payment refund flow checks use the isolated read-only fixtures documented in `../release/payment-refund.md`; the iOS 17 generic-device Release compile passed with build 17. The signed archive and upload status are recorded in `../release/build-17.md`.
- Read-only customer estimate preview with the authentic Thorbis logo and selected-option approval flow: `/private/tmp/thorbis-public-estimate-v2.png`.
- Read-only iPad 13-inch schedule preview: `/private/tmp/thorbis-ipad-schedule-rotated.png` (landscape orientation).

This evidence covers the listed UI adjustments only. It is not an app-wide HIG certification or proof of full Paper/TanStack parity. Physical-device, assistive-technology, Dynamic Type, dark/high-contrast, orientation/resizing, and independent review gates remain open.

## Invoice payment history and recorded collection

- The issued invoice detail now shows a complete-history payment count, read-only payment detail, a Paper-style add control, and a fixed `Collect payment` action. The full-height SwiftUI sheet records a tender already collected using Card, ACH, Cash, or Check; the sheet states that it does not charge a card or bank account.
- The displayed balance remains derived from the latest server `InvoiceRecord`. The form blocks overpayment and stays locked after a successful POST until the full payment history and refreshed invoice `amountPaid` agree. Retries reuse the same amount, method, and idempotency key after an uncertain transport or server failure.
- Screens were inspected in the iPhone 17 Pro / iOS 26.3.1 read-only fixture: `/private/tmp/thorbis-invoice-detail-payment-preview.png` and `/private/tmp/thorbis-invoice-payment-entry-preview.png`.
- Verification on 2026-10-27: full simulator suite passed, 161 tests and 0 failures on iPhone 17 Pro / iOS 26.3.1 (`/tmp/ThorbisReviewFixTests.xcresult`); `xcodebuild -project Thorbis.xcodeproj -scheme Thorbis -configuration Release -destination 'generic/platform=iOS' -quiet build` passed.
- An uncertain payment intent persists only its amount, tender type, and idempotency key, scoped to organization and invoice. A definitive 4xx response or successful server-history reconciliation clears it. A fully refunded record without `netAmount` contributes zero; an issued invoice response remains authoritative if the follow-up refresh fails.
- This slice is not proof of full feature parity. Processor-backed card collection, hosted pay links, refunds, and other audited app areas remain outside this implementation.

## Full payment refunds

- Invoice payment details now expose a reasoned full refund only for a recorded, unrefunded payment when `invoice.refund` is available in the `payments` feature. The server remains authoritative for amount-specific authorization and current eligibility; partial refunds are intentionally not offered.
- The native flow saves the reason in device-only Keychain before submission, requires a destructive confirmation, and keeps HTTP 202 pending/reconciliation outcomes separate from canonical HTTP 200 completion. An uncertain request is recoverable with an explicit status check that reuses the same payment ID and reason. No automatic retry occurs.
- Design previews use read-only sample invoice/payment fixtures and a local transport that returns HTTP 405 for refund POSTs. Preview states cover payment details, reason entry, confirmation, pending, and reconciliation; no real workspace or payment is mutated.
- API/model/preview coverage and current release checks are in [payment-refund.md](../release/payment-refund.md). Physical-device Keychain behavior and the HIG-018 performance measurement are not tested.

## Estimate revision and option packages

- Sent and declined estimates can be revised into a replacement draft under `estimate.create`. The native editor submits the reviewed revision number, preserves manual and Price Book source identity across the primary scope and all option packages, and supports up to eight alternatives. Option packages require `estimate_option_signing`; when existing packages cannot be submitted, the editor locks the revision instead of dropping them. Negative credit lines require `estimate.discount`. Approved estimates remain on the server-supported change-order path.
- A stale revision conflict preserves the local form and offers an explicit reload. The read-only iPhone 17 Pro fixture is `/private/tmp/thorbis-estimate-revision-review-fixed.png`; it verifies presentation and disabled-save state only, not an authenticated server mutation.
- Contract tests verify `/v1/estimates/:id/revise`, exact Price Book revision encoding, option data, limits, feature/capability gates, normalized change detection, and no automatic retry on a 409. The current 174-test simulator suite and Release compile are recorded in `docs/release/beta-coverage.md`.
