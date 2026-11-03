# Held customer-owner proof boundary

The customer owner is not wired into production screens. Production builds now omit its synthetic `completeLive` evidence case. As a result the owner cannot use a caller-asserted complete result to clear a denial; a scope requiring live revalidation remains live-only through this owner. DEBUG retains the case strictly for synthetic tests.

This is not a general security boundary: the underlying quarantine coordinator still exposes its outcomes to other in-process callers, and limited-live evidence is also caller-supplied. The backend does not currently establish a scope-bound complete compilation. Do not merge or expose this experiment as a complete feature.

- Swift 6 compiler probes: `/private/tmp/customer-owner-proof-boundary.log`; corresponding source hashes: `/private/tmp/customer-owner-proof-boundary-manifest.txt`. Production-mode source compiles, while `customer-owner-unverified-proof-probe.swift` correctly fails to compile because the synthetic case is absent. The DEBUG standalone harness passes with test-only SavedCopies stubs. Before this boundary, the same production probe compiled successfully.
- The targeted DEBUG iOS transport test passed after this change: `/private/tmp/thorbis-owner-proof-ios.log`; result bundle `/private/tmp/thorbis-owner-ui-derived/Logs/Test/Test-Thorbis-2026.11.03_10-48-44--0500.xcresult`; source hashes `/private/tmp/thorbis-owner-proof-ios-manifest.txt`. This tests one request and inherited live-only transport, not complete authorization.

Actual server-issued evidence, production scope/session and API generation binding, all visible copies, cached-key isolation and denial recovery, real Keychain/app-group behavior, and signed-device lifecycle testing remain open. The compiler probe is not an iOS Release archive or production integration test.
