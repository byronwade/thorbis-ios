# Thorbis 1.0 (12) — estimate revision and option packages

Date: 2026-10-27. Bundle `com.thorbis.field`, Apple ID `6827337706`, team `T677262U5B`.

## Changes

Build 12 includes the native estimate replacement-draft editor for sent and declined estimates. It edits the primary scope and up to eight option packages, preserves manual and exact Price Book revision provenance, honors `estimate_option_signing` and `estimate.discount`, and keeps local edits available after a stale-revision conflict. Approved estimates remain on the change-order path. The editor does not send the replacement draft automatically.

The login mark and app icon use the authentic Thorbis shield from the TanStack repository. Both source files match at SHA-256 `07b9cb8803e215ad6a45b17daadd05ef27e0a72799c9cf0e83310a848273d737`.

## Verification

- Full Swift 6 simulator suite: **174 tests passed, zero failed** on iPhone 17 Pro / iOS 26.3.1. Result bundle: `/Users/byronwade/Library/Developer/Xcode/DerivedData/Thorbis-dmuwxdzkujtkngcfxjqjbnvsarbv/Logs/Test/Test-Thorbis-2026.10.27_03-54-45--0400.xcresult`.
- Release iOS device build succeeded with code signing disabled for the compile check.
- Signed archive at `/private/tmp/Thorbis-12-release.xcarchive`; app plist reports bundle `com.thorbis.field`, version `1.0`, build `12`. `codesign --verify --deep --strict` passed for team `T677262U5B`.
- Read-only iPhone 17 Pro estimate editor preview: `/private/tmp/thorbis-estimate-revision-review-fixed.png`. It verifies the interface with sample data, not an authenticated live estimate write.

## Distribution

`xcodebuild -exportArchive` reported **Upload succeeded** and **Uploaded package is processing** at 3:58 AM EDT on 2026-10-27. Build 12 is not yet available for tester assignment while Apple processes it. Hayley Wade (`hayleywoods15@gmail.com`) is in the external tester group, but assignment and invitation delivery are not confirmed. External beta review also needs the App Review contact and demo-login details documented in `apple-record.md`.

This is an incremental staff beta, not complete Paper/TanStack parity or authenticated device workflow validation. See `beta-coverage.md` for remaining work.
