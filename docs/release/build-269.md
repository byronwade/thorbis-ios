# Build 269

Uploaded to TestFlight from `paper-v2-tokens` at 8ae38654 on 2026-11-18 (PR #563).

The cleanup pass asked for after build 268: one grammar per kind of element across the whole app, a simpler menu, and presenting all of a job's estimates.

- Buttons and controls: one ramp of heights (60, 50, 48, 44, 36), one chip, one field, one segmented track, one chevron.
- Alerts and messages: confirms are one centred card (60 call sites, five former system alerts); one banner, toast, empty state, field error and loading line.
- Headers and titles: one page title at one height, one section label, one sheet title, one task bar; about 32 bottom bars and 19 sheet tops moved onto shared pieces.
- Navigation: the menu lists Paper's rows per role (technician 10, office 12–13, owner 14 plus Jobs); removed places open from Search, Money, Team, Business settings or Settings › Other places. The gear opens Settings; the business name opens the switcher. One menu editor. The phone's floating New job pill is gone.
- Job More menu: Paper 21K's eight rows plus Add to job and Wrap up; other actions moved to the status, clock and person chips, the Share circle, Money and Add to job.
- Estimates: the customer view follows Paper 38B; Show customer on an estimate opened without a job finds the job through the customer's jobs and opens all of its estimates.
- Fixed: the customer's Estimates screen froze at the largest text size after Review; its button label falls back to "Review (n)".

Checks: 1,360 unit tests passed and the large-company launch check passed on the commit before the UI test fixes and release notes; the fixer built and ran its classes on its branch. An earlier partial UI run (223 tests) had 10 failures: 9 fixed or shown to be test-only, 1 ("Done above the keyboard" at largest text) fails because no software keyboard appears on the simulators. The full UI suite on this code had not finished at upload. Light mode not re-checked.
