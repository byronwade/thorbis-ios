# TestFlight 1.0 (76)

Build 76 uploaded on October 28, 2026 at 10:58 p.m. EDT. Xcode reported
EXPORT SUCCEEDED. Apple processing is complete, the build is assigned to
**Internal Testers (2)**, and What to Test shows **Saved**.

[Open build 76](https://appstoreconnect.apple.com/teams/1f7ffdae-c53e-4d57-a97b-cc8cbc4760a8/apps/6827337706/testflight/ios/75334d12-cbd3-43ba-b8b4-a28eb9d92bc8) ·
[Dashboard confirmation](../design/evidence/build-76/testflight-confirmation.png).
Build ID: `75334d12-cbd3-43ba-b8b4-a28eb9d92bc8`.

Runtime source: `956a22f5c9615bf5dde502757c2861c81634e8cd` in existing
[draft PR #78](https://github.com/byronwade/thorbis-ios/pull/78), stacked on #77.

Every verified job estimate and invoice now has a page in one customer book, with
swipes, Previous/Next, a document menu and the existing overview. Each invoice
shows its original discounts/credits, total, paid amount, balance and dated
payments/refunds. Canonical review and signature remain separate from swiping.
Back retains the selected page; collection keeps technician authentication and
fresh invoice/job checks. Paid-invoice signing, signer evidence, stale recovery
and valid discounted collections remain available. Large text reflows both
navigation and financial rows. Invalid amounts have an explicit unavailable state.

Final qualification: **95/95** affected unit/native checks on iPhone 17 Pro/iOS 26,
initial iPad mini/iOS 18.2 smoke **3/3**, final iPad large-text **1/1**, and release
script checks **12/12**, all with zero failures/skips. All **172** Swift source,
test and widget fingerprints match. One independent branch review; all accepted
findings fixed with regression evidence. This was focused qualification under
the user's testing preference, not a new full scheme or physical-device/provider
certification.

The signed archive passed strict signature/team, app and widget version 1.0 (76),
release preview/control exclusion and disabled Tap policy audits. Archive:
`/private/tmp/thorbis-76.lxkhtd68/Thorbis.xcarchive`.

Known nonblocking baseline warnings: WidgetKit actor isolation and missing vendor
Stripe Terminal dSYM. Tap to Pay remains disabled pending distribution qualification.
C1–C3 catalog offers, customer choices and bill-once billing remain active; this
release does not claim their completion or a new backend/provider rollout.

[Release evidence](../design/evidence/build-76) ·
[UI and verification record](../superpowers/execution/2026-10-28-job-document-book.md).
