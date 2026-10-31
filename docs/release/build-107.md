# Build 107 — redesign and on-site toolkit

Runtime source: `e6822aa` (`release/104-integration`).

- **One design system everywhere** (Thorbis Design): one selector row per screen, one list row, status as a word, one black button for the next step. Lists, Today, customer profile (PR #164).
- **Job screen** titled by street; Overview shows office note, access, photos, latest activity, past visits, money and follow-ups. Once arrived it becomes **On site**: live timer, access/hazard strip, tools (Photo, Note, Measure, Scan tag, Checklist, Add part, Estimate, Return visit), "Before you wrap up" list and Wrap up (PR #163).
- **On-site tools**: data-plate scan, job checklists with readings, call/text the office, short video clips (PR #160).
- **Estimates and invoices** show every line in full; customers see "What's included" before approving (PR #161).
- Next stop card, voice notes and quick notes, "At this address", custom controls everywhere, place-aware search (PRs #156–#159). Sheet Cancel/Close pills no longer truncate (PR #162).

**No tests were run, at the owner's request.** The stock-control lint passed (0 occurrences), the Release archive succeeded, and Xcode reported **Upload succeeded** at 22:16 EDT on 30 October 2026.

Known: list rows can show through the gaps of the floating bottom bar while scrolling (fix in the next build). Live data-plate scanning, video upload, dictation and Tap to Pay need a real iPhone. Backend gaps are tracked in BYR-1599.

**Processing, tester groups and What to Test are not verified.**
