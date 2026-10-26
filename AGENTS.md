# Agent notes: Thorbis iOS

- Native Swift 6 / SwiftUI app, iOS 18. `project.yml` → `xcodegen generate`; never commit the `.xcodeproj`.
- Put logic in `Core/` (ThorbisCore) with tests; views in `Thorbis/Sources/<Feature>/`. Core must stay
  free of UIKit/SwiftUI so `swift test --package-path Core` runs on Linux
  (`docker run --rm -v "$PWD":/w -w /w swift:6.1-noble swift test --package-path Core`).
- The API is the authority. Never invent state locally; replace cached records with the server's response.
  Request shapes: path ids never repeated in the body, bodyless POSTs send `{}`, estimate send uses
  `expectedRevisionNumber`, invoice issue uses `expectedLinesRevision`, job progress uses `{to, arrival, pause}`.
- Auth is the Better Auth session cookie, kept in the Keychain per server. Sign-in sends an `Origin` header.
- Design: follow design.thorbis.com exactly (Native contract HIG-001–022). Colours come from
  `Assets.xcassets/Colors` via `Theme`; commit buttons are ink (`CommitButtonStyle`), accent is for
  pointers only, status is a word plus a symbol, system text styles only, 44pt targets.
- Apple commerce rules: no plan purchase, upgrade, pricing, StoreKit/IAP or external checkout, and no
  arbitrary URL opening. Outbound links go through `OutboundLink` (tel, sms, mailto, Maps) only.
- Fixture data (`FixtureTransport`, `--ui-fixture`) must stay inside `#if DEBUG`.
