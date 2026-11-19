# Build 273

Uploaded to TestFlight from `paper-v2-tokens` at c60b898b on 2026-11-18 (PR #563).

- More menu (owner feedback: "a lot of everything is extremely hard to navigate"): with the bottom bar on, the menu More opens no longer repeats the bar's tabs; it lists only the other places.
- Places with no Paper menu row or parent screen for the role (for a technician: Estimates, Invoices, Properties, Reports and others) moved out of Settings › Other places into the menu's last group, "Everything else". Settings on iPhone is settings only. iPad keeps Other places.
- The menu's foot shows Notifications and Settings as worded buttons instead of a bare bell and gear. This departs from Paper 29N, which draws them icon-only.

Checks: 1,385 unit tests pass (1 skipped); stock-control lint 0; drawer, tab bar and adaptive-controls UI classes 23 run, 0 failures (2 skipped). The full UI suite with the on-screen keyboard is still running against build 272's code: 300 passed, 0 failed so far. Not tried on a real phone or account.
