# Build 103 — modern pass 1

Runtime source: `bead5f4` (`main`, PR #134).

- Money, times and record numbers use Inter with tabular digits instead of Geist Mono.
- iPhone screen headers put the filter on the title's line; the empty row above the title is gone.
- Job header: only status is a pill; time and technician read as facts; the progress bar is removed.
- Offline job shows one banner. Money month rows show one amount per side. Customize menu wording matches the bottom bar.

Includes builds 101 and 102. Does not include the `codex/*` performance and job-document work (held on `codex/release-103-integration`), and does not fix the iPad invoice-selection blocker.

`scripts/testflight.sh` passed the simulator tests, the Release archive succeeded, and Xcode reported **Upload succeeded** at 13:37 EDT on 30 October 2026. Processing, tester assignment and What to Test are not verified.

**Build number note:** 103 is taken by this upload. The `codex/release-103-integration` branch must upload as 104 or later.
