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
found no concrete feature or permission regression. This record does not claim
Paper parity or TestFlight delivery.

On candidate `a6e37f0c` (the subsequent commit only added this record), a clean
simulator test build succeeded using a locally cached Stripe Terminal 5.8.1
binary; the tracked package configuration remains unchanged. The focused
phone run passed 21 navigation and release-note unit tests and three of four
drawer UI tests. The remaining case failed before reaching the disclosure when
the simulator switched through another app while opening the drawer. Its
isolated rerun passed. See `/private/tmp/thorbis-sidebar-local-build-1113.log`,
`/private/tmp/thorbis-sidebar-current-test-1113.log` and
`/private/tmp/thorbis-sidebar-current-retry-1113.log`. This does not establish
the cause of the combined-run failure. On the same simulator build, three
focused iPad UI tests passed, including opening the web-aligned sidebar and
toggling the Work section: `/private/tmp/thorbis-sidebar-ipad-current-1113.log`.
The focused phone test launched with the largest accessibility text category
and passed its disclosure and Jobs navigation assertions:
`/private/tmp/thorbis-sidebar-large-test-1113.log`. A phone UI fixture granting
only job viewing passed a direct Jobs navigation check and verified the other
Work destinations were absent: `/private/tmp/thorbis-sidebar-single-place-1113.log`.
Actual VoiceOver focus and activation remain unverified: the available Xcode
26.3 simulator does not provide VoiceOver, and no physical iPhone is connected
for testing. XCTest verifies accessible labels, state and button taps, not
VoiceOver gestures. A physical-device VoiceOver check remains a follow-up.

The five phone UI cases, including the largest-text test, subsequently passed
together on the same release-based code:
`/private/tmp/thorbis-sidebar-phone-repeat-1113.log`. The earlier combined-run
failure remains recorded above; this repeat does not establish its cause.
