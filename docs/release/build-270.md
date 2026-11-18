# Build 270

Uploaded to TestFlight from `paper-v2-tokens` at 1db1ecd9 on 2026-11-18 (PR #563).

Navigation and real-data fixes after the owner tested build 269 on a phone (light mode, a demo company with about 600 unscheduled jobs and long names).

- Bottom tab bar is the iPhone default (labelled; technician and office: Schedule, Jobs, Customers, Messages, More; owner: Dashboard, Schedule, Jobs, Money, More). Sidebar remains under Settings › Menu and start screen › Navigation. iPad unchanged.
- Segmented tabs redrawn: quiet track, chosen segment raised in white.
- Messages: one row of filter chips; folders and less-used filters under "…".
- Schedule: three oldest waiting jobs with See all and a searchable "Waiting for a slot" page; banner spacing.
- Job page: bar title bounded between its circles; on-site times past a day read in days.
- Lock Screen card fits iOS's 160pt and is not shown for a step older than 16 hours.
- Long-data sweep of all 187 preview screens: about 30 fixes (capped lists with See all, one-line rows, compact row pills, durations and ages with larger units, grouped counts).
- Light mode: white drawer, bottom bars take their page's ground; sheet tops aligned; failed-save banners red; Customer view row on a job's Money section; fitting empty-state glyphs.

Not in this build: one signature for several estimates (still in progress).

Checks: 1,373 unit tests pass (1 skipped) on this commit; stock-control lint 0; large-company launch check passes for owner, office and tech. The full UI suite had just started on this commit at upload. Not tried on a real phone or account.
