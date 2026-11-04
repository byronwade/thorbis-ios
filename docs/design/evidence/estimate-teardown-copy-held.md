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

## Created-company membership refresh

A switch-only retry now refreshes memberships from the server, checks the original actor, server and current session generation before and after the read, and opens only an ID in the refreshed membership list. It does not append an ID from an older response to another actor's organizations. Unrun tests cover a missing local membership and a different actor.

`APIClient.sendData` rejects an in-flight response when its request generation is retired. Consequently a company-create request that may have committed during session change can throw before returning its ID. This candidate prevents another create tap in the same visible form after any unconfirmed response and tells the user to check their company list. That hold is not durable across form destruction or process death; it does not solve server idempotency or make a later retry safe. App and UI verification remain outstanding.

The follow-up failure classifier permits retry after an explicit local session/server prerequisite failure or a selected 4xx rejection, and keeps the in-form hold for transport/cancellation, 5xx, and malformed success. A standalone classifier test passed; the actual SessionController 422/503 test is added but unrun. The assumption that each selected 4xx cannot follow a committed company creation requires server-contract verification. The in-form hold remains non-durable.

Endpoint review narrowed definitive remote rejections to 403 with one of the two Better Auth 1.6.26 organization-create denial codes for creation disallowed or organization limit. In the checked-out `packages/auth/src/auth.ts`, the organization plugin uses these defaults and the adapter has transactions enabled; the installed `better-auth` `plugins/organization/routes/crud-org.mjs` evaluates both denials before `adapter.createOrganization`. Other HTTP status/code combinations remain unknown, even 400/422, as their source and no-write semantics are not proven. This is source review, not hosted-version verification.

The initial `c633337` simulator run stopped in Swift compilation before any tests: `openCreatedCompany` assigned to catch's immutable `error` rather than `self.error`. The follow-up fixes that compile error. The first package attempt was terminated after an observed Keychain wait; the retry used the checked package cache and netrc provider. Logs `/tmp/thorbis-lifecycle-c633337-xcode.log`, `/tmp/thorbis-lifecycle-c633337-sample.txt`, `/tmp/thorbis-lifecycle-c633337-retry.log`; exact source `/tmp/thorbis-lifecycle-c633337-hashes.txt`.

Better Auth's checked-out 1.6.26 create handler defaults to activating the new organization; the follow-up sends `keepCurrentActiveOrganization: true` to avoid a server-side switch before the lifecycle barrier. The unrun create/failed-switch test asserts that exact JSON field and the client workspace. Local dependency/config source supports the field; hosted server version and actual server session behavior have not been verified here.

The frozen `6f70f1c` focused simulator run also stopped at compilation before tests: three catch blocks in the earlier recovery-copy UI assigned to the implicit catch `error` rather than `self.error` (`NewEstimateView.swift` lines 625, 693, 717). The follow-up fixes those three assignments. Log `/tmp/thorbis-lifecycle-6f70f1c-xcode.log`; hashes `/tmp/thorbis-lifecycle-6f70f1c-hashes.txt` matched after the run. No app test passed in either attempt.

The `9a40257` simulator run compiled the app and ran seven session cases: six passed, and the identity-loss case failed because its `previewForce` call does nothing without Paper Preview. The failure did not exercise expiry or generation retirement. Log `/tmp/thorbis-lifecycle-9a40257-xcode.log`; source hashes `/tmp/thorbis-lifecycle-9a40257-hashes.txt`.

The follow-up replaces that fixture with a real near-term session expiry while device unbinding is suspended, and checks that generation actually retires before asserting no rebind. This corrected test has not run yet.

The corrected real-expiry case passed on simulator at source `6b36d9a` (one case, 10.067 seconds; `/tmp/thorbis-lifecycle-6b36d9a-xcode.log`). All recorded source hashes matched after the run (`/tmp/thorbis-lifecycle-6b36d9a-hashes.txt`). The six other focused session cases passed in the preceding `9a40257` run; only the corrected test changed between those runs. These tests do not exercise real editor lifecycle UI, provider deployment, sign-out privacy cleanup, or cross-process persistence.

## Held process-memory retirement

Intentional sign-out and workspace change now attempt create-only protected copies of every process-held new-estimate draft and edited recovery copy before clearing those buffers. An ambiguous copy or unmatched pending attempt leaves all buffers held and blocks the transition. A live editor records its exact successfully saved draft at transition preparation and avoids redundant preservation for that same content when invalidation/teardown follows. Forced expiry is still not blocked.

`swiftc Thorbis/Sources/EstimateTransitionMemory.swift Thorbis/Sources/VolatileDraftRecovery.swift Thorbis/Sources/RecoveryCopyEditKey.swift Thorbis/Sources/EstimateRecoveryCopyAttempts.swift scripts/estimate-transition-memory-check.swift -o /tmp/thorbis-transition-memory-check && /tmp/thorbis-transition-memory-check` passed for failed writes, same-ID retry after an ambiguous write, orphaned attempts, and successful scoped memory retirement. This is a synchronous in-memory callback harness; the actual editor/session integration has not been compiled or run. No cross-process writer exclusion, power-loss durability, protection against external modification of the canonical draft after checkpoint, guaranteed notification re-registration, or complete recovery UI has been established. This remains held for independent review and app-level tests.

## Held reopen behavior

When the only alternatives are process-known automatic copies identical to the held in-memory draft and no canonical draft exists, the editor opens that draft directly. A differing copy, canonical draft, manually saved/promoted copy, missing process provenance, or failed read keeps the conservative recovery-choice path. Explicitly saved copies cannot later be reclassified as automatic in this process. Provenance is process-local, so after a relaunch the saved copy is offered as a recovery choice.

The standalone `estimate-automatic-copy-check.swift` passes for job scoping, explicit promotion, repeated automatic marking after promotion, and registry clearing. The existing parent-teardown direct-reopen and manual-copy UI tests and the new process-relaunch recovery-copy UI test have not been run on this source. Neither the in-memory registry check nor Swift parsing proves the SwiftUI flow, authorization after relaunch, multi-process behavior, or storage durability.
