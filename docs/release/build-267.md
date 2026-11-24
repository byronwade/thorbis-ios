# Build 267

Uploaded to TestFlight from `paper-v2-tokens` at ec1591ac on 2026-11-18 (PR #563).

Crash and stall fixes after a report that the TestFlight app kept crashing. App Store Connect had no crash logs or tester feedback at the time, so these come from reading the redesigned code, not from a confirmed log.

- Customer page: no longer traps when one of the customer's jobs is listed twice; paged reads now drop repeated records.
- Speech permission: the authorization callback no longer runs main-actor code on a background queue (closed the app on the first microphone tap).
- Customers and Jobs: rows are built lazily again instead of a whole group at once.
- Job page: the scroll view resets when the visit steps appear or go.
- Also from the UI test repairs: sheet menus ignore a row tap that followed a scroll, the sign-out sheet scrolls at large text, and the invoice line editor keeps Done and Remove above the keyboard.

Checks: 1,352 unit tests pass (1 skipped); stock-control lint 0. Full UI suite on build 266's code: 420 run, 402 pass, 11 skipped, 7 fail; those seven were fixed and pass by class. The menu, job page and list UI classes were still running on this commit at upload. Not tried with a real signed-in account.
