# Tap recovery store prototype — not wired or release-ready

Base: iOS Tap reader isolation branch `9a4c96f`. The Tap build policy is unchanged and remains disabled. This store is not referenced by the app's payment controller, does not initiate payments, and is not a recovery feature.

The prototype stores stable origin, organization, actor, invoice, amount, currency and optional canonical attempt ID. It deliberately stores no client secret, card data, or SDK continuation. A hold without an ID represents a lost preparation response and cannot be resolved by the current read-only server API. A hold is only removed by an exact ID and amount/currency check, and the caller must independently establish a current authorized session and authoritative canonical receipt. Future integration must gate every payment effect on successful store writes, fail closed on inaccessible/corrupt storage, make receipt verification mandatory, and address termination at every boundary. This prototype does not establish crash/power-loss durability, physical-device behavior, production backend support, or entitlement/merchant readiness.

Checks on 2026-11-03, without simulator, network or live charge:

- `xcrun swiftc docs/design/evidence/tap-recovery-prototype/store-check.swift Thorbis/Sources/TapRecoveryStore.swift -o /tmp/tap-recovery-foundation-check && /tmp/tap-recovery-foundation-check` printed `tap recovery foundation checks passed`. It exercises a new store instance, actor and invoice isolation, immutable attempt identity, mismatched receipt/actor, successful exact clear, corrupt input, and a write failure.
- `xcrun swiftc docs/design/evidence/tap-recovery-prototype/process-check.swift Thorbis/Sources/TapRecoveryStore.swift -o /tmp/tap-recovery-process-check`, followed by `write` and `read` in two distinct executable invocations against the same temporary file, printed `hold restored in separate process`. This checks normal process restart, not crash or power loss.
- `ThorbisTests/TapRecoveryStoreTests.swift` was added but XCTest was not run; the simulator was not used.

Outstanding: use a reviewed durable storage protocol and canonical server lookup bound to the exact authenticated tenant, actor, job and invoice; qualify process termination, concurrent writers, protected-data behavior, storage errors, session revocation and receipt confirmation on device. A successful test of the standalone store is not evidence these properties hold in the app.
