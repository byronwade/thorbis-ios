# Thorbis iOS (SwiftUI)

Native field app: sign in, Schedule, Jobs (grouped by status), Job details with status transitions,
Customers (A–Z) and customer detail, More menu. Design source: Paper → "Thorbis Mobile".

```sh
cd apps/ios
xcodegen
xcodebuild -project Thorbis.xcodeproj -scheme Thorbis -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath build build
```

Local API (in-memory, header identity): run the memory composition of `services/api` on
`127.0.0.1:8788`, then pick **Local dev identity** on the sign-in screen. The API base URL can be
changed on the sign-in screen (stored in UserDefaults).
