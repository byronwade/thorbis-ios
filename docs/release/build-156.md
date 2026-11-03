# Build 156

Uploaded to App Store Connect on 3 November 2026 from release merge
`135a7e01c19f81c824e4615d803929ac5870f511`
([PR #283](https://github.com/byronwade/thorbis-ios/pull/283)). Xcode reported
that the upload succeeded and the package was processing. Processing completion
and tester-group availability have not been verified.

On a job's Money view, each fresh invoice keeps its own item list behind an
independent Show items control. Amounts, status, invoice navigation and payment
actions remain visible. The standard-size payment bar sits below the scrolling
content so it cannot cover an invoice disclosure. Full descriptions remain in
invoice detail; this does not add the requested editable long-text drawer.

Five focused iPhone simulator UI cases passed on the source tree matching the
merged release: independent invoice disclosures, a partially visible control,
largest text, opening the right invoice, and returning to the correct staff
collection after customer payment. Independent source review found no confirmed
new blocker. See [invoice evidence](../design/evidence/invoice-disclosure-2026-11-03/README.md)
for screenshots, earlier failures, and limits. Physical-device, iPad and
VoiceOver testing were not performed for this increment.

The signed archive reported build 156 and passed the Tap to Pay audit with the
feature disabled. Upload succeeded despite an expired-session warning for one
account. Xcode reported the existing missing Stripe Terminal framework dSYM
warning; see [build 148](build-148.md#stripe-terminal-symbol-investigation).
Customer-selected add-ons, durable editable estimate drafts, paragraph-length
server storage, and qualified on-site payments remain separate work.
