# Estimate description loss — held candidate

This branch is work in progress and is not qualified for merge or TestFlight.
It starts at release record `8eb4e32`. The staged source and test diff before
this note had SHA-256 `328004503854397c218aa624ef6c1ed8994d72a89f6e42933799eb4f20a96e1a`.
`project.yml` was `d70032a3cac9ded75c8599814df84d22e00d7e63c24b406875b63354added94c`,
and the generated Xcode project was `bb6864d643c01d98ae15aa249fa080b86f9cf9b6927eec4c73b10a295c6a04ec`.

The candidate retains custom and credit descriptions instead of silently
truncating them. It enforces the current 200 UTF-16-unit estimate bound,
identifies overlong Price Book source snapshots, and attempts to keep the
correction and Save action visible with the keyboard open. It does not add
server support for long descriptions or durable draft storage.

Evidence and limitations:

- `/private/tmp/thorbis-textloss-red2.log`: the custom-line preservation test
  failed on the original implementation because the ending was truncated.
- `/private/tmp/thorbis-textloss-warning-credit-red.log`: the credit-line
  preservation test failed on the original implementation for the same reason.
- `/private/tmp/thorbis-textloss-revision-red.log`: the revision test failed
  before the guard for both main and option catalog lines. Its credit test
  passed after removal of the credit truncation. Its UI selector failed because
  XCTest rejected an identifier longer than 128 characters.
- `/private/tmp/thorbis-textloss-final.log`: 35 unit tests passed on a source
  snapshot built before the final exact-error assertions and re-scroll changes.
  The first new-estimate UI test was interrupted following a simulator renderer
  crash; the log reports an unexpected exit and restarts. The diagnostic is
  `~/Library/Logs/DiagnosticReports/SimRenderServer-2026-11-02-180528.ips`.
  The revision UI test failed before entering text because its `builder-line`
  preview has unsupported provenance and disables editing. Neither test
  establishes that the keyboard layout or warning is usable.
- Follow-up fixture correction: the revision UI test now opens
  `estimate-revision`, selects the `Compressor diagnostic` line, and explicitly
  asserts it is enabled. That preview uses the sent `PaperPreview.estimate`,
  whose main and option lines have supported manual or Price Book source
  identities; unlike `builder-line`, it does not use `optionsEstimate`'s
  incomplete Price Book source. This is a source inspection, not a test pass.
  The corrected test remains unrun while the simulator is unstable.
- Follow-up on `d212d14`: 35 focused unit tests and the corrected revision
  keyboard test passed. The new-estimate UI test failed: its accessibility
  hierarchy and recording showed the floating Done control still overlapped
  Save. A geometry regression reproduced that overlap before the fix
  (`/private/tmp/thorbis-textloss-overlap-red.log`). After adding 48pt of
  keyboard-only footer clearance, both new and revision keyboard UI tests
  passed (`/private/tmp/thorbis-textloss-overlap-green.log`, exit 0). Each
  checks that Save and Done do not intersect and that tapping Save displays
  the length warning; the new-estimate test also checks the complete draft
  text remains in the field. The verified staged code/test diff had SHA-256
  `4b571584463091a56061b4c4da508d2851a161442f321024bfe1b2154bc0b31b`
  on base `d212d14`. This is one iPhone 17 Pro simulator at default text size;
  large text, a small device, compact iPad windows and real-server saving
  remain unverified.
- On iPhone SE (3rd generation) with the largest accessibility text, the
  first test failed before reaching the editor: the custom-item action grew
  to roughly 2,236pt for the long search and the picker did not close
  (`/private/tmp/thorbis-textloss-small-large.log`). The picker now displays
  a stable action title and a two-line preview while passing the full query
  to the line. `/private/tmp/thorbis-textloss-small-large-fixed2.log` passed
  (exit 0): the action was under half the screen height, the full draft text
  persisted, Save and Done did not intersect, and the warning and Save were
  hittable. The staged app/test diff hash was
  `d49faed8fe7485428210126253157f06903b122304f9ac622e614ff515c77dcb`
  on `ea94efd`. The passing run did not retain a screenshot; it does not prove
  absence of visual clipping or adequate editor space at that text size.
- A preceding UI recording showed the number keyboard covering Save
  (`/private/tmp/textloss-fail-frame.png`). The candidate's keyboard-aware
  layout has not been qualified against a completed UI run.

Before integration: run focused tests on this exact source; repair the revision
test fixture using a supported, editable estimate without weakening permission
or provenance checks; verify warning visibility, keyboard reachability,
repeated scrolling to an already expanded line, multiple invalid lines, and
correction at large Dynamic Type and on a small phone/iPad window. Review the
full diff independently, and confirm the backend contract and TestFlight build
qualification separately. Do not infer a durable draft or successful server
save from preview tests.
