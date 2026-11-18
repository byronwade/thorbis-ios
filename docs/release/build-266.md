# Build 266

Uploaded to TestFlight from `paper-v2-tokens` at e834eb74 on 2026-11-18 (PR #563).

Round three of the Paper design pass: sheets and sub-screens that the first two rounds had not compared.

- Job: Add to job sheet, Time and profit (time only; no cost data for profit), job contact page, voice note, add document, follow-up, photos, before and after, data plate, measure, photo viewer.
- Money: estimate revisions, Scan to pay, estimate response, line description editor.
- People: New message, customer details (Texts switch, archived customers), archive customer, import customers, vehicle.
- Office and account: Roles, Ownership, Invite member, pending invite, team member, offboard, export sheet, company profile rows, sign out; the iPad sidebar bell opens Notifications.

Left out because the app has no real data or backend for them: bank transfer, card entry, card reader, combined bill, three-term financing, AI writing help, membership autopay, warranty registration, team channels, subscription, two-step sign-in, morning briefing, and several rows within the screens above. Wrap-up (Paper 83/83A) is unchanged pending a decision.

Checks: 1,352 unit tests pass (1 skipped); stock-control lint 0; the archive is a release build. The UI suite was not run on this commit; controls that moved (role editors, member actions, Create invoice) may fail tests that look in the old place.
