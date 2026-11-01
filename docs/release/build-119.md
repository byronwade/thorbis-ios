# Build 119 — on-site screen polish

Runtime source: `748a3e9` (`release/104-integration`).

- **On site** (PR #195): 18pt section rhythm and 14pt bottom-bar padding as in the OnSite mockup; the status line never starts a line with "·" (one fact per line at accessibility sizes); tool names wrap instead of shrinking; reach circles scale with text (44–64pt); "Wrap up · N left" splits onto two lines when it can't fit; the customer "Job texts" menu is a full 44pt target.
- Kept on purpose: "On the invoice" (parts aren't tagged yet, BYR-1599) and the header contact circles.

**No tests were run beyond WhatsNewTests, at the owner's request.** The stock-control lint passed (0), the Release archive succeeded, and Xcode reported **Upload succeeded** on 31 October 2026.

Not verified: Job texts hit area in Accessibility Inspector, accessibility-size shots of the full tool grid and wrap-up list, dark mode.

**Processing, tester groups and What to Test are not verified.**
