# Native iOS app (SwiftUI)

`apps/ios` is the native SwiftUI field app built from the Paper "Thorbis Mobile" page
(file "Thorbis — Schedule Redesign", page B-0, 390×844 artboards). It is a thin client of the
canonical API (`services/api`, OpenAPI in `services/api/openapi.json`). No business rules live here.

- Generate the project with `xcodegen` (the `.xcodeproj` is not committed).
- Apple commerce rules from `apps/mobile/AGENTS.md` and ADR-0018 apply: no plan purchase,
  upgrade, pricing, StoreKit/IAP or external checkout surfaces, and no arbitrary URL opening.
- Auth: production uses the Better Auth session cookie (`/api/auth/sign-in/email`). Against a
  loopback API the app offers "Local dev identity", which sends the `x-thorbis-*` dev headers that
  only `createDevHeaderIdentityResolver` accepts.
- Not built by Thorbis CI; build locally with Xcode.

## What's new notes (every update)

People see a What's new sheet once after each update (design.thorbis.com MA-19..MA-22). The notes
live in `Thorbis/Sources/ReleaseNotes.swift`.

- Every PR that changes what people see adds a new entry at the top of `ReleaseNotes.all` with a
  unique id (`yyyy-MM-dd-short-name`) and today's date. Unshipped entries fold into one sheet.
- Write what the person can now do, in domain words: title at most 40 characters, one sentence
  at most 110, at most five highlights; count anything smaller in `fixes`. No ticket ids, code
  names, batch numbers or "bug fixes and improvements".
- Before uploading a TestFlight build, check that every user-visible change since the last build
  has a note; add a catch-up entry if one is missing. `WhatsNewTests` enforces the rules.
- Preview the sheet with `--paper-preview --paper-preview-screen whats-new`.
