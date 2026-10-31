# Build 125 — side drawer menu

Runtime source: `198357f` (`release/104-integration`).

- **Side drawer** (PR #207), after the owner asked for the Claude / ChatGPT iOS menu instead of the bottom bar: a menu circle (with a blue dot when anything inside has one) on every root screen and a left-edge swipe on roots open a drawer that pushes the screen right as a rounded card. Drawer: business name + search circle, "Now" job row, "Saved on this phone" while syncing, Pinned (editable), Places, Recents (status glyphs, spinners), blue dots for Inbox unread, Needs attention and changed recents; ink "New job" (long-press for estimate/customer) and a gear for Settings / business switcher / Edit menu. Bottom tab bar, search circle and phone More screen removed; iPad sidebar unchanged.

**Tests run: PrimaryNavigationTests, MenuLayoutTests, WhatsNewTests (24); UI suite compiled, not run, at the owner's request.** Contrast 0 failures; the stock-control lint passed (0), the Release archive succeeded, and Xcode reported **Upload succeeded** on 31 October 2026.

Not verified: rewritten drawer UI tests, VoiceOver modal/escape/focus, Reduce Motion fade, Inbox dot on screen.

**Processing, tester groups and What to Test are not verified.**
