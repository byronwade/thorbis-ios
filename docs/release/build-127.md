# Build 127 — design.thorbis.com foundation

Runtime source: `3a4dd90` (`release/104-integration`).

- **v2 foundation** (PR #212), after the owner asked to "redesign everything to follow linear.app mobile app and design.thorbis.com" and said the fonts were too big:
  - Tokens follow design.thorbis.com: warm cream light sheet, Linear dark greys, weights 400/500, electric-blue accent, soft place marks.
  - Smaller type ramp: body 15, secondary 14, chrome 13, captions 12, detail titles 24, root titles 26. Customer-facing screens keep 17/56.
  - No separators or side rails.
  - Sunk fields and bevelled ink commits.
  - Status shown as a word (`StatusLabel`).
  - `ThorbisMenu` is now an anchored popover, including the status picker.
  - New `ThorbisModalSheet`; Assign tech, Pause job, Reschedule, Collect payment and confirms use it, and no commit is pre-disabled without a reason.
  - "Arrive" wording.
  - Drawer retoned.
  - Golden rules rewritten.

**Tests run: 38 unit tests in touched suites and one UI test (overflow popover → Reschedule); full UI suite not run, at the owner's request.** Contrast 0 failures; the stock-control lint passed (0), the Release archive succeeded, and Xcode reported **Upload succeeded** on 31 October 2026.

Not verified: the status popover may list fewer moves than before (screen pass checking); owner Home attention rows still lack words.

**Processing, tester groups and What to Test are not verified.**
