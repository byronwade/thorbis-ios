# Build 282

Uploaded to TestFlight from `paper-v2-tokens` at 057825b9 on 2026-11-19 (PR #563).

Owner: "Yes, build everything. get everything ready" (in reply to the App Store blocker list from build 281).

- Delete account: the confirm sheet asks for the password. The phone sends it once to `POST /v1/account-lifecycle/reauthentications`, then sends the deletion request with the proof it gets back. It reads the server's reason codes: wrong password, too many tries, signed out, check ran out, not switched on yet. Every refusal says nothing was deleted.
- Inbox: texts, email and Drafts are hidden unless the server turns on `inbox_messaging`. Text and Email buttons open the phone's own Messages and Mail.
- Equipment and maintenance plans: the lists show the shared server records only. No new phone-only notes.
- Offline queue: a note that timed out is checked against the server before it is posted again, so it cannot post twice. If the phone could not save the queue, the saved-work banner says so.
- Permission screens: one "Continue" button before each system prompt (App Review 5.1.1).
- Sign-out unregisters the phone from push alerts.
- Long lists (billing, invites, team) stop if the server repeats a page.

Checks: 1,392 unit tests pass (1 skipped), stock-control lint passes. Full UI run: 2 failures, both passed when re-run alone (invoice catalog search; the landscape saved-work test needed a simulator restart because the simulator was stuck upright). Not checked on a real phone. The delete flow was not run against a live server: the server route is not deployed.

Server work, drafts only, nothing merged or deployed:
- byronwade/Thorbis-TanStack#1605 (BYR-1606): the sign-in check route, its table (migration 0151) and a proposed deletion policy that refuses every request until the owner approves it. `pnpm check` has not passed end to end on any machine.
- byronwade/Thorbis-TanStack#1604 (BYR-1605): draft Privacy Policy, Terms and Subprocessors text with about 55 owner-to-confirm blanks.

Still open, needs the owner or the server:
- Account deletion cannot complete: #1605 must be reviewed, migrated and deployed; the deletion policy must be approved; and nothing on the server removes data yet (BYR-447).
- No reviewed privacy policy or terms are published.
- Time clock, receipts, truck stock, training, pipeline, vendors, marketing notes, fleet and customer notes still keep records on this phone only, and say so.
- App Privacy answers (device ID, location, analytics, call audio) are the owner's to confirm.
