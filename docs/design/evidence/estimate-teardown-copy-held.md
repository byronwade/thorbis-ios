# Held estimate teardown preservation

This candidate captures the current job-estimate draft in the existing original-scope process buffer before trying to install a separate create-only recovery copy when the editor is torn down after an unsuccessful save. Ambiguous installation or readback retains the process buffer and the attempt identity. It does not replace the canonical draft.

The standalone check can be run from the repository root:

```
swiftc Thorbis/Sources/EstimateRecoveryCopyStore.swift Thorbis/Sources/EstimateRecoveryCopyAttempts.swift Thorbis/Sources/VolatileDraftRecovery.swift Thorbis/Sources/EstimateTeardownPreservation.swift scripts/estimate-teardown-preservation-check.swift -o /tmp/thorbis-teardown-copy-check
/tmp/thorbis-teardown-copy-check
```

The check covers the actual copy store and process-local attempt registry, including a readback failure after installation, same-ID retry, scoped memory, and refusing installation if the memory capture fails. It does not exercise the SwiftUI editor, application session transitions, app termination, actual device protection, power loss, or multiple processes. No Xcode build or UI tests have run for this candidate.

Hold this candidate: explicit sign-out, workspace switching, and automatic session expiry are not yet coordinated with a live editor or in-flight create/link request. Memory cleanup after confirmed preservation, failed-storage user recovery, identity reauthorization, concurrency, protected-copy retention, and durable cleanup still need an integrated design and tests. Existing estimate create/link atomicity limitations are unchanged. Do not merge or present this as complete recovery.

## Held lifecycle barrier

The candidate now registers job-estimate editors with a process-local main-actor coordinator. Intentional sign-out and workspace switch check it before and after the device-unbinding await; an in-flight operation or failed draft persistence blocks the transition, and new editor submissions are blocked while the transition runs. Forced session invalidation requests preservation without preventing authority revocation. Settings and the workspace chooser show or retain errors for these routes.

The standalone coordinator check is `swiftc Thorbis/Sources/EstimateEditorLifecycle.swift scripts/estimate-editor-lifecycle-check.swift -o /tmp/thorbis-editor-lifecycle-check && /tmp/thorbis-editor-lifecycle-check`. It tests the coordinator callbacks only, including a changed safety result between checks; it does not exercise the real session, editor closures, async network calls, or SwiftUI lifecycle. Swift frontend parsing is not typechecking.

Still held: independently verify closure lifetime and exact editor state, all session and workspace transition entry points, device-unbind effects when the second check fails, error visibility in menu switches, forced invalidation during in-flight create/link, memory retirement and privacy at sign-out, protected-copy recovery and deletion, cross-process writers, and process death. No app build or simulator tests were run for this change.

## Device unbind and company-creation follow-up

The real unbind callback posts `/v1/devices/unregister`. If the second preservation check fails, this candidate requests push re-registration only while the captured actor, organization, origin, generation and unexpired authority remain current. Re-registration is best effort and is not proof the device was rebound. If identity changes during unbind, the transition aborts without asking to rebind the old identity.

The workspace menus now show a failure alert. After a successful company-create response followed by a failed switch, the form keeps that returned company ID with the originating actor and server and offers a switch-only retry. This is process/view-local: destroying the form or process loses that retry state. A lost or malformed create response can still represent a committed creation, and this change does not establish create idempotency or prevent duplicates in that case.

Four focused `SessionControllerTests` were added for failed post-unbind sign-out, failed post-unbind switching, identity loss during unbind, and one create followed by switch-only retry. They are unrun until simulator access is coordinated. The app and these tests have only been syntax-parsed, not typechecked or executed. Real push delivery, every workspace entry point, SwiftUI alert behavior, and company-form loss remain unqualified.
