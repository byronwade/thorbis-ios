# Build 116 — on-site wrap-up

Runtime source: `6397fad` (`release/104-integration`).

- **On site** (PR #189): "Before you wrap up · X of Y" built from job state (before/after photos incl. pending uploads, diagnosis note, customer approval with total, signature, payment due) plus any server closeout rule; each row opens the step that completes it. One bottom commit "Wrap up · N left" opens the next open step and becomes "Complete job" with one confirm when nothing is left and the server allows it. Call circle calls the office only. "On the invoice" shows issued invoice lines.
- **Closeout**: paying returns to the job; Thorbis buttons replace stock ones; closeout screen always in •••.

**No tests were run beyond WhatsNewTests, at the owner's request.** The stock-control lint passed (0), the Release archive succeeded, and Xcode reported **Upload succeeded** on 31 October 2026.

Backend gaps (BYR-1599): parts vs other invoice lines, office phone, hazards. Not verified: completing a job, signature capture, taking payment, tapping each wrap-up row.

**Processing, tester groups and What to Test are not verified.**
