# Thorbis 1.0 (72)

Uploaded to App Store Connect on 2026-10-28 at14:15EDT. Apple processing and
Internal Testers assignment are pending verification.

Customers can scan a QR code to open the existing secure card checkout on their
own phone. Share and Copy remain alternatives. Expired or malformed links offer
recovery; refreshed invoice/history data controls paid status, and a changed
balance hides the previous link. Done returns to the invoice.

Cash and Check remain direct. Bank transfer (ACH) received and card collected
elsewhere are in one native menu. All four canonical tenders and their pending
amount/method/idempotency identity are preserved. Recording a received transfer
does not initiate an ACH debit. The Tap build policy remains false while Apple
publishing and exact-attempt/provider qualification are incomplete.

App source:c777c54, preserved from TestFlight71 plus the invoice UI changes.
Review: https://github.com/byronwade/thorbis-ios/pull/74 (stacked on73).
Issue:BYR-1579. Apple qualification evidence:tap-to-pay-qualification.md.

Verification:

- Full iPhone scheme407/407 passed; zero failures/skips.
- Additional iPad handoff1/1 passed, covering QR/Copy/status/Done.
- Focused decoder/expiry/URL/balance tests7/7; all4 invoice native UI checks and
  release-note checks passed. Largest text/dark sharing and expired recovery are
  covered. Native screenshots and test summaries are in docs/design/evidence/build-72.
- The exact renderer's preview and escaped-query payloads were independently
  decoded on macOS by Vision and CIDetector. Simulator Vision was unreliable;
  the unit test uses independent CIDetector decoding without skipping.
- Fresh review found no Critical/Important issues. Minor deferred: the no-image
  encoding fallback still uses camera headings, although Share/Copy remain usable.
- First full run406/407 had an existing scheduling UI tap timeout. Its unchanged
  focused reproduction and full407-test confirmation passed; no skip/automatic
  retry or Job UI code change was used.
- Release archive succeeded; app and widget both1.0(72). Deep strict signature
  verification and explicit-disabled Tap policy audit passed.
- No live charge/refund or merchant capability activation was performed. Native
  UI tests use DEBUG sample data and inert example.invalid URLs.
- Upload succeeded with a non-blocking missing StripeTerminal dSYM warning,
  UUID6B66F53A-307E-3AD8-AC4E-A2E5AF652AE9. Existing widget isolation warning remains.

Archive/upload logs:/private/tmp/thorbis-72.detz77.
