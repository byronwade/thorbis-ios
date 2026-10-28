# TestFlight 1.0 (74)

Uploaded on 2026-10-28 at 19:08 EDT. Apple processing is complete. The existing
Internal Testers group is assigned with two testers, and What to Test shows Saved.
No new invitations or external beta review were submitted.

Source: 0717f2c61fe152d3dd55964ee0fe727641a969f4. Draft PR
[#76](https://github.com/byronwade/thorbis-ios/pull/76) is stacked on #75.

Draft invoices now search the full Price Book, with ranked results, recent items
and category filters. Each tap appends a separate quantity-one line while keeping
the picker open. Selection counts update in place, and an active category stays
visible after the keyboard closes. Additions remain in the draft until Save.
Shared catalog loads survive the initiating view closing; organization, session
and API-generation guards prevent stale publication across workspaces. Incomplete
pagination retains the last complete cache and offers retry.

Validation: 458/458 full native unit/UI tests passed with zero failures or skips,
including cancellation, transport-scope handoff, selected-category visibility and
VoiceOver-label regressions. Release-script checks passed 12/12. Strict signature,
team, app/widget version and Release preview-boundary audits passed. Swift source
fingerprints match the final test run. These new runtime checks used iPhone 17 Pro
on iOS 26.0; they do not certify new iPad or iOS 18 behavior.

Tap to Pay remains disabled pending signed distribution qualification. Existing
secure payment links and received-payment methods remain available. Customer
add-on quote/acceptance and catalog-photo contracts remain follow-up work.
A preexisting WidgetKit actor-isolation warning and Stripe Terminal vendor-dSYM
warning remain non-blocking; Xcode reported EXPORT SUCCEEDED.

[Open this build](https://appstoreconnect.apple.com/teams/1f7ffdae-c53e-4d57-a97b-cc8cbc4760a8/apps/6827337706/testflight/ios/21c02aa4-de59-4262-a446-0d28181e04b1).
Evidence is in [build-74](../design/evidence/build-74). The
[execution record](../superpowers/execution/2026-10-28-technician-catalog-search.md)
records review decisions and remaining work.
