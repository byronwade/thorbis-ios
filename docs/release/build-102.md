# Build 102 — search from the bottom bar

Runtime source: `7614b35a7a9fb4430b0ee150959c7c1ba096bdeb` (`main`, PR #132).

- **Bottom search.** On iPhone, Search no longer opens a sheet. The Search circle widens into a field at the bottom with the keyboard up, and + becomes Close. Recent records, then results, rise in a drawer above the field over a frosted screen. A picked result opens on the place showing.
- **Menu fix.** The place list sizes to its rows, scrolls inside the card and is clipped to its rounded edge. Build 101 drew the last rows past the card on accounts with many places.

Everything in build 101 is included. Unmerged `codex/*` work from builds 98–100 is not.

`scripts/testflight.sh` ran 427 simulator tests with no failures, `scripts/lint-stock-controls.sh` passed, the Release archive succeeded, and Xcode reported **Upload succeeded** at 12:31 EDT on 30 October 2026.

**Processing completion, tester group assignment and What to Test are not verified.**

Search with a live server, dragging the drawer closed, the menu overflow on a real owner account, VoiceOver, iPad and physical-device behaviour are unverified. Screens were checked in the iPhone 17 Pro simulator with `--paper-preview` only.
