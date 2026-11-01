# Build 120 — customer view closer to the mockups

Runtime source: `45c7dca` (`release/104-integration`).

- **Customer view** (PR #197): option list leads with a 30pt price and a 20pt name; "What's included" puts "Option N of M", the 30pt name and summary together, with Total on the same sheet (also on handoff and job documents); a "Back to options" circle when it is the first customer-mode screen; bottom actions sit side by side or stack at large text; the icon-only lock is a 44pt circle (unlock flow unchanged).
- **Job selector**: segments share the width; when a label can't fit it drops "· amount"/"· count" instead of cutting text (VoiceOver still reads it).
- Kept on purpose: amounts keep cents; no discount row, member-price text or unit words (no data).

**Tests run: WhatsNewTests, CustomerPresentationTests and three JobEstimateHandoffUITests only, at the owner's request.** The stock-control lint passed (0), the Release archive succeeded, and Xcode reported **Upload succeeded** on 31 October 2026.

Not verified: iPad, dark mode, back/lock circles in a real customer-mode session, the remaining handoff UI tests.

**Processing, tester groups and What to Test are not verified.**
