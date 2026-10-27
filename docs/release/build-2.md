# Build 2 — native authentication Origin fix (pending release)

Physical-device testing of build 1 reported `Missing or null Origin` during login. The native URLSession transport omitted Origin. Better Auth requires a trusted origin on cookie-bearing mutations, including workspace activation and sign-out, even though the initial cookie-free sign-in can proceed without it.

The canonical API transport now supplies the validated base origin on unsafe HTTP methods. It strips a trailing slash and retains debug loopback ports. GET/HEAD/OPTIONS and the separate signed-storage transport are unaffected. No server CSRF checks were weakened.

## Evidence

- With a synthetic invalid cookie, production `POST /api/auth/sign-out` returned 403 `MISSING_OR_NULL_ORIGIN` without Origin and 200 success with `Origin: https://app.thorbis.com`. No real credentials or session cookies were used.
- A standalone Swift 6 harness compiled the actual API client and URLProtocol fixture. All four mutation checks failed before the fix and passed afterward. Expanded checks passed in Debug and optimized Release for canonical mutation origins, read isolation and origin normalization.
- XCTest regression cases added for sign-in, workspace activation, sign-out, ordinary API mutation, trailing slash, read requests and debug loopback ports.
- Independent read-only review found no blocking issues.

## Release blocker

The current restricted task permissions prevent Xcode access to CoreSimulator and signing accounts. The XCTest run could not find its destination; signed archive failed with No Accounts / No profiles, and even unsigned asset compilation failed because Simulator runtimes were inaccessible. These are environment failures, not passing iOS verification.

Build 2 is not uploaded. Restore the Xcode access used for build 1, regenerate with XcodeGen, run the iOS suite, archive version 1.0 build 2, export using ExportOptions.plist, then confirm processed internal TestFlight availability. Do not claim a successful live login until the device is retested.
