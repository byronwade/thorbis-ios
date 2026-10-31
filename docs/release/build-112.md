# Build 112 — lock screen, widgets, sign-in and first-run

Runtime source: `d25f0d6` (`release/104-integration`).

- **Live Activity and Dynamic Island** (PR #178): street first, status word, timer, one next-step button (On my way → Arrived → Start); on site it names access facts on record without showing codes.
- **Widgets**: Today in small/medium/large, lock-screen accessories, new Next stop widget with the step button; techs see only their own jobs.
- **Control Center / Action button**: Next step and Next job controls. **Notifications**: Open / On my way actions (need server push categories, BYR-1599). **Siri**: On my way with confirmation; Today's schedule. **Spotlight**: street-first titles.
- **Sign in, company picker, onboarding** (PR #179): new look, errors under the field they belong to, Step N of 3, one button above the keyboard.
- **Empty, error and loading states**: one line + one action; plain-word errors (no signal, server, access, expired); camera and dictation Open Settings notices; skeleton rows; What's new restyled.

**No tests were run, at the owner's request.** The stock-control lint passed (0), the Release archive succeeded, and Xcode reported **Upload succeeded** at 01:58 EDT on 31 October 2026.

Not verified in the simulator: real lock-screen card, expanded island, placed widgets, Control Center, Siri, real push actions, camera/dictation notices in place.

**Processing, tester groups and What to Test are not verified.**
