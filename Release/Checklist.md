# Release gates

Status: release preparation. No box below asserts a completed external action. Record evidence
(commit, build number, device/OS, date, outcome) beside each checked item.

## Local candidate

- [x] Core package tests pass (`swift test --package-path Core`, 30 tests, Swift 6.1 on Linux).
- [ ] `xcodegen generate` and a generic simulator build pass with `CODE_SIGN_IDENTITY=-`.
- [ ] App-hosted unit tests (`ThorbisTests`) and UI smoke tests (`ThorbisUITests`) pass on an iPhone simulator.
- [ ] Walk Today, Jobs, job detail (drive → arrive → work → pause → resume → complete), Customers, Money,
      Inbox, Search and Account on iPhone and iPad with `--ui-fixture`.
- [ ] Accessibility pass: VoiceOver, Dynamic Type up to AX5, Increase Contrast, Reduce Motion, light and dark.
- [ ] Release binary contains no fixture data (checked by `scripts/testflight.sh`).
- [ ] Inspect app icon, display name, version and build on the home screen and in Settings.

## Backend

- [ ] Sign in with a real Thorbis account against `https://app.thorbis.com`; organization picker shows
      only the user's workspaces; switching workspace reloads data.
- [ ] Job progress, schedule, assign, notes, photo upload (JPEG ≤ 15 MB), complete, cancel and the
      completion invoice work against production with a test workspace.
- [ ] Estimate send/approve/decline and invoice issue honour revision checks (a stale revision shows the conflict).
- [ ] Account deletion: production requires recent re-authentication (BYR-446). Until the API accepts a
      native re-authentication, the app shows the server's refusal. App Review requires in-app deletion, so
      this must ship before App Store submission (TestFlight is not blocked).

## Apple account

- [ ] Developer membership active; bundle id `com.thorbis.field` registered to the team.
- [ ] App Store Connect app record "Thorbis" created with that bundle id, primary language English (US), SKU `thorbis-ios`.
- [ ] Xcode signed in to the team; automatic signing creates the distribution certificate and profile.

## TestFlight

- [ ] `APPLE_TEAM_ID=… BUILD_NUMBER=… scripts/testflight.sh` archives and uploads; record build number and upload time.
- [ ] Build finishes processing; export compliance answered (the app declares no non-exempt encryption).
- [ ] Internal testing group created and Byron added; build installed through the TestFlight app.
- [ ] On device: sign in, camera permission prompt and photo attach, call/text/email/directions links,
      offline banner and retry, sign out.

## Submit (later)

- [ ] Account deletion works end to end in production.
- [ ] Store listing, screenshots, privacy answers ([Privacy.md](Privacy.md)), age rating, review notes
      and a review demo account ([AppStore.md](AppStore.md)).
