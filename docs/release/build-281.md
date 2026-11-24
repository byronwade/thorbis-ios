# Build 281

Uploaded to TestFlight from `paper-v2-tokens` at 49931e55 on 2026-11-19 (PR #563).

Owner: "It needs to be production ready". Two read-only audits were run (runtime robustness, App Store submission) and the code-only findings fixed.

- Crashes: the member total on an estimate and the purchase-order line preview no longer trap on a very long quantity (bounded, overflow-checked like `subtotal`). A session expiry far in the future no longer overflows the timer.
- Offline queue: a queue file this build cannot decode is copied to `<file>.unreadable` before the next save can write over it.
- Privacy: Home and Lock Screen widgets clear on session expiry and revoked job access. Upload sessions are invalidated when done.
- App Store declarations: privacy manifest adds file timestamps (C617.1) and device ID. `NSPhotoLibraryAddUsageDescription` and `NSContactsUsageDescription` added. Camera, location and speech strings now match real use.
- Legal links: Terms and Privacy Policy open thorbis.com/legal from sign-up and from Account and data.
- Tidy: New estimate, New contact, logo crop, billing and photo compare close with ×. The iPad jobs filter field says "No filters" instead of sitting blank. A technician's own job no longer shows a chip with their own name.

Checks: 1,389 unit tests pass (1 skipped), stock-control lint passes, 46 UI tests pass (JobOverview, TabBar, JobListSearch, EstimateCreationRecovery). Swept on an iPhone SE and an iPad simulator. Not checked on a real phone.

Not fixed, needs the owner or the server:
- Account deletion sends nothing: the server has no route that gives the phone a re-authentication proof.
- thorbis.com/legal/privacy and /terms are structure only; no reviewed text is published.
- Several screens say they keep records on this phone only (texts and email, marketing, pipeline, timesheets, equipment, agreements).
- Queued notes can post twice after a timeout (no idempotency key on the REST note route). Non-payment queue entries are reported saved even if the disk write failed.
- Permission primers offer "Not now" before the system prompt.
