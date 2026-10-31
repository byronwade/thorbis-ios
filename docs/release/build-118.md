# Build 118 — large text and VoiceOver

Runtime source: `7eb2199` (`release/104-integration`).

- **Large text and VoiceOver** (PR #193): customer Call/Text/Email/Directions go two across at accessibility sizes; site notes stack under their label; Settings values wrap to 3 lines; commit-button icons scale with text. Contact, membership and location rows read as one VoiceOver item; invoice lines read "name, quantity N"; "Job texts" announces its value; Book job's "All customers" is a 44pt target.
- **Customer hand-back tests**: the DEBUG sample controls covered "Hand back"; they now sit above the navigation stack. The three hand-back UI tests pass.

**No tests were run beyond WhatsNewTests and the three hand-back tests, at the owner's request.** The stock-control lint passed (0), the Release archive succeeded, and Xcode reported **Upload succeeded** on 31 October 2026.

Not verified: VoiceOver turned on for real (checks came from XCTest audits), the Job texts hit area, dark mode.

**Processing, tester groups and What to Test are not verified.**
