# Build 154

Uploaded to App Store Connect on 3 November 2026 from the source tree of
`release/104-integration` merge `08ac88207b58c02a117cd5c4617cc772c2c41957`
([PR #276](https://github.com/byronwade/thorbis-ios/pull/276)). Xcode reported
that the upload succeeded and the package was processing. Processing completion
and tester-group availability have not been verified.

Customer Overview contact rows show initials and direct call and text circles
when a phone number is available. The existing contact menu remains, and actions
stack below the name at accessibility text sizes. Existing phone normalization
and system handoffs are unchanged.

Two focused iPhone simulator UI tests and nine What's New tests passed on the
exact merged source. Independent source review found no confirmed new blocker.
See [contact evidence](../design/evidence/customer-contact-quick-actions-2026-11-03.md)
for screenshots, the corrected test navigation and limits. Actual phone and SMS
handoffs, VoiceOver, dark mode, other device sizes and real customer data remain
untested in this increment.

The signed archive reported build 154 and passed the Tap to Pay audit with the
feature disabled. Xcode reported the existing missing Stripe Terminal framework
dSYM warning; see [build 148](build-148.md#stripe-terminal-symbol-investigation).
Build 153's live-only cache fix is included. Draft recovery, customer cache
quarantine and history paging, extended descriptions, customer-selected add-ons,
and qualified on-site payment methods remain separate work.
