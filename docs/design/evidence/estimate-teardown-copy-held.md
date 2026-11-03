# Held estimate teardown preservation

This candidate captures the current job-estimate draft in the existing original-scope process buffer before trying to install a separate create-only recovery copy when the editor is torn down after an unsuccessful save. Ambiguous installation or readback retains the process buffer and the attempt identity. It does not replace the canonical draft.

The standalone check can be run from the repository root:

```
swiftc Thorbis/Sources/EstimateRecoveryCopyStore.swift Thorbis/Sources/EstimateRecoveryCopyAttempts.swift Thorbis/Sources/VolatileDraftRecovery.swift Thorbis/Sources/EstimateTeardownPreservation.swift scripts/estimate-teardown-preservation-check.swift -o /tmp/thorbis-teardown-copy-check
/tmp/thorbis-teardown-copy-check
```

The check covers the actual copy store and process-local attempt registry, including a readback failure after installation, same-ID retry, scoped memory, and refusing installation if the memory capture fails. It does not exercise the SwiftUI editor, application session transitions, app termination, actual device protection, power loss, or multiple processes. No Xcode build or UI tests have run for this candidate.

Hold this candidate: explicit sign-out, workspace switching, and automatic session expiry are not yet coordinated with a live editor or in-flight create/link request. Memory cleanup after confirmed preservation, failed-storage user recovery, identity reauthorization, concurrency, protected-copy retention, and durable cleanup still need an integrated design and tests. Existing estimate create/link atomicity limitations are unchanged. Do not merge or present this as complete recovery.
