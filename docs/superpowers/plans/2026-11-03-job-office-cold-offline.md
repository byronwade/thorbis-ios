# Held cold-offline job office snapshot

The previous store binds a grant to ephemeral session, authority and API UUIDs,
so it cannot provide cold offline access after relaunch. This separate,
disconnected prototype uses stable actor, organization, normalized origin, job,
policy version, authority generation, a SHA-256 digest of the server session ID,
and an authority deadline supplied by a
caller that has independently verified its persisted session. It never claims
to know about a remote revocation while offline. The current wall clock is not a
trusted anti-rollback clock; device clock manipulation and the quality of the
underlying authority receipt remain unresolved before enabling.

Every operation takes a nonblocking shared lifecycle lock and an exclusive
per-scope lock using stable files. A durable file barrier is established before
changing the Keychain marker to pending and before any live request is allowed.
A cold reader requires no barrier, an available marker, an unexpired caller
scope and a digest-matching protected snapshot. Successful completion writes the
snapshot and removes older scoped snapshots before granting the marker. A
connectivity failure can restore only the current pending attempt's prior
verified snapshot. Explicit denial installs a barrier before changing the marker.
A failed marker write after the barrier leaves cold reads blocked after restart.

`retireAll` requires the exclusive lifecycle lock, writes a durable global
retirement barrier, deletes the prototype's entire dedicated Keychain service,
then deletes snapshots and per-scope barriers. It does not unlink global or
scope lock files. Failure leaves the global hold in place for a retry; a
completion racing after successful retirement cannot find its pending marker.
Sign-out must not report success if retirement fails. The prototype is not wired
to sign-out or the job reader, and there is no claim that other unmediated paths
or stale callers have been secured.

When the filesystem cannot establish the initial write-ahead barrier, the
operation fails and no live read may start; an in-process unsafe latch suppresses
the old grant. If every durable write is unavailable, software cannot record
that failure across a process restart; the caller must not proceed with sign-out
or a request, and independent persisted session validation is essential.
`Data.write(.atomic)` and Keychain ordering have not been verified under sudden
power loss with explicit file/directory fsync; process-exit evidence is not a
power-loss guarantee. Snapshot replacement and retirement errors fail closed,
but crash-orphan files can remain until a later successful replacement or
retirement. Keychain entries are device-bound, not a hardware-signed
job-specific authorization grant. Local storage tampering, clock rollback,
process death and mixed-version deployments require further security review.

A standalone macOS model harness exercised stable-scope reopen, pending and
denied holds, and expiry (`/tmp/thorbis-job-office-cold-green3.log`). A separate
process held the scope flock and forced contention before a retry succeeded
(`/tmp/thorbis-job-office-cold-lock-green2.log`). Separate process invocations
using a file-backed marker demonstrated pending/relaunch, failed marker write
with a surviving barrier, and failed retirement followed by retry; these are
not real-Keychain or iOS device evidence. XCTest source includes actual-Keychain,
expiry, scoped lock, cleanup failure and retirement cases, but has not yet run.


The first simulator run compiled the app and passed the twelve fake-marker
cases, but the real-Keychain case failed with OSStatus -34018 under
`CODE_SIGNING_ALLOWED=NO` (`/tmp/thorbis-job-office-cold-xcode.log`). The
built app reports an ad-hoc linker signature with no visible entitlements,
consistent with missing-entitlement behavior, but this has not yet been
confirmed using a properly signed simulator or device build. The actual
Keychain adapter must not be described as qualified. A caller must supply the
verified session-ID digest, never a raw token; the cold scope rejects missing or
malformed digests and isolates a changed digest.

A subsequent simulator run explicitly enabled bundle ad-hoc code signing and
passed all 13 cold-store tests, including the actual Keychain read/add/update
case (`/tmp/thorbis-job-office-cold-signed-xcode.log`). The simulator app had
identifier `com.thorbis.field` and an empty entitlements dictionary; unlike the
unsigned linker-signed run, Keychain calls succeeded. This qualifies only that
simulator signing context, not a physical device or distribution-signed build.
The session-digest isolation case is included in the passing run. Process tests
with an injected marker are not power-loss evidence, and the cold store remains
disconnected from the job reader and sign-out.

A follow-up signed simulator run passed all 13 cold-store tests and expanded the
real Keychain case to verify deletion is limited to the dedicated test service;
a second Keychain service remained intact (`/tmp/thorbis-job-office-cold-delete-xcode.log`).
This is simulator evidence only and does not qualify device signing, integrated
logout, power-loss recovery or network/authority races.

## Denial variants and interrupted attempts

The original prototype keyed records by policy, authority generation and exact
expiry. That allowed a denial under one expiry to leave a prior grant accessible
when an earlier expiry recurred. The denial, lock, Keychain marker and barrier
now share one key for actor, organization, origin, job and session digest.
Snapshots separately bind their exact policy and authority generation and must
be within both their original expiry and the caller's current expiry. A denial
under any policy/generation/deadline for that same identity retires its old
grant. Mixed-version migration is not implemented; this key change cannot be
rolled out while any old reader can still access its old-key grant.

A second reproduced bug let a pending marker from a dead process retain an old
snapshot on the next process's connectivity failure. A pending marker now
contains a random process epoch, and retention/completion additionally require
an active in-memory ticket for that exact key under the flock. A process restart
or another process treats the old pending marker as orphaned and cannot restore
its previous grant. Same-process overlapping reads retain the old snapshot only
while the previous ticket is genuinely active. The caller must invoke `abandon`
on cancellation or retirement; a denial invalidates every active attempt for
that key. Standalone red/green process and deadline checks are recorded in
`/tmp/thorbis-cold-orphan-{red,green}.log` and
`/tmp/thorbis-cold-deadline-{red,green}.log`. iOS and network/UI coverage of
these revisions, cross-process policy races and full caller cancellation wiring
remain open; no cold reader or sign-out path is enabled.

A further race occurred when a previously granted long-lived snapshot was
followed by a short-lived read whose denial arrived after that request's
deadline: rejecting the expired scope prevented recording the denial, and a
renewed request could then restore the older grant. This was reproduced in
`/tmp/thorbis-cold-expired-denial-red.log`. Denial and cancellation now validate
stable identity and origin without requiring the request deadline to remain
current; reads, preflights and grants still require unexpired authority. The
exact regression passed `/tmp/thorbis-cold-expired-denial-green.log`. The
integrating caller must deliver a confirmed denial for the captured stable scope
even if its request deadline expires while the response is in flight, while
never treating it as authority to publish data.

### Held coordinator seam (2026-11-03)

`JobOfficeColdReadCoordinator` is disconnected from product screens. It starts the durable pending barrier before a fresh read, persists a confirmed 401/403/404 against the captured stable identity even if its runtime lease or deadline has since retired, rechecks caller authority after the read, and abandons canceled or failed attempts. Its injected caller must reread verified persisted authority and compare runtime session, API, actor, organization, job and policy on each check; it must map only an actual fresh uncached denial to `.denied`. No local check proves the server's job-specific authorization or deployed session identity.

Standalone macOS compilation against model stubs ran the real coordinator and store for five scenarios: preflight storage failure, stale success, denial after scope retirement, task cancellation, and denial persistence failure (`/tmp/thorbis-cold-coordinator-cases.log`); the separate expired-denial check passed (`/tmp/thorbis-cold-coordinator-green.log`). The XCTest source adds corresponding checks but has not been run on a simulator. These results do not establish live networking, UI integration, cold relaunch, physical-device behavior, offline revocation, actual power-loss durability, or correct production sign-out handling. A production caller must mediate every read, prove current job access and authenticated server session identity, handle retirement failure, and test end to end before enabling this seam.

### Denial contention fence experiment (held)

The separate-process regression `/tmp/thorbis-cold-denial-contention-red.log` showed that a held scope lock could cause a confirmed denial to be discarded and a prior note restored. This candidate writes a separate denial intent without that lock, and tests for it both before and after locked operations. The same regression passes in `/tmp/thorbis-cold-denial-contention-green.log`; four additional standalone coordinator checks pass in `/tmp/thorbis-cold-coordinator-fence-cases.log`. The added XCTest has not been executed. A denial conservatively blocks this job/session from cold storage until global retirement; regrant semantics are intentionally not implemented. This experiment still requires adversarial review of cross-process retirement ordering, storage failure when another process cannot observe the failure, power-loss durability and publication races. It does not qualify this feature for production or guarantee revocation while offline.
