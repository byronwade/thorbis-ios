# Build 147

Uploaded to App Store Connect on 2 November 2026 from the source tree of
`release/104-integration` merge `0b5050ab80bd0ad5a7a5481b02a8131cc3d9c73e`
([PR #254](https://github.com/byronwade/thorbis-ios/pull/254)). Xcode reported
that the upload succeeded and the package was processing. Processing completion
and tester-group availability have not been verified.

- New job estimates carry the job location. Retry preserves a known saved
  estimate, checks its identity and terms, and re-reads it and the job before
  linking. An uncertain create is held from another submission while the editor
  remains open.
- Customer Money lists document identity, last-known totals and payment status.
- Long estimate line text remains in the editor instead of being silently
  shortened. The app explains the current server limit, and Save stays clear of
  the keyboard. Long custom-item queries use a compact preview.
- When the server drops meaningful item grouping, the technician can review and
  choose whether to continue; a visibility mismatch blocks the link.

The final combined run passed 33 unit and three UI tests. Additional focused
simulator runs covered two independent estimate signatures, invoice discounts
and refunds, estimate retry and authority refresh, and the largest-text custom
item flow on a small phone. One earlier combined run was interrupted; the
customer Money navigation test passed on rerun. Release script checks passed.
The archive passed the Tap to Pay build audit with Tap to Pay disabled.

Xcode warned that the Stripe Terminal framework's dSYM was not included, so
crash reports in that framework may lack symbols. Paragraph-length server
storage, durable recovery after the editor closes, atomic compare-and-link,
and Tap to Pay qualification remain separate work. These simulator checks do
not establish production payment behavior or live-device accessibility.
