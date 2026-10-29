# TestFlight 1.0 (77)

Build 77 uploaded on October 29, 2026 at 1:04 a.m. EDT. Xcode reported
EXPORT SUCCEEDED. Apple processing is complete, the build is assigned to
**Internal Testers (2)**, and What to Test shows **Saved**. The exact full notes
and group assignment were verified in the dashboard; this does not certify
external Beta App Review, email delivery or installation on a physical phone.

[Open build 77](https://appstoreconnect.apple.com/teams/1f7ffdae-c53e-4d57-a97b-cc8cbc4760a8/apps/6827337706/testflight/ios/96d08acb-84d1-4e95-81da-9d6d00883343) ·
[Dashboard confirmation](../design/evidence/build-77/testflight-confirmation.png).
Build ID: `96d08acb-84d1-4e95-81da-9d6d00883343`.

Runtime source: `0ffd5773bfd2ebca99f7abbed7d5b34c561e920c` in
[draft PR #80](https://github.com/byronwade/thorbis-ios/pull/80), stacked on #79.
Subsequent source-branch commits before release documentation changed docs only.

Photos, scanned PDFs and imported images/PDFs now save protected local units
before upload. Their original operation ID and capture time survive navigation
and relaunch; the queue is scoped to the verified account, workspace, API origin
and job. Each transfer phase checks current authority and exact server storage
confirmation before local removal. Existing Paper capture/import/preview/tag and
retry controls remain available. Integrity and failed-cleanup errors are visible.

Older saved photos have an explicit recovery flow with fresh online job lookup,
named destination confirmation and protected adoption/cleanup receipts. Original
ownership is never guessed; recovery does not automatically preview or upload.
All job-scoped swipeable estimates/invoices and their discounts/payment/refund
history from build 76 remain, plus the exact Tap receipt fix from PR #79.

Qualification: **65 distinct** affected media/API/native cases, **64 passed** and
one simulator-only protection-attribute skip. Post-review payment/What's New
**57/57 passed**, zero failures/skips. Independent review cleared all four original
findings; no Critical/Important remained. One deferred Minor can leave a stale
legacy-cleanup warning after confirmed upload, with no media loss identified.
This does not certify physical camera/lock protection or production transfers.

Signed app/widget 1.0 (77) passed strict signature/team/bundle checks, iPhone/iPad
family and iOS 18 minimum, all **177 Swift fingerprints** and exclusion of **23 DEBUG
preview controls**. Tap policy remains false. Archive:
`/private/tmp/thorbis-77.RkzjtWJA/Thorbis.xcarchive`.

Existing widget actor-isolation warning and vendor Stripe Terminal missing dSYM
warning remain nonblocking. Export included a stale developer-session warning,
then completed transport successfully; it did not require a repeated sign-in.
No SDK upgrade, new backend/provider deployment, manual keyed-card method or
private bank-check capture/deposit is enabled. Tap distribution qualification,
C1–C3 catalog offers and the broader continuous goal remain active.

[Signed and upload evidence](../design/evidence/build-77) ·
[Native execution/review](../superpowers/execution/2026-10-29-durable-job-media.md).
