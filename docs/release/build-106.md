# Build 106 — calmer job screen, Customer view, search and create

Runtime source: `9387ebe` (`release/104-integration`).

- **Job screen in three tabs.** Overview · Money · Activity replace the five tabs. Money lists estimates then invoices, each amount shown once; Activity holds notes, status changes and photos (PR #154, BYR-1596).
- **Customer view, one door.** One Customer view button on the job hands the phone to the customer for estimates and invoices (PR #153, BYR-1594).
- **Search and create from the bottom bar** (PR #148, BYR-1597) and the visual card rollout (PR #150).
- Current-job chip no longer covers the last row on More, and is hidden on Jobs.

Build 105 was never uploaded: its package download hung. This build includes everything planned for it.

**No tests were run for this build, at the user's request.** `scripts/lint-stock-controls.sh` passed, the Release archive succeeded, and Xcode reported **Upload succeeded** at 20:34 EDT on 30 October 2026. Xcode warned that symbols for StripeTerminal.framework weren't uploaded (no dSYM in the vendor binary); crash reports inside Stripe Terminal won't be symbolicated.

**Processing, tester groups and What to Test are not verified.**
