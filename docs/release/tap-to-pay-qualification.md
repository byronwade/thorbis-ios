# Tap to Pay qualification evidence

Updated 2026-10-28. Apple development access was approved on October27 for team
T677262U5B (Case23157370). No publishing approval was found. TestFlight71 keeps
ThorbisTapToPayEnabled=false; development access does not authorize distribution.
BYR-436 owns program/review evidence; BYR-350 owns Terminal qualification.

Apple's October2026 v1.8 requirements and public checklist were read. Submit
completed metadata and requirement tabs, plus New User, Existing User and
Checkout recordings. Film checkout with a second device: the system reader
screen is not captured by screen recording. Native merchant terms need an
authorized person's acceptance. Registered physical-device validation remains
outstanding; simulated UI cannot certify acceptance or preparation latency.

Sources:
- https://apple.box.com/v/ttpoiappreviewpdf
- https://apple.box.com/v/ttpoichecklist
- https://developer.apple.com/documentation/proximityreader/setting-up-the-entitlement-for-tap-to-pay-on-iphone

## Verified source gaps and next work

| Evidence in current iOS source / pinned SDK5.8.1 | Required source work |
| --- | --- |
| Connection builder defaults tosAcceptancePermitted=true; checkout has invoice-collection authority, not merchant-terms authority | Explicitly disallow terms acceptance during technician checkout; provide an administrator recovery message |
| ReaderEvents ignores SDK configuration progress | Publish real progress and clear stale state |
| No native education/replay entry | Integrate ProximityReaderDiscovery and an accessible replay path |
| Preparation begins after invoice-scoped intent creation | Verify merchant-scoped token contract before designing launch/foreground warmup |
| Token response exposes secret/locationId, no explicit connected-account identity | Verify server scope before calling isTapToPayAccountLinked(nil); never infer or locally persist terms acceptance |
| Current completion closure observes aggregate invoice balance/payment count | Reconcile the exact provider attempt, merchant, environment, amount/currency and invoice under BYR-350 |

Keep the release policy false while these gates remain open. Do not submit a
duplicate entitlement request, enable a capability, accept terms, or send review
materials based solely on this document. The original approval email is the
case thread; no mail or portal state was changed during the audit.
