# Held job-office offline authority

`JobDetailCache` indexes data by job ID alone. The generic `SavedCopies` store has a
separate cache identity, but a screen-local denial disappears when its view is
recreated. Neither is sufficient evidence to show office instructions after a
job-specific denial. This isolated prototype is not wired into the job screen.

The new protected snapshot is keyed by actor, organization, validated API origin,
job, policy version, server authority generation and the current session,
authority and API generations. A caller must durably replace any old grant with
a pending token before issuing a live job read; an unavailable store means it
must not initiate that read. A successful fresh, identity-matched job may be
published only if its exact token and external live authority are current. A
server denial leaves the scope unavailable and invalidates pending attempts; a
connectivity error may restore only that attempt's prior verified snapshot.
Write failure disables the scope in the current process, and a later process or
session has different generation identifiers and cannot recover the old grant.
The storage format is protected and excluded from backup; sign-out attempts to
remove it. No general JobDetailCache or SavedCopies content is proof of access.

Standalone Swift stubs passed a scope/snapshot/denial/stale-response check
(`/tmp/thorbis-job-office-model-green3.log`); XCTest source adds same-session
recreation, policy and generation isolation, overlapping attempts, connectivity,
wrong-job and write-failure checks. App compilation, simulator tests, UI wiring,
end-to-end denial/reopen/offline races and independent security review are still
required. `stillAuthorized` is a caller assertion, not an authorization system:
the screen must check the actual current session, policy, actor, organization,
job, API origin and generation before every call and again before publishing.
Every live read capable of observing a denial must be mediated by the preflight;
a separate unmediated caller or stale unscoped fallback defeats that guarantee.
No claim is made that a previously authorized offline grant knows about a remote
revocation before the device receives one. The lifetime/expiry of offline
permission and interrupted preflight recovery remain policy decisions before
any product feature can be enabled.

## Overlap and offline-lifetime limits

The initial prototype dropped the previous verified snapshot when live read B
began while live read A was already pending. A failing standalone regression
(`/tmp/thorbis-job-office-overlap-red.log`) reproduced that behavior; the newer
pending entry now carries forward the prior verified snapshot, while a denial
stores none. Only B's current ticket may restore it after connectivity loss
(`/tmp/thorbis-job-office-overlap-green.log`). An old denial deliberately wins
over a newer success within the same scope: it suppresses offline access until
another current, verified live read succeeds. The conservative denial can cost
availability, but does not resurrect a potentially revoked note.

The session, authority-revision and API UUIDs are intentionally ephemeral.
Consequently offline copies do not survive app relaunch, API invalidation or
ordinary authority refresh even when actor, organization and server policy
appear unchanged; only same-generation view recreation can reuse them. A stable
cross-relaunch grant would need a separately qualified, expiry-bounded authority
receipt tied to the original actor/tenant/origin/job and policy, durable
write-ahead revocation that defaults to deny after storage errors, and a proven
binding between the restored session and that receipt. The existing cached
session snapshot alone does not establish a job-specific offline authorization
or a durable negative decision. Do not weaken the generation keys or claim
cross-relaunch offline access without those guarantees.
