# Inbox day grouping implementation plan

**Goal:** Make notices easier to scan using their actual received dates, without inferring notice types from title text.

**Architecture:** Insert a noninteractive heading when the next visible notice differs in local calendar day from its immediately preceding visible notice. Preserve server order, unread state, navigation, pagination, loading and permissions. Missing or malformed timestamps group as Date unavailable; never substitute a fabricated date. Consecutive unknown dates share a heading. Group headers are recalculated for the active filter and loaded pages.

**Design:** Adapt the existing Thorbis grouped-list pattern used in the Paper Schedule artboard to the real staff-notice feed. Paper's Messages screen is a different channel-based feature; do not invent channels, event kinds or decorative notice-type icons.

**Verification:** Regression tests cover local-day boundary, date/year, same-day, invalid and unknown adjacency, date changes in filtered order; UI verifies grouped notices remain openable and unread text persists. Retain reportable gaps for accessibility, RTL and live data unless tested.
