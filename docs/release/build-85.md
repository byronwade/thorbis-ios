# TestFlight 1.0 (85)

Uploaded October 29, 2026. Xcode reported upload succeeded and Apple began processing. Processing completion and tester availability have not yet been verified.

Runtime source: `36ec24473ed4459693d6d50940a3e70a1bb46e12`. Estimate and invoice pricebook pickers can browse all loaded matching items in bounded pages, return to earlier pages, and repeatedly add items without their position changing. The estimate custom-line action remains accessible. This does not enable the undeployed editable estimate draft-save API or include the separate activity-selection branch.

The focused picker, catalog and search suite passed 33/33; release-note validation passed 9/9. Independent source review cleared the final functional changes without running tests. VoiceOver focus after a page change and large-catalog performance on a physical iPhone remain unverified. Earlier failed UI runs and the abandoned lazy-list experiment are recorded in the execution notes.

The signed archive passed app/widget identity, strict signatures, source fingerprint, configuration and preview-exclusion checks. Tap to Pay remains disabled. The upload reported the existing missing Stripe Terminal dSYM warning, limiting symbolication for that framework. Archive and audit: `/private/tmp/thorbis-85-catalog/`.
