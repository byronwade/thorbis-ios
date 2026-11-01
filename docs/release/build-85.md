# TestFlight 1.0 (85)

Uploaded October 29, 2026. Apple processing completed, the Internal Testers group (2 testers) has access, and What to Test is saved. Physical installation and external beta review are not confirmed.

[Open build 85](https://appstoreconnect.apple.com/teams/1f7ffdae-c53e-4d57-a97b-cc8cbc4760a8/apps/6827337706/testflight/ios/97ec983d-1a0f-465c-9f84-3a27bb46aa3b).

Runtime source: `36ec24473ed4459693d6d50940a3e70a1bb46e12`. Estimate and invoice pricebook pickers can browse all loaded matching items in bounded pages, return to earlier pages, and repeatedly add items without their position changing. The estimate custom-line action remains accessible. This does not enable the undeployed editable estimate draft-save API or include the separate activity-selection branch.

The focused picker, catalog and search suite passed 33/33; release-note validation passed 9/9. Independent source review cleared the final functional changes without running tests. VoiceOver focus after a page change and large-catalog performance on a physical iPhone remain unverified. Earlier failed UI runs and the abandoned lazy-list experiment are recorded in the execution notes.

The signed archive passed app/widget identity, strict signatures, source fingerprint, configuration and preview-exclusion checks. Tap to Pay remains disabled. The upload reported the existing missing Stripe Terminal dSYM warning, limiting symbolication for that framework. Archive and audit: `/private/tmp/thorbis-85-catalog/`.
