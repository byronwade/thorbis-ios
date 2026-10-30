# Build 98 — job photo organization

Runtime source: `05fe82006c68ce31db727670dc1f587271446ed9`.

Job photos are grouped by actual capture date, with a separate group for missing or invalid dates. At accessibility text sizes, photo filters and captions reflow, and capture actions come before pending uploads and the grid. An empty filter now offers a visible Show all photos action. The release includes a catch-up What's New entry for the build 97 price-book visuals.

A clean integrated iPhone SE run passed 12 focused unit tests and 7 UI tests. An earlier clean run failed two UI cases; investigation reproduced the empty-filter action obscured by the fixed bar, and the corrected source places it directly below the filter. The second failure was caused by an overshooting test swipe; revised tests opened the library picker and document menu. Independent source reviews found no confirmed blocker. The signed archive passed frozen-source, strict-signature, app/widget version, preview-exclusion and Tap gating checks.

Xcode reports upload succeeded at 06:55 EDT on 30 October 2026 and Apple processing started. **Processing completion, tester group assignment and testing notes are not verified** because local browser control was unavailable. Do not treat this record as proof of tester availability.

Real camera capture, photo opening and retagging, iPad, VoiceOver, RTL, physical devices and large-collection performance remain unverified. The activity provenance and customer-history candidates are not included. Tap to Pay remains disabled pending qualification. The distribution export was not independently audited; Xcode reported a missing StripeTerminal dSYM.
