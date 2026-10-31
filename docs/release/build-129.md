# Build 129 — swipeable stop cards on Today

Runtime source: `a5287d4` (`release/104-integration`).

- **Stop cards** (PR #219), after the owner asked for left/right swipeable cards:
  - Today shows a horizontal pager of stop cards. It opens on the stop under way, then the next booked stop.
  - Each card shows "Stop N of M · time", the street, problem · customer, the status word, access facts (never the alarm code), Directions / Call / Customer view circles, and the one next-step commit.
  - A 16pt sliver of the next card shows. The pager sits 20pt in, so the drawer's edge swipe still works.
  - The day list stays below the pager.
  - A Cards/List toggle is saved per device. Techs default to Cards; office and owner default to List.

**Tests run: TodayStopCardsTests (10), WhatsNewTests (9), TodayStopCardsUITests (3: swipe, drawer edge drag, toggle). Release build checked; full UI suite not run, at the owner's request.** The stock-control lint passed (0), the Release archive succeeded, and Xcode reported **Upload succeeded** on 31 October 2026.

Not verified: VoiceOver adjustable paging with real VoiceOver, the Customer view circle end to end, iPad. The card commit says "Wrap up" without a count.

**Processing, tester groups and What to Test are not verified.**
