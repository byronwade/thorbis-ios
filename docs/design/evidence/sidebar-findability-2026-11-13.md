# Sidebar findability, 13 November 2026

The phone drawer and iPad sidebar use the shared `PlacesList`. A multi-place
heading currently opens the first place when its label is tapped and expands
only when its small chevron is tapped. The candidate makes the whole heading
expand or collapse, starts Work expanded, remembers the Work preference, and
keeps each authorized destination in its group. Single-place groups remain
direct links. The collapsed current place is included in the accessibility
hint. Custom, favorite and device-only sections remain available.

The earlier candidate had four passing focused iPhone UI tests on an earlier
release base, plus two passing iPad disclosure tests; a separate iPad test
failed before reaching the disclosure. Actual VoiceOver, largest text and a
permission-limited single-place UI were not verified. The candidate was
cherry-picked onto release `281c5f7b` and reviewed independently; that review
found no concrete feature or permission regression. The fresh build and tests
on this exact release-based candidate are pending. This record does not claim
Paper parity or TestFlight delivery.
