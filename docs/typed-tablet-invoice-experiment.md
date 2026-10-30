# Tablet invoice navigation experiment — held

This checkpoint is a DEBUG-only experiment. Do not enable or release it.
It does not establish safe invoice selection for tablet Schedule.

The tablet Jobs test opens the Invoice navigation bar, returns with the Back
button, and verifies the selected invoice in the payment sheet. It passed in
`/private/tmp/thorbis-typed-tablet-detailassert.xcresult`.

The tablet Schedule test taps a hittable invoice row but the Invoice navigation
bar does not appear. It failed in the same result bundle. A previous version of
the test incorrectly accepted text from the underlying row as proof that the
invoice opened; do not weaken the explicit navigation-bar and Back assertions.
An earlier experiment returned to a payment sheet for the wrong invoice. The
distinct nested route type in this checkpoint has not fixed the opening failure.

The tablet outer stack and Schedule detail stack must be redesigned or otherwise
proved to route and return within the correct presentation owner before this can
ship. Verify actual invoice opening, cancel/back and interactive swipe, matching
invoice identity and authoritative balance on return, session and permissions
changes, VoiceOver and keyboard activation, and every job entry root. Continue
to keep production on the existing routing until these checks pass.

The diagnostic probe writes only in DEBUG preview with the explicit
`--typed-route-diagnostics` launch argument; remove it before release.
