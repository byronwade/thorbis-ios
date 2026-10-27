# Build 2 — native authentication Origin fix

Physical-device testing of build 1 reported `Missing or null Origin` during login. The native URLSession transport omitted Origin. Better Auth requires a trusted origin on cookie-bearing mutations, including workspace activation and sign-out, even though the initial cookie-free sign-in can proceed without it.

The canonical API transport now supplies the validated base origin on unsafe HTTP methods. It strips a trailing slash and retains debug loopback ports. GET/HEAD/OPTIONS and the separate signed-storage transport are unaffected. No server CSRF checks were weakened.

## Evidence

- With a synthetic invalid cookie, production `POST /api/auth/sign-out` returned 403 `MISSING_OR_NULL_ORIGIN` without Origin and 200 success with `Origin: https://app.thorbis.com`. No real credentials or session cookies were used.
- A standalone Swift 6 harness compiled the actual API client and URLProtocol fixture. All four mutation checks failed before the fix and passed afterward. Expanded checks passed in Debug and optimized Release for canonical mutation origins, read isolation and origin normalization.
- XCTest regression cases added for sign-in, workspace activation, sign-out, ordinary API mutation, trailing slash, read requests and debug loopback ports.
- Independent read-only review found no blocking issues.

## Release verification

Full Access was restored and the previously blocked checks were rerun successfully:

- 101 iOS tests passed, zero failures, on the dedicated Thorbis Beta iPhone simulator.
- 20 Release API tests passed, zero failures, including production Origin behavior.
- Signed archive succeeded at `/private/tmp/Thorbis-2-full.xcarchive`; strict codesign verification passed and the archived CFBundleVersion is 2.
- Source fix commit: `3e9303e`; pushed to draft PR #2.

Upload succeeded at 20:33 EDT on 26 October 2026 (`EXPORT SUCCEEDED`). Apple processing is pending. Live physical-device sign-in still requires retesting with build 2.
