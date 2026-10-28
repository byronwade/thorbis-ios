# Job documents and customer handoff

Stage A of BYR-1580 shows every verified estimate and invoice for the current job.
Technician catalog editing and customer-selected add-ons remain follow-on work;
this stage does not implement their server quote/acceptance contract.

The branch is stacked on the invoice payment release at 488fb5e. Initial task
commits are c119bb0 and 14a0643. That source passed 426 unit/native UI tests before
its fresh whole-batch review. The review found seven Important issues and one
subtotal feature loss, regraded Important under the preserve-features requirement.
All eight were accepted into one fix pass, without a second review dispatch.

## Review fixes

- Retain same-scope invoices as stale only after transient detail failures;
  denied, deleted, or contradictory contents never return from that fallback.
- Share document snapshots and known-ID recovery between staff and customer mode.
- Publish/cache only the latest request; gated older responses cannot replace a
  newer authoritative empty result for either collection.
- Track rejected origin estimate IDs so a failed link read cannot resurrect them.
- Validate actual invoice ID, organization, customer and job at detail/model and
  final payment hand-back boundaries. An invalid response clears collection readiness.
- Select the opened invoice card. A native equal-balance regression exposed an
  additional navigation-task reset: selection was cleared on return. Scope that
  reset to a changed session generation, while continuing ordinary refreshes.
- Gate estimate creation on complete readable paper, preserving create-only roles.
- Restore fixed-price approved/awaiting totals behind a disclosure. Keep currencies
  separate, identify option-bearing estimates separately, and suppress invalid or
  overflowing totals.

## Verification record

Fallback regressions first failed on two assertions, then passed 14/14. Combined
loader/payment scope and request-order checks passed 28/28. The summary/native run
passed 23/26: creation and disclosure failed as expected; the selection test first
had a footer-label harness error. Its corrected scoped check reproduced the actual
wrong invoice. Later focused confirmation passed 45/46, with selection still wrong.
The captured video and temporary DEBUG-only trace proved navigation task restart
cleared selected2209 and selected2240 instead. Those diagnostic logs were removed.

The first generation-guard confirmation stopped before selecting a card: its
initial tab tap did not take effect. The isolated selection journey now starts
with the existing job-invoice preview; other cases retain tab-navigation coverage.
That exact selection check passed 1/1 after the fix. No failing run was counted as
passing or hidden behind automatic retries.

Final full-scheme verification:443/443 passed,0 failures/skips. Additional iPad
largest-text/dark customer-document check:1/1 passed,0 failures/skips.
Release-boundary/signing Python checks:12/12 passed. The final source fingerprint
is held during verification; no source edits are made during a build/test run.

The preview intercepts all requests and rejects writes. Deterministic owner-auth
fixtures exist only in DEBUG preview. Release uses device-owner authentication;
Simulator fixtures do not certify physical-device biometrics or Apple publishing
qualification. Tap to Pay remains unavailable until its signed distribution
qualification is established. QR/card checkout and received-payment recording
remain available under their existing server authority.

## Delivery

Signed archive, upload, Apple processing, tester assignment and testing notes:
pending. No TestFlight73 availability is claimed yet.

## Prepared demo data

The separate local kit contains 300 customers, 600 jobs, 400 estimates, 350 invoice
lifecycle plans, 30 synthetic technician profiles and 500 catalog entries. Descriptions
and authored demo USD rates are prepared. All 500 logical entries map to 24
representative image families: 18 sourced photos and 6 labelled generated images.
Independent record/image checks passed; source bytes and credits are preserved.

No tenant import, login account, invitation, signature, approval, payment or
provider action was created. The workspace choice remains pending. Catalog photo
attachment and a no-send assignable technician fixture need their governed owner
interfaces; BYR-861 remains post-stage under BYR-138. No issue-ID substitution or
stage bypass was used.
