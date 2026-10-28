# Thorbis 1.0 (18): Paper mobile redesign

Date: 2026-10-27. Bundle `com.thorbis.field`, team `T677262U5B`. Built from `claude/paper-redesign` at `5448648` with PR #1's CI and upload script merged in (`6ee2589`).

Build 17 was rejected at export because that number had already been used in App Store Connect. The same commit was uploaded as 18.

## Changes

- **Navigation.** iPhone navigation is the native tab bar with Paper's technician dock: Schedule, Jobs, Customers, More and Search. The overlay menu and the Done-sheets are removed. The minimum OS is now iOS 18.
- **Tab screens.** Schedule (with On my way in Next up), Jobs, Customers A–Z, More, Search and Inbox use Paper's large-title layout.
- **Detail screens.** Job and customer detail, estimates, invoices, price book and closeout use the native back bar with Paper record headers.
- **Job tabs.** Estimates, Activity and Media were rebuilt. Closeout is now Paper's wrap-up checklist.
- **Text and color.** The type ramp scales with Dynamic Type. Links and tint use a contrast-safe brand text blue.

## Verification

- **Tests.** `scripts/testflight.sh` ran the full simulator suite before archiving (220 tests, as on the branch).
- **Archive and upload.** The Release archive and export succeeded, and Apple reported **Upload succeeded** and **Uploaded package is processing**.
- **Visual review.** Visuals were checked on iPhone 17 Pro and iPad Pro 13-inch simulators, in dark and light appearance and at the accessibility Large text size, using read-only preview fixtures.

## Distribution

Build 18 is processing in App Store Connect. Assigning it to tester groups was not done from here.

This build does not establish full Paper parity. See `docs/design/README.md` for the screens that still need server contracts.
