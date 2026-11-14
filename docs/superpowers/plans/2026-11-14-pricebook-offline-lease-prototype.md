# Price book offline lease prototype

This experiment lives exclusively in the test target and uses synthetic scopes and an isolated temporary directory. It is not connected to any production entry point or existing cache.

1. Write executable tests for dirty-before-request, restart, authorized commit, write failures, scope/nonce isolation, expiration, and legacy data; run against a deliberately nonfunctional prototype and observe failures.
2. Implement a minimal lease coordinator and file-store test fixture; rerun the focused tests.
3. Record limits: real app integration requires all network entry points to enforce the barrier, cross-process serialization, durable writes, trusted finite authority expiry, and migration. No offline scheme can detect revocation while disconnected.

Baseline: 6 simulator tests executed and failed at `begin()` returning nil in a deliberately unimplemented test-only stub. This baseline does not reproduce or test a production path.

The prototype green run executed 8 simulator tests with zero failures (result bundle `/private/tmp/thorbis-lease-green-1114.xcresult`). These tests exercise a synthetic test-only file store and coordinator. They do not establish production correctness.

Before any integration, identify and gate every price-book request and editor/browse entry point; establish a finite server-backed authority deadline and behavior for legacy leases; add real integration tests including denial during concurrent requests, process termination, all storage-failure combinations, user/organization/origin changes, and offline re-entry. A real design must serialize across all possible processes and bind its records to the actual authority and protected persistence. The prototype's atomic file write and readback do not prove power-loss durability, Keychain behavior, or file protection. Its digest is not authentication against an attacker who can modify both files. Wall-clock rollback and revocation while disconnected are not solved. An uncertain clean write can be readable after an authorized response although the caller receives failure; no durable success is acknowledged in that case.
