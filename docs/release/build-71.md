# Thorbis 1.0 (71)

Uploaded to App Store Connect on 2026-10-28 at 13:44 EDT. Apple processing completed; the build is assigned to Internal Testers.
Verified in App Store Connect on 2026-10-28. The existing two-member group retains access.

Build: https://appstoreconnect.apple.com/teams/1f7ffdae-c53e-4d57-a97b-cc8cbc4760a8/apps/6827337706/testflight/ios/577d345e-4b9e-4a78-af58-695747158433

The invoice collection flow now offers Tap to Pay only when the build policy,
phone reader support, workspace feature and payment permission allow it. This
release explicitly disables Tap: Apple distribution entitlement qualification is
still separate. Secure card links, Cash, Check and already-collected card/ACH
recording remain available under the existing server permissions.

App source: 0ae06d2. Release-path fix: a5bb596. Stacked draft PR:
https://github.com/byronwade/thorbis-ios/pull/74 (depends on PR73).
Issue: BYR-1579. The received-method menu and QR handoff are the next batch.

Verification:

- Full Swift/native UI scheme: 393 passed, zero failed or skipped.
- Focused payment checks: 38 passed.
- Python artifact/release-boundary suite: 12 passed. The review finding about
  re-signing after audit was reproduced RED and fixed GREEN. An enabled build
  now exports once, audits the signed IPA and transports that exact file.
- Shell syntax and git diff checks passed.
- Release archive succeeded; app and widget both 1.0 (71). Deep strict signature
  verification and explicit-disabled Tap policy artifact audit passed.
- No live charge, refund or merchant capability activation was performed.
- Existing widget actor-isolation warning remains. Upload succeeded with a
  non-blocking missing StripeTerminal dSYM warning, UUID
  6B66F53A-307E-3AD8-AC4E-A2E5AF652AE9.

Archive/logs (local): /private/tmp/thorbis-71.qqljEc. Signed-app audit:
`python3 scripts/audit_tap_to_pay_build.py <archive>/Products/Applications/Thorbis.app`.
The current disabled build uses Xcode account upload. A future enabled build
requires Transporter and existing App Store Connect API-key authentication;
missing transport prerequisites refuse upload instead of re-exporting.

Fresh review deferred one minor: the Simulator controller no-request test also
has unsupported hardware. Pure readiness tests cover a disabled build with a
supported device; controller eligibility injection belongs in future physical
Tap qualification. Actual ACH debit, return accounting and exact provider-attempt
Tap reconciliation remain BYR-352/BYR-350/BYR-436 qualification work.
