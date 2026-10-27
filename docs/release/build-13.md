# Thorbis 1.0 (13) — Thorbis branding and Paper composer

Date: 2026-10-27. Bundle `com.thorbis.field`, Apple ID `6827337706`, team `T677262U5B`.

## Changes

The sign-in and customer estimate header use the official Thorbis blue shield and wordmark lockup. The shield asset is byte-identical to `Thorbis-TanStack/apps/showcase/public/logo-source.png` (SHA-256 `07b9cb8803e215ad6a45b17daadd05ef27e0a72799c9cf0e83310a848273d737`).

The native customer estimate flow displays the issued estimate and handles token-scoped approval, decline, and change requests with revision and nonce checks. The Paper job composer collects a customer, title, and description, then opens the created job. Schedule and technician assignment remain available from job details. The canonical create endpoint has no priority or attachment/mention/checklist/camera fields, so those Paper toolbar actions are not represented as saved behavior.

## Verification

- Full Swift 6 iPhone 17 Pro / iOS 26.3.1 simulator suite: **192 tests passed, 0 failed**. Result bundle: `/Users/byronwade/Library/Developer/Xcode/DerivedData/Thorbis-dmuwxdzkujtkngcfxjqjbnvsarbv/Logs/Test/Test-Thorbis-2026.10.27_05-11-56--0400.xcresult`.
- Release iOS archive `/private/tmp/Thorbis-13-release.xcarchive` succeeded as version `1.0`, build `13`; `codesign --verify --deep --strict` passed for team `T677262U5B`.
- The read-only iPhone Paper preview was inspected on the simulator. It uses sample data, intercepts all requests, and rejects writes.
- Release iOS device build succeeded; the signed archive was uploaded to App Store Connect.

## Distribution

`xcodebuild -exportArchive` reported **Upload succeeded** and **Uploaded package is processing** at 5:20 AM EDT on 2026-10-27. App Store Connect has not been checked for processing completion. Hayley Wade (`hayleywoods15@gmail.com`) is already listed in the external tester group, but Build 13 has not been assigned and no new invitation has been confirmed. External beta review still needs the App Review contact and demo-login details documented in `apple-record.md`.

This incremental beta does not establish full Paper/TanStack parity or authenticated live-device validation. See `beta-coverage.md` for remaining work.
