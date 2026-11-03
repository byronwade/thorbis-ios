# Build 155

Uploaded to App Store Connect on 3 November 2026 from release merge
`240cac8e4f7b1fa1eea167b4b556bfb85ac11cc5`
([PR #281](https://github.com/byronwade/thorbis-ios/pull/281)). Xcode reported
that the upload succeeded and the package was processing. Processing completion
and tester-group availability have not been verified.

Standalone price-book rows now show a concise supporting description where the
existing item text has a reliable title boundary, alongside the unit and price.
Long previews remain bounded at accessibility text sizes; the full description
and existing item actions remain available in details. Search still covers only
loaded items. Catalog photos and full-catalog search are not added by this change.

Six presentation tests and six focused iPhone simulator UI cases passed on the
source tree that matches the merged release, including dark mode, largest text,
long descriptions, full details, high prices and partial loading. Independent
source review found no confirmed blocker. See
[price-book evidence](../design/evidence/price-book-row-details-2026-11-03.md)
for screenshots and limits. Physical-device, iPad and VoiceOver validation were
not performed for this increment.

The signed archive reported build 155 and passed the Tap to Pay audit with the
feature disabled. The upload succeeded despite a logged expired-session warning
for one account. Xcode also reported the existing missing Stripe Terminal
framework dSYM warning; see [build 148](build-148.md#stripe-terminal-symbol-investigation).
The invoice item disclosure, durable draft recovery, paragraph-length server
storage, customer-selected add-ons and qualified on-site payments remain
separate work and are not included in this build.
