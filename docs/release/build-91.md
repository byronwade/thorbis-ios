# TestFlight 1.0 (91)

Uploaded 2026-10-30 from source `4c82cba3db7d9e9eba9692f100a26bd207f53e13`. Apple processing completed and the build is assigned to Internal Testers (2 testers). [Open build 91](https://appstoreconnect.apple.com/teams/1f7ffdae-c53e-4d57-a97b-cc8cbc4760a8/apps/6827337706/testflight/ios/9a5f5a1e-2586-4f8f-a074-acd8cb41fff2).

This batch adds status-specific schedule cues, customer initials and status labels, and document-type visuals in estimates, invoices and billing. It fixes optional ETA labels and allows long names and large amounts to reflow. The combined focused run passed 9 What's New unit tests and 2 customer/invoice UI tests. Schedule and customer dark/light previews, light billing, large-text invoices and the narrow-phone long-name/large-amount case were inspected. Actual ETA selection, live workspace data, VoiceOver and iPad remain unverified.

Real-photo preview is not included: the existing API downloads full originals and the prototype duplicated Photos navigation. The [investigation](../design/evidence/build-91/photo-thumbnail-investigation.md) records a bounded, authorized thumbnail path for follow-up. Tap to Pay remains disabled. The Stripe Terminal dSYM warning remains, and the distribution export was not independently audited.
