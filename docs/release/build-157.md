# Build 157

Uploaded to App Store Connect on 3 November 2026 from release merge
`4012162d6f591715c493d697e0c9b4c2b7779fca`
([PR #285](https://github.com/byronwade/thorbis-ios/pull/285)). Xcode reported
that the upload succeeded and the package was processing. Processing completion
and tester-group availability have not been verified.

Customer location names wrap without truncation, and their Service or Billing
status moves below the name at accessibility text sizes. The existing location
actions remain available. Two focused iPhone simulator UI cases passed on the
combined release source, covering long names and Edit location at normal and
largest text sizes. Independent source review found no confirmed blocker. See
[location evidence](../design/evidence/customer-location-label-2026-11-03.md).
Physical-device, iPad and VoiceOver testing were not performed for this increment.

The signed archive reported build 157 and passed the Tap to Pay audit with the
feature disabled. Xcode reported the existing missing Stripe Terminal framework
dSYM warning; see [build 148](build-148.md#stripe-terminal-symbol-investigation).
The estimate draft-recovery candidate, invoice description reader, customer cart
and qualified on-site payments remain separate work and are not in this build.
