# Build 117 — screens closer to the approved mockups

Runtime source: `dc67c22` (`release/104-integration`).

- **Mockup parity** (PR #191): Today rows 14pt so times stay on one line; Job's Share moves into ••• (always shown), "1 option" grammar, no double gap when there are no past visits; estimate, invoice and customer-view lines lead with a short name and explain underneath (no text dropped); customer view drops the duplicate "See what's included" link and hint, hides "1 ×"; Customer › Jobs notes show 3 lines.

**No tests were run beyond WhatsNewTests, at the owner's request.** The stock-control lint passed (0), the Release archive succeeded, and Xcode reported **Upload succeeded** on 31 October 2026.

Backend gaps: drive time, activity author, per-job photo count and paid amount, member discount. Not verified: share sheet from •••, dark mode, iPad option cards, the updated JobOverviewUITests assertion.

**Processing, tester groups and What to Test are not verified.**
