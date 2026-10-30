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

## Technician connection safeguard — October 30, 2026

Stripe Terminal 5.8.1's `SCPTapToPayConnectionConfiguration` header documents
that terms acceptance defaults to permitted; setting it to false prevents the
terms prompt and fails the connection when merchant terms are not yet accepted.
Invoice collection now explicitly sets this value to false, and the two
terms-related SDK errors direct the technician to the business administrator
or another payment method. The administrator setup flow is not implemented by
this change. A valid prior merchant acceptance, the Apple distribution grant,
provider readiness and physical-device qualification remain separate gates.

The earlier table's aggregate-receipt observation is historical: current
invoice collection checks the canonical payment for the specific attempt.
This does not establish connected-merchant or distribution qualification.
The `ThorbisTapToPayEnabled` release policy remains false.

Verification in the isolated worktree: the builder setter and configuration
getter typechecked against the pinned simulator framework; all 12 existing
Tap build-audit Python tests passed. Two new Swift tests cover the configuration
and unaccepted-terms message, but were not executed: the initial simulator
test build stalled during asset compilation and was stopped. Repeat those tests
and test the fail-closed connection on an authorized physical development
device before treating the behavior as qualified.

### Existing reader and credential scope

Review found that `TerminalSetup.connect` returns for any existing reader,
before checking its location or the merchant and environment for the new
invoice. In Stripe Terminal 5.8.1, `Reader.locationId` is the last location
registered at connection, and does not establish the connected merchant or
environment. The SDK's `clearCachedCredentials` documentation says to disconnect
the reader, clear cached credentials, configure the token provider for the new
account, then discover and connect; the SDK can otherwise reuse a saved reader
session. See `SCPTerminal.h` and `SCPReader.h` in the pinned SDK. The current
API token response has no merchant identity, so matching location alone is not
evidence that a reused connection belongs to the requested merchant.

Before enabling Tap, establish server-authoritative merchant, environment and
workspace identity, serialize the complete collection lifecycle to prevent a
scope switch while a charge is underway, and disconnect/clear credentials and
obtain a freshly scoped token whenever the verified binding changes or cannot
be established. Test same-scope reuse, account and environment changes,
logout/workspace changes, reconnect errors and concurrent attempts. This
report does not claim those protections are implemented.
