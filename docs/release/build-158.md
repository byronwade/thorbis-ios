# Build 158

Uploaded to App Store Connect on 3 November 2026 from application source matching
release merge `184b9715c76de0d1780459dd89b033e9d029e4bb`
([PR #290](https://github.com/byronwade/thorbis-ios/pull/290)). Xcode reported
the upload succeeded and the package was processing. Processing completion and
tester-group availability have not been verified.

Customer estimate links now display the API's USD minor units correctly in
totals, options, line items, discounts and receipts. Approval is held when the
amount cannot be verified. The corrected application source passed 44 focused
unit tests, 26 estimate-handoff tests and four simulator UI cases; the original
screen reproduced the error. See [estimate evidence](../design/evidence/public-estimate-cents-2026-11-03.md)
for source fingerprints and test limitations. Live server documents,
physical-device rendering and VoiceOver were not tested for this increment.

The signed archive reports build 158, passed `codesign --verify --deep --strict`,
and passed the Tap to Pay audit with the feature disabled. Xcode reported the
existing missing Stripe Terminal framework dSYM warning; see
[build 148](build-148.md#stripe-terminal-symbol-investigation). The subsequently
merged closeout guidance, customer-selected add-ons and draft recovery are not
included in this build.
