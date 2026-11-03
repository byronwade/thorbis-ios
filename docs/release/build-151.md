# Build 151

Uploaded to App Store Connect on 3 November 2026 from the source tree of
`release/104-integration` merge `6b7a65aebcd799c5fac72b0386d78f31c3cd448d`
([PR #268](https://github.com/byronwade/thorbis-ios/pull/268)). Xcode reported
that the upload succeeded and the package was processing. Processing completion
and tester-group availability have not been verified.

The job Money view displays each estimate in a distinct card with its title,
known amount, status, reference and next-step wording. Existing scoped links,
customer handoff, option handling and partial-load recovery remain. This does
not introduce customer catalog add-ons or make existing draft edits saveable.

The final source passed five normal-size iPhone UI cases, two largest-text UI
cases and nine What's New checks. The integrated and merged trees matched the
verified source tree exactly. Independent static review found no definite new
scoping or action-loss issue. See
[job-estimate card evidence](../design/evidence/job-estimate-cards-2026-11-03.md)
for the initial failed large-text run, final checks and screenshots. Physical
phone, iPad, runtime VoiceOver and large-list performance remain unverified.

The signed archive reported build 151 and passed the Tap to Pay audit with the
feature disabled. Xcode reported the existing missing Stripe Terminal framework
dSYM warning; see [build 148](build-148.md#stripe-terminal-symbol-investigation).
Durable draft recovery, paragraph-length server storage, customer-selectable
add-ons and qualified on-site payment methods remain separate work.
