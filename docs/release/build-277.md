# Build 277

Uploaded to TestFlight from `paper-v2-tokens` at 2d15859a on 2026-11-19 (PR #563).

- Menu cleanup (owner: "some spots are clipped off the screen, clean up the user profile side"): the foot is one row (initials, name, role, gear) that opens Settings, replacing the person line plus two buttons. Notifications is a row at the top of the list. A long company name wraps to a second line (three at accessibility sizes) instead of ending in "…"; initials stay inside their circles at large text; only the last 20pt of the list fades, so a row no longer looks half cut off.

Checks: 1,387 unit tests pass (1 skipped); stock-control lint 0; tab bar and menu UI classes 22 run, 0 failures (2 skipped, iPad only). The menu was checked in the simulator for all three roles and at an accessibility text size. Not checked on a real phone or a small phone.
