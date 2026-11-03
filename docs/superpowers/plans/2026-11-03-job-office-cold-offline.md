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
