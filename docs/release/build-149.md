# Build 149

Uploaded to App Store Connect on 2 November 2026 from the source tree of
`release/104-integration` merge `aa4a64c270ad5de8d2d4bc378df48f969ac9d52a`
([PR #262](https://github.com/byronwade/thorbis-ios/pull/262)). Xcode reported
that the upload succeeded and the package was processing. Processing completion
and tester-group availability have not been verified.

- In the combined customer estimate handoff, long item and package descriptions
  open in a read-only drawer. Customer typography and context-specific spoken
  labels make descriptions easier to read and distinguish. Package details are
  also available during selection.
- A cached estimate revision is used for package details only when its document
  identity and revision still match the refreshed record. Session or API-scope
  changes retire the protected handoff. Existing estimate and invoice readers
  retain their customer-facing behavior.

The signed simulator run passed 48 focused unit tests and seven UI checks; the
largest-text UI case was interrupted when the simulator shut down and passed in
an isolated retry on the same source. The combined release-source run passed 35
unit tests. Independent source review found no remaining blocker; live customer
approval and runtime VoiceOver were not tested. The signed archive passed the
Tap to Pay audit with that feature disabled.

Xcode again reported missing Stripe Terminal dSYMs; see
[build 148](build-148.md#stripe-terminal-symbol-investigation). Customer-selected
catalog add-ons, paragraph-length server storage, durable draft recovery and
qualified on-site payment methods remain separate work. The draft-recovery
candidate was not included in this build.
