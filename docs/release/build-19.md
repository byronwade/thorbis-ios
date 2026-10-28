# Thorbis 1.0 (19): field flows and offline

Date: 2026-10-27. Built from `claude/paper-redesign` at `0353f13`. The upload script ran 239 simulator tests, the Release archive and export succeeded, and Apple reported **Upload succeeded**.

## Changes since build 18

- **Estimates.** Built from the Price Book on a job and linked to it. The job's Estimates tab lists every estimate with awaiting and approved totals.
- **Collect payment.** Opens on the card payment link. Tap to Pay is no longer the default.
- **Photos.** Camera capture, upload on capture, and Before/After filing. Photos are kept on the phone until uploaded.
- **Lifecycle.** The next-step button (On my way, then Mark arrived, then Start work) appears after every step, both on the job and on Schedule's Next up.
- **Offline.**
  - Reopening the app no longer signs you out or resets the screen. With no signal, the saved schedule and jobs open.
  - On my way, Arrived, Start work and notes queue on the phone and sync in order. Refused changes are shown with the reason, with Retry and Dismiss.
  - Server outages don't sign anyone out.
- **Money.** The revenue report is now Paper's Money screen.
- **Polish.** Success haptic on commits. "No connection" in plain words.

## Verification

- **Server contract check.** The exact JSON the app sends was replayed against the TanStack API with in-memory services. Every call was accepted: estimate create with a Price Book line, estimate link and list, assign, progress with ETA, media registration with tags and `capturedAt`, notes, and command upload with applied and duplicate outcomes. The list and progress responses were confirmed to carry no `allowedTransitions`.
- **Finding.** The dev identity rejects command envelopes as `policy_superseded` unless `policyVersion` is 0, even though its catalog reports 1. The commit after this build (`FieldOutbox` REST fallback) resends such changes through the REST routes, so a policy mismatch can't strand queued work.
