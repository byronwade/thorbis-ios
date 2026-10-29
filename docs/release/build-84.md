# TestFlight 1.0 (84)

Uploaded October 29, 2026 at 6:22 p.m. EDT. Xcode reported upload succeeded and Apple began processing; tester availability is pending.

Runtime source: `05b1c6042fb3523e78779a3a365730e68220c915`. Customer records include job-grouped modern and historical photos, with scoped deduplication and incomplete states. Job directions require choosing a customer account location rather than assuming the first location is the job site. Multiple job-specific contacts and locations remain unsupported by the current server contract.

The merged candidate passed 71 focused tests, including modern and historical photo roll-up journeys, job location choices, menu accessibility and payment-method checks. A separate 8 MiB legacy-photo responsiveness check, nine release-note tests, and a largest-text bank-transfer confirmation check passed. The signed app/widget archive passed identity, source fingerprint, configuration and preview-exclusion checks. Tests do not establish physical-device ActivityKit delivery, VoiceOver, or many-job performance. Tap to Pay remains disabled. Xcode reported a missing Stripe Terminal dSYM during upload, limiting symbolication for that framework.

Archive and audit: `/private/tmp/thorbis-84.buukf0q9/`. Activity selection improvements from the separate WIP branch are not included.
