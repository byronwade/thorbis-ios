# Tap to Pay reader scope and account switching

Status: design and qualification work, not an implementation or permission to
enable Tap to Pay. Build 147 leaves the feature disabled. The Stripe Terminal
SDK's pinned `SCPTerminal.h` requires disconnecting a connected reader before
clearing cached credentials, then configuring the new token provider before
discovery and connection. `SCPReader.locationId` identifies a location, not
the connected Stripe account; equal location strings alone do not prove the
same authorized merchant. The account identity itself must remain server-owned
and need not be exposed to the app.

## Current risk

`TerminalSetup` is a process-wide singleton. `prepare` changes its invoice and
API reference, while `connect` currently reuses any existing reader without
checking the workspace, session or location. Two async charge controllers can
also interleave even though they run on the main actor. A request from a new
workspace must not use a prior workspace's reader session or cached token.
The Stripe terms guard proposed in 96b2b34 prevents terms presentation during
technician checkout, but it does not establish merchant-session isolation.

## Proposed behavior

1. Introduce an exclusive, cancellable Terminal operation lease that owns one
   payment attempt until it has completed or entered a recoverable uncertain
   state. Competing invoice attempts must wait or show a clear busy state; do
   not mutate the shared token provider while an operation is active.
2. Bind the lease and reader session to the verified actor, organization,
   session generation, API request generation and normalized origin, as well as
   the server-provided Terminal location. Treat a missing/unknown prior binding
   as a mismatch. Revalidate the binding and current capability after every
   await and before retrieving, collecting or confirming an intent.
3. For a different binding, location, or unknown existing reader: disconnect
   the reader and verify disconnection; clear cached credentials and verify the
   SDK result; only then install the new scoped token provider, discover and
   connect. A failed or cancelled cleanup aborts the payment; it never silently
   continues with the old reader. Mark a binding valid only after the SDK
   confirms the new connection. A server-owned merchant-binding/epoch contract
   is needed to detect account replacement within the same Thorbis workspace;
   until available, conservatively reconnect and clear credentials per attempt.
4. Sign-out, workspace switch, changed API origin and capability revocation
   invalidate the binding. If a payment is already in flight, prevent another
   attempt and preserve its idempotent server identity for reconciliation;
   do not describe cancellation or disconnection as a reversed charge.
5. Keep merchant terms acceptance disabled during technician checkout. An
   administrator-owned acceptance flow requires separate authority, design,
   implementation and physical-device qualification.

## Evidence needed before release

The local candidate is an initial fail-closed safeguard, not a complete
implementation of this design. It serializes access, clears credentials before
each connection, scopes a cached intent to the initiating session, checks the
token location, and quarantines uncertain creates and confirmations for the
remainder of the process. That quarantine does not survive app termination and
there is no customer-facing recovery flow. A server-verified merchant binding,
durable attempt reconciliation, controller-level asynchronous tests and real
device qualification remain outstanding. Do not enable Tap to Pay on the
strength of the candidate or its focused simulator tests.

The reviewed-amount safeguard compares the amount and currency presented to
the technician with both the server response and Stripe's retrieved intent,
and checks locally visible invoice terms before confirmation. A standalone
comparison test observed an expected failing result before the comparison was
implemented; the focused simulator suite passed 11 tests. These checks do not
exercise a full charge or prove protection against a later change on another
device. Server-side concurrency enforcement and end-to-end verification remain
necessary.

The current candidate also skips Stripe's tipping selection and requires the
retrieved and collected intents to retain the server's payment-intent ID and
reviewed amount and currency, with no nonzero tip reported. The SDK documents
that the tip field may be absent when intent updates are disabled, so the
configuration and physical-device behavior require qualification. A standalone
wrong-identity check observed a failing result before the policy was added, and
the focused simulator suite passed 13 tests. These are not controller-level
charge tests and do not prove remote invoice changes are detected.

Discovery still requires lifecycle work: the current SDK cancelable is not
stopped when authorization changes after a reader is discovered, and an empty
discovery update can wait indefinitely. Do not release the Terminal lease as
idle until cancellation is confirmed; quarantine it if cancellation cannot be
verified. Neither scenario is qualified by the tests above.

- Fake-SDK call-order tests for same/different/unknown scope, nil location,
  disconnect failure, clear failure, reconnect failure, stale callbacks and two
  simultaneous attempts. Confirm no token request or card collection occurs
  after failed cleanup, and no provider secret appears in logs.
- Async tests for sign-out, workspace switch, API origin change, permission
  refresh and cancellation at each network/SDK boundary. Verify the exact
  original attempt and reconciliation state survive an uncertain outcome.
- Server tests for token/account/attempt/invoice binding and idempotent webhook
  settlement, including a merchant account changed within one workspace.
- Physical iPhones and qualified Apple entitlement: verified two independent
  merchant accounts/locations, real connection/disconnection, interrupted
  payment recovery, and owner terms setup. Do not enable the feature or claim
  cross-account safety based on simulator or fake-SDK tests alone.
