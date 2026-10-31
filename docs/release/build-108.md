# Build 108 — every screen in the new look, dark mode and large text

Runtime source: `790035d` (`release/104-integration`).

- **Every remaining screen in the new look** (PR #167): Settings, Reports and Money, membership and equipment, the customer handoff and document book, New job / New customer / equipment / price-book editors, Book return visit, the schedule picker, Assign tech, Follow-ups, Price book, Message drafts, Fleet, Equipment, Agreements, Billing, iPad schedule column and sidebar.
- **Dark mode and large text** (PR #168): contrast fixes for red and blue text, the sync badge and selected segments; screens no longer wider than the phone at accessibility sizes; text wraps instead of breaking mid-word; customer screens put buttons after the content at large sizes; the On site toolkit reflows to 3 and 2 columns.
- Job Money tab rows in the new style; times read "10:30 a.m." everywhere; the bottom bar keeps its ground on every screen (PR #166).

**No tests were run, at the owner's request.** The stock-control lint passed (0), the Release archive succeeded, and Xcode reported **Upload succeeded** at 23:29 EDT on 30 October 2026.

Known at the largest text sizes: a strip of the Activity timeline under the composer, the On site status line wrapping the tech's name, and a tall customer header. iPad gets a full redesign later.

**Processing, tester groups and What to Test are not verified.**
