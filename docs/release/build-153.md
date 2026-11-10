# Build 153

Uploaded to App Store Connect on 3 November 2026 from the source tree of
`release/104-integration` merge `e490ce858dde24591a34880ed781f1423f5d45c7`
([PR #272](https://github.com/byronwade/thorbis-ios/pull/272)). Xcode reported
that the upload succeeded and the package was processing. Processing completion
and tester-group availability have not been verified.

Live-only GET requests no longer fall back to Thorbis's saved copy after a
network failure and now request a fresh response from URLSession. Ordinary
reads retain offline saved-copy behavior. Four focused simulator transport
tests passed, including both offline fallback paths and the request cache policy;
independent source review found no additional definite defect. The cache-policy
test inspects the request, not a real URLCache or intermediary. Physical-device
and denial-to-offline customer UI checks remain untested.

The signed archive reported build 153 and passed the Tap to Pay audit with the
feature disabled. Xcode reported the existing missing Stripe Terminal framework
dSYM warning; see [build 148](build-148.md#stripe-terminal-symbol-investigation).
Build 152's estimate cards and customer-loading changes are included. A durable
customer-denial quarantine and customer-activity paging remain separate work,
as do draft recovery, extended descriptions, customer add-ons and qualified
on-site payment methods.
