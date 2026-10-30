# TestFlight 1.0 (87)

Uploaded October 29, 2026. Xcode reported upload succeeded and Apple began processing. Tester availability is not yet verified. The earlier attempt to upload build 86 was rejected because that number had already been used; no success is claimed for that attempt.

Runtime source: `0627bfeb4e902a70f2184282b55eb36673031f9e`. Customer Overview presents the next visit and contact actions, with all jobs in the Jobs tab and customer details in a labeled disclosure. Job Overview brings notes, photos and follow-ups forward; its customer link has a visible arrow and comfortable tap target. Existing payment, location-choice, records and secondary actions remain available. This build does not include the separate activity-selection or editable estimate draft-save WIP.

Focused simulator journeys and independent reviews are recorded in `docs/superpowers/execution/2026-10-29-customer-job-glance-integration.md`. Tests include customer navigation, explicit location selection, long text, payment action, and a narrow iPhone SE layout. The initial integrated suite had one outdated Directions-label test failure; the corrected affected checks passed. Real-device VoiceOver, iPad, dark mode and customer loading/error journeys remain unverified.

Signed archive audit passed app/widget identity, source fingerprint, configuration and preview-exclusion checks. Tap to Pay remains disabled. The upload reported the existing Stripe Terminal missing-dSYM warning, limiting crash symbolication for that framework. Archive and audit: `/private/tmp/thorbis-87-glance/`.
