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
