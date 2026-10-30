# TestFlight 1.0 (88)

Uploaded October 29, 2026. Apple processing completed, the Internal Testers group (2 testers) has access, and What to Test is saved. Physical installation and external beta review are not confirmed.

[Open build 88](https://appstoreconnect.apple.com/teams/1f7ffdae-c53e-4d57-a97b-cc8cbc4760a8/apps/6827337706/testflight/ios/740cd394-348f-47ca-9692-12e4d261bce0).

Runtime source: `17267dd046db023d755e2a0adc3d9dd1b7b204f9`. Price Book uses compact row titles, real kind groups, units and aligned prices inspired by the Thorbis Mobile Paper design. Full meaningful descriptions remain readable and underlying stored text is unchanged. Only the exact known demo reconciliation suffix is suppressed in ordinary presentation; explicit stored-text copy and editing preserve it.

The focused pre-cache-change suite passed 39 unit and 16 UI tests. Final cache-bypass, stale-cache and 51-item failed-refresh checks passed on the latest source. Independent review found no new concrete exposure beyond the documented pre-existing same-owner stale-list limitation, and did not run tests. Actual device accessibility, real offline operation, and deployed cache headers remain unverified. See `docs/superpowers/execution/2026-10-29-pricebook-paper-clarity.md` for details and earlier failures.

Signed archive checks passed app/widget identity, source fingerprints, configuration and preview exclusions. Tap to Pay remains disabled. Upload reported the existing missing Stripe Terminal dSYM warning, limiting crash symbolication. Archive and audit: `/private/tmp/thorbis-88-pricebook/`.
