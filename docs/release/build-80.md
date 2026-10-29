# TestFlight 1.0 (80)

Upload succeeded October 29, 2026 at 11:38:40 a.m. EDT. Apple processing is complete, **Internal Testers (2)** has access, and What to Test shows **Saved**. This verifies internal tester availability, not email delivery, external review or physical installation.

[Open build 80](https://appstoreconnect.apple.com/teams/1f7ffdae-c53e-4d57-a97b-cc8cbc4760a8/apps/6827337706/testflight/ios/d44022bf-0e05-4581-84ec-6855eb852061) · [Dashboard confirmation](../design/evidence/build-80/testflight-confirmation.jpg). Build ID: `d44022bf-0e05-4581-84ec-6855eb852061`.

Runtime source `d6e638594414b749ef8d513a2911a918a9a6f73e`, [draft PR #84](https://github.com/byronwade/thorbis-ios/pull/84), stacked on #83. This small fix adds two accurate privacy-purpose declarations for the existing schedule map and linked Stripe Terminal SDK, and checks them on signed app bundles even while Tap to Pay remains disabled. It retains every build 79 estimate improvement.

Independent review found no blocking findings. Actual signed-bundle RED cases previously passed missing/empty/non-string purposes incorrectly; all 15 focused Python tests passed after the fix. The old archive 79 is correctly rejected by the new audit. The generated simulator app and signed release 80 both pass it. No new permission request, Always/background mode, entitlement, SDK or Swift/UI change was introduced. Runtime prompt timing/denial and payment-provider readiness are not certified.

Signed app/widget identities, team, 1.0(80), iPhone/iPad families and iOS 18 minimum passed. All 187 unchanged Swift fingerprints and 3 changed configuration/tooling fingerprints match. Both exact purpose strings are present, Terminal remains 5.8.1, Tap policy false, and 41 preview flags plus 20 fixture/diagnostic literals are excluded. Archive `/private/tmp/thorbis-80.m4kn3aku/Thorbis.xcarchive` uses development signing; no separate distribution IPA audit. Existing widget actor and vendor Terminal dSYM warnings remain nonblocking. Apple’s completed-upload row for 80 displays no warning-detail control, while 79 retains one; the missing-purpose warnings are not displayed for 80. [Upload completion view](../design/evidence/build-80/upload-complete.jpg).

[Purpose qualification](../design/evidence/permission-purpose/execution.md) · [Signed/upload evidence](../design/evidence/build-80).

The larger technician editing, long-text/profile and customer storefront/cart work is separate and active; it is not delivered by this metadata patch. Historical simulator tap uncertainty and deferred completed-state copy remain recorded in build 79.
