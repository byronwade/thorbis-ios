# TestFlight 1.0 (73)

Uploaded2026-10-28 at17:08 EDT. Apple processing is complete. Internal Testers is
assigned with two testers; testing notes show Saved. No external beta review was
submitted and no new tester invitations were sent.

Source:5f48e17af1dd7886f62633270e7440f8ded09edf. PR[#75](https://github.com/byronwade/thorbis-ios/pull/75)
is stacked on#74. The app now lists all verified documents for the current job,
keeps payment on the selected invoice, preserves safe stale rows, and offers
customer document browsing with technician hand-back. Estimate totals are behind
a disclosure; incomplete reads prevent duplicate-create prompts.

Validation:443/443 full iPhone unit/native UI tests,1/1 additional iPad largest-text
and dark-mode document check, and12/12 release-script/signing-policy tests passed.
The signed archive passed strict integrity, app/widget version consistency and
Release preview-boundary checks. Tap to Pay remains disabled pending its signed
distribution qualification; no payment/provider actions were used in verification.

A preexisting WidgetKit actor-isolation warning and StripeTerminal missing-dSYM
warning remain non-blocking. Xcode reported EXPORT SUCCEEDED and the processed
build is assigned to its internal group.

[Open this build](https://appstoreconnect.apple.com/teams/1f7ffdae-c53e-4d57-a97b-cc8cbc4760a8/apps/6827337706/testflight/ios/5fb0132f-70ba-4806-ac29-53dd4a1a063a). Evidence is in docs/design/evidence/build-73;
reproduction details and remaining catalog/customer-add-on work are in
[the execution log](../superpowers/execution/2026-10-28-job-documents.md).
