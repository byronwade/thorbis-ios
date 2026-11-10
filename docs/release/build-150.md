# Build 150

Uploaded to App Store Connect on 3 November 2026 from the source tree of
`release/104-integration` merge `c67b0b03697685b807db09ffa2abb2f2404110f3`
([PR #265](https://github.com/byronwade/thorbis-ios/pull/265)). Xcode reported
that the upload succeeded and the package was processing. Processing completion
and tester-group availability have not been verified.

- Invoice line Done and Remove stay clear of the keyboard's floating Done
  control while editing. Closing the line dismisses focus and formats a valid
  focused price; incomplete input remains available for validation.
- At accessibility text sizes the price book moves its heading into the scroll
  content and supplies a compact, labelled add action while preserving full-size
  item text. Search, filters, Close and Done remain available. Standard-size
  layout and guarded add behavior remain.

The exact app and test source passed four focused signed iPhone UI cases for
line close, price retention, keyboard dismissal and large-text line editing;
a strengthened large-text Remove/Done geometry case passed separately. The
large-text catalog source passed three UI journeys including a long title and
adding twice with the keyboard visible. Independent source reviews found no
confirmed blocker.

The combined release checkout passed 56 unit tests and two UI cases; its
aggregate failed when the simulator was explicitly shut down during the third,
direct-close case. App and runner received SIGTERM before the close assertion;
that aggregate is not counted as passing. An invalid-frame runtime warning also
appeared in prior baseline evidence and remains unexplained. Physical iPhone,
iPad, runtime VoiceOver, and floating/split/hardware keyboards remain unverified.
The signed archive passed the Tap to Pay audit with the feature disabled.

Xcode reported missing Stripe Terminal dSYMs; see
[build 148](build-148.md#stripe-terminal-symbol-investigation). Draft recovery,
paragraph-length server storage, customer-selected add-ons and qualified on-site
payment methods remain separate work and are not included in this increment.
