# Build 159

Uploaded to App Store Connect on 3 November 2026 from release merge
`b6b211dd14a3f568735ad6999c6a4329d005b612`
([PR #291](https://github.com/byronwade/thorbis-ios/pull/291)). Xcode reported
upload success and that the package was processing. Processing completion and
tester-group availability have not been verified.

Job closeout now checks scoped invoice and payment evidence before treating
waiting payments as covering the balance. It explains payments needing review
and allows invoices to be found by full ID. The integrated source passed 30
focused unit tests, including cash and refused-payment outbox cases; 17 mounted
UI cases passed on a production-equivalent debug fixture. See
[closeout evidence](../design/evidence/closeout-payment-evidence-2026-11-03.md).
Legacy payments lacking a job association can conservatively hold automatic
offline closeout until reconciled. Existing cross-view invoice denial and
cold-cache limitations remain separate work.

The signed archive reports build 159, passed strict signature verification and
the Tap to Pay audit with the feature disabled. Xcode reported the existing
missing Stripe Terminal framework dSYM warning; see
[build 148](build-148.md#stripe-terminal-symbol-investigation). Startup-screen
preferences and newer job-flow changes are not included in this build.
