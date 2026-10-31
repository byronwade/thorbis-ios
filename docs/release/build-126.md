# Build 126 — simpler drawer, in-between states

Runtime source: `f17998d` (`release/104-integration`).

- **Simpler drawer** (PR #210), after the owner called build 125's drawer "crazy busy": a 22pt one-line business title; no Now card and no saved-work row (saved work is a dot and an item on the gear); at most 5 role-based rows (Tech: Today, Jobs, Customers, Inbox; Office: Schedule, Jobs, Customers, Money, Inbox; Owner: Home, Jobs, Customers, Money, Inbox) plus an "All places" disclosure; up to 5 plain recents; dots only for Inbox unread and saved work. Every pushed screen shows the menu circle before a compact Back; customer mode never does.
- **In-between states** (PR #208): empty states naming one action, skeleton loading rows, calm offline/error strips, glyph-led status picker, toast for estimate-line undo, wrap-up haptic, darker in-progress/unscheduled glyphs.

**Tests run: navigation, menu, controls, glyph, appearance and WhatsNew unit suites only; UI suite compiled, not run, at the owner's request.** The stock-control lint passed (0), the Release archive succeeded, and Xcode reported **Upload succeeded** on 31 October 2026.

Known: the owner says the sheets still look bad; the v2 redesign (Linear grammar on design.thorbis.com tokens) is rebuilding them.

**Processing, tester groups and What to Test are not verified.**
