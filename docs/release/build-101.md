# Build 101 — floating bottom bar and pop-up menu

Runtime source: `464bb1a8f25aa894070a8c638ffe4f1629ea6f16` (`main`, PR #130).

The phone's side drawer and system tab bar are replaced by a floating bottom bar and a pop-up menu, laid out like Linear.

- **Bottom bar.** A capsule of pinned places ending in a switcher slot, with round Search and + on the same line. The selection pill slides between places.
- **Pop-up menu.** The switcher opens every place, with the business switcher on top and Settings and Search at the bottom.
- **Arrange in place.** The menu's sliders button lets people drag places between the bar and the menu, or reorder them. Changes save as they are made and are carried in the company layout.
- **Current job.** The job the person is on floats above the bar (not on Schedule).
- **Sync on Search.** A count while changes wait, a ring while syncing, and red when the server refused one.
- **+ follows the screen.** New customer on Customers, New estimate on Estimates, else New job. Long-press + and Search for shortcuts and recently opened records.
- Search opens with the keyboard up. Settings gains business setup, company details and payments for owners.

This build is cut from `main`. It does not include unmerged work on the `codex/*` branches that went into builds 98–100.

`scripts/testflight.sh` ran 427 simulator tests with no failures, `scripts/lint-stock-controls.sh` passed, the Release archive succeeded, and Xcode reported **Upload succeeded** at 12:06 EDT on 30 October 2026.

**Processing completion, tester group assignment and What to Test are not verified.** App Store Connect was not checked after the upload.

Long-press menus, dragging in the menu editor, the business switcher through `ThorbisMenu`, VoiceOver, iPad and physical-device behaviour are unverified. Screens were checked in the iPhone 17 Pro simulator with `--paper-preview` only.
