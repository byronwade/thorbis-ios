# Inbox email handoff — 13 November 2026

Customer, job and contact email actions open the device-local inbox composer
with the recipient and any supplied fields. Send with Mail opens the system
composer or a mailto fallback; it does not mark a message sent in Thorbis.
The existing on-device save and queue actions remain explicit about not sending.

Unfinished email is protected in a device-only Keychain recovery item scoped to
the original actor, organization, API origin and record context. Reopening that
context offers recovery or discard. Failed recovery reads block editing; failed
writes and cleanup are reported. Previous copies may be older or already saved.

The release-based candidate at `db37e4a2` passed 26 focused unit tests and five
UI tests for session restoration, process termination, and injected recovery
load, write and cleanup failures (`/private/tmp/thorbis-email-recovery-db37-1113.log`).
On the same built code, a combined run passed 35 unit tests and four UI tests
covering customer, job and contact entry points and the simulated Mail handoff
preserving all fields (`/private/tmp/thorbis-inbox-email-final-db37-1113.log`).
Independent source review found and
prompted fixes for scope collisions, field loss and stale recovery cleanup;
the later source changes were DEBUG-only test injection.

No email was sent in testing. Actual Mail account behavior, physical-device
VoiceOver and a shared, provider-connected inbox are not verified or implemented
by this change. The signature privacy and TestFlight account-contract issues
remain separate and unresolved.
