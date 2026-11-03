# Held atomic job-estimate client

The server draft adds an idempotent `/v1/commands` job-estimate command, but it is not deployed and does not expose a versioned readiness assertion. `offline_sync` alone does not prove the command contract. Keep the new path off by default, and never switch an attempted or ambiguous command to the older create-and-link flow.

1. Model a durable, immutable command envelope and exact payload that survives restart under the original actor, organization, API origin and job; preserve line presentation and price-book provenance. Encode the server's expected wire shape and reject unsupported inputs.
2. Interpret response identity and result defensively. A transport error, malformed or missing result, changed scope, authorization rejection, conflict or legacy reconciliation never permits a new create or fallback; only a verified link for the exact command/job may advance. Retry must reuse the stored ID and exact payload.
3. Add unit tests and later integrate a live-capability check, draft persistence, current authority/job revalidation, and UI only after the backend contract and recovery rules are independently reviewed. Coordinate simulator access. Keep production disabled and do not expose an unavailable action.

## Current hold and integration blockers

The model and transport are present but hard-disabled, with no editor call site.
Any recovered draft that already contains an atomic operation keeps that operation,
locks editing and the old create/link action, and cannot be erased by the normal
draft discard. The boolean passed to the held method is only a placeholder and
is not sufficient authorization to enable the feature. Integration must obtain
a live, versioned backend capability, freshly authorize the specific job and
estimate action, persist the complete command and attempt state before sending,
and recheck actor, tenant, origin, session generation and authority after every
await. An interrupted or rejected replay may represent an earlier committed
write and must never fall back to a new create. Legacy reconciliation needs an
explicit review path rather than acceptance of submitted content.

A returned link proves only the server's reported link identity; it does not
prove saved commercial terms, member pricing, line visibility, revision or
current job scope. Before considering the draft saved or removing local recovery,
fetch the current job and estimate under the same live lease, verify authoritative
membership and the exact accepted commercial scope including server-applied member
pricing and presentation, and handle changed or unavailable evidence as pending
review. Do not claim support for paragraphs above the currently deployed
200-character command limit without the separately qualified backend capability.
The model rejects malformed persisted origin/timestamp and does not send them,
but this is not a substitute for the API client's production-origin trust rules.
Xcode, simulator, durable in-app attempt/retry, session-switch, and end-to-end
server tests are still required before enabling or shipping.

The held builder adapter maps price-book identity/revision, material/work group,
quantity, price and customer visibility into the command and refuses unsupported
source kinds. A standalone Swift harness compiled the extracted adapter with
stub input types and exercised its provenance/visibility and unsupported-source
branches (`/tmp/thorbis-atomic-ios-adapter-green.log`). This is not an Xcode app
build or an end-to-end request. The command model's standalone scope, durable
serialization and response tests are in `/tmp/thorbis-atomic-ios-model-final5.log`.
Focused XCTest sources include gated transport and draft cleanup failure, but
have not yet run on an iOS simulator.

## Focused iOS verification

On iPhone 17 Pro simulator iOS 26.3.1, Xcode built the app and passed all 23
selected `AtomicEstimateCommandTests`, `EstimateCreationRecoveryTests`, and
`CommercialDraftStoreTests` cases (`/tmp/thorbis-atomic-ios-xcode-tests.log`;
result summary `/tmp/thorbis-atomic-ios-tests-summary.json`). This includes
stored command round-trip and backward compatibility, unsupported builder source,
provenance and presentation mapping, same-scope checks, malformed restored
origin/time refusal, held transport, ambiguous response handling, pending atomic
operation blocking the old recovery action, and failed cleanup retaining an
operation. The selected run did not include UI automation, live server requests,
or session-switch/authority-race qualification. The API send and editor
integration remain disabled; a verified result still requires the post-response
checks above.

## Held exact job binding

Before a held command could be sent, require the freshly re-read job to match the command's tenant and job ID and the draft's exact customer and optional location, and reject a canceled job. Add mismatch tests and retain the production-off gate. This is only a necessary local check; a caller must separately prove current authority and freshness across every await, and unknown outcomes may not fall back to another creation.

The held transport now requires a job snapshot whose job, tenant, draft customer and exact optional location match, and only accepts recognized non-canceled job statuses. Standalone Swift compiled the actual command model against a minimal JobRecord stub and passed job/tenant/customer/location/status cases (`/tmp/thorbis-atomic-job-binding-green.log`); XCTest source was parsed but not run. The input snapshot and draft bindings are supplied by the caller, and are not themselves proof of fresh authorization or immutable draft identity. Before enabling, persist and bind the draft customer/location to the operation, freshly validate job access immediately before send, guard session and authority across awaits, and revalidate a confirmed server result. A mismatch or unknown result must remain pending for review, never start another create.

Next, persist a local-only `draftTarget` alongside the immutable pending command: normalized customer UUID plus explicit optional location UUID, populated from the builder before the first attempt. The held send must compare that target with both the recovered draft and the freshly authorized job; it must not add these fields to the server wire payload. Old pending operations without a target remain decodable but locked for manual review, never recreated or sent using inferred values. Test persisted round-trip, malformed and absent targets, nil versus present location, changed recovered draft, and reuse of the original command ID and payload. The versioned capability, live session/job authority and server result revalidation remain prerequisites to any enablement.

The held operation now stores a local-only draft target, binds builder customer/location at creation, and refuses send when that target is absent, malformed, differs from the recovered draft, or differs from the job snapshot. Legacy operations continue to decode and remain locked for review; the server envelope and command ID are unchanged. `/tmp/thorbis-atomic-target-green.log` records standalone execution of the actual model with a JobRecord stub covering round-trip, missing/malformed target, mismatched job facts and omitted wire target. XCTest sources were parsed only; no simulator or server integration has run for this change. Fresh job/session/authority proof, durable persistence before send, job relationship races and post-result commercial verification still block enablement.

The location field is now encoded explicitly, including JSON null when the draft has no location. A target object missing that field fails decoding and leaves the entire saved draft held rather than inferring no location. The `/tmp/thorbis-atomic-target-explicit-red.log` baseline showed implicit omission; `/tmp/thorbis-atomic-target-explicit-final.log` passes with explicit null, missing-field rejection, legacy absent target handling, and retained wire omission. This encoding has not shipped; any prototype operation produced by earlier commit 1f275c7 without the explicit location remains held as a malformed draft and must not be silently retried.

## Held target-bound V1 wire contract

The client now persists `contractCommand` when making a new pending operation and constructs `jobs.createRelatedEstimateTargetV1` with `expectedJob.customerId` and an explicit `expectedJob.locationId` (JSON null when absent). Older pending operations lacking the version marker, including prototypes with a saved draft target, still decode but cannot construct a wire batch or send; they remain held for review, never silently converted or recreated. A rejected/unknown command is not proof of no prior commit. The local customer/location and command version remain bound across persistence; the server derives the new estimate's actual customer and location under its own lock.

Standalone Swift compiled the actual model with a JobRecord stub and passed encoded wire target, nil location, legacy marker refusal, target mismatch, round-trip and server-style duplicate/rejection response checks (`/tmp/thorbis-atomic-wire-v1-final.log`); Swift sources and focused XCTest were parsed, not run on simulator. Server draft PR #1586 is unmerged and not deployed. This does not establish version readiness, fresh job or session authorization, durable persistence before sending, complete returned terms/pricing, end-to-end integration, or safe recovery and cleanup. The transport and UI remain disabled.

### Swift-to-server contract fixture

`tooling/atomic-estimate-contract-fixture.swift` compiles with the actual `AtomicEstimateCommand.swift` and a minimal standalone `JobRecord` stub; it produces the real V1 JSON and decodes real server responses. The held backend integration test uses that executable against its disposable PostgreSQL runtime and validates the actual envelope with the server parsers, a rejected mismatched customer, an applied command with stored line facts, and exact duplicate replay; Swift classifies each actual response (`/tmp/thorbis-cross-contract-pg-final.log`). The test requires an explicitly supplied fixture executable and skips without it; it does not execute the app's disabled transport, exercise saved drafts, establish real device identity or capability readiness, or qualify production deployment.

## Held write-ahead attempt journal

`AtomicEstimateAttemptJournal` is disconnected from product UI and transport. Before reporting an attempt prepared, it requires ownership of the existing `new-estimate` draft scope, loads that persisted draft, checks actor/organization/origin/job/customer/location and title, and writes a separate immutable protected journal record containing the complete draft and V1 command. It rereads and compares the record; a different operation or draft, corruption, missing ownership or write failure cannot replace an existing attempt. Recovery can locate the record from the original actor/organization/origin/job without already knowing the command ID. The common draft store's default protected atomic write remains unchanged; an injected writer enables failure tests.

Standalone macOS checks compiled the actual journal, command and `CommercialDraftStore` with a minimal draft/model stub and exercised owner checks, reopen, same-command idempotence, different-command refusal, identity isolation, corrupt records and failed write retaining the original draft (`/tmp/thorbis-atomic-journal-real3-green.log`). XCTest sources are present but have not been run on simulator. This does **not** authorize sending or prove line-by-line draft-to-command equivalence, current resource authority, cross-process exclusion, crash/power-loss durability, job mutation safety beyond the server contract, or eventual cleanup. The journal uses a separate scoped file from the original editor: until all creation, editing, discard, retry and sign-out paths are integrated with it, another path could ignore a pending attempt. A missing journal is not proof an earlier attempt did not commit. Do not enable transport or integrate the UI until these issues and exact server post-result reconciliation are qualified.

### Saved-draft equivalence

The held journal now reconstructs the command from the saved editor lines via the existing revision line mapper, presentation logic and atomic builder adapter, using the new-estimate price parser's stricter nonnegative input rule. It compares the complete reconstructed command before writing and again on recovery. The explicit `storesLineGroups` value is retained with the attempt; if groups are unavailable, drafts containing material/hidden lines are refused instead of silently dropping presentation. The caller must still prove this feature mode and current authority before any future send. Prior prototype journal records without the new mode fail closed rather than being inferred; no prototype was shipped.

The standalone regression `/tmp/thorbis-atomic-journal-terms-red.log` reproduced acceptance of a mismatched empty draft. `/tmp/thorbis-atomic-journal-terms-green.log` passed description, quantity, price, source kind, catalog item/revision, group, visibility, group-loss and reopen cases using the actual journal, protected store and money parser plus extracted unmodified builder mapping functions with minimal model stubs. XCTest source additionally covers invalid price/quantity and unsupported sources, but has only been parsed, not run on a simulator. This does not prove live feature readiness, cross-process exclusion, original editor/send/discard integration, power-loss durability, or authoritative post-save terms.

### Held interprocess attempt fence

A stable, never-unlinked per-attempt lock file now guards both prepare and recover. Lock acquisition is nonblocking, with one job-scoped lock at a time and no await while held; a competing process is refused. Preparation reads the protected source draft, compares terms, checks the journal, installs via a same-directory create-only hard link, and rereads before releasing the lock. The source draft's existing in-process owner is still checked. A crash or failed write may leave a pending record or temporary file; no error or absence proves a server attempt did not commit. Existing draft-store save behavior is unchanged outside this new held journal.

`/tmp/thorbis-atomic-journal-lock-red.log` showed the previous journal ignored a held OS lock. The standalone compiled check `/tmp/thorbis-atomic-journal-lock-green.log` passes under a separate process holding that lock; `/tmp/thorbis-atomic-journal-two-process-final.log` shows two independent processes with different command IDs result in one accepted and one refused, with one recoverable record and a failed create-only replacement. These checks use the real journal/store/command and extracted builder mappings with minimal model stubs; the new XCTest case is parsed but unrun on simulator.

This is not production-qualified. The existing editor, discard, fallback creation and any other source-draft writers do not yet acquire this OS lock, so a separate process can still change or ignore the source draft. There is no held network-spanning lease, no integrated sign-out/cleanup ordering, no device filesystem protection/hard-link qualification, and no file/directory fsync or proven power-loss durability. The lock file must never be unlinked. Keep transport and UI off until all relevant writers use one coordinated protocol and real cross-process, crash, authority and post-result tests pass.

### Held shared legacy/V1 marker

The isolated journal now reserves one job-scoped, create-only marker for either an atomic V1 operation or a legacy create. A legacy marker captures the owned, persisted source draft and explicit customer/nullable location before any future network call; `legacyPending` deliberately means reserved **or** attempted, with no success or no-commit inference. A second staging call, even with the same local ID, fails closed because the first may already have sent a non-idempotent legacy request. V1 and legacy markers mutually block one another; `status` distinguishes local absence, V1 pending and legacy pending, with malformed data throwing rather than appearing absent. Direct V1 records containing storesLineGroups remain readable; earlier 33c1701 prototype records without that field fail closed and remain held for review. No method clears or resolves either kind of marker.

Standalone real journal/store checks with extracted builder functions and minimal model stubs passed `/tmp/thorbis-shared-marker-green.log`; `/tmp/thorbis-shared-marker-process.log` passed a two-process legacy-versus-V1 race with one accepted, one refused and a retained pending marker. Focused XCTest sources were parsed but not run on simulator. The existing editor does not invoke this primitive: save, discard, legacy create/link/retry, V1 send, other processes/old app versions, and reconciliation/cleanup remain unintegrated. Captured data alone proves neither resource authorization nor successful submission; marker absence is not proof that no prior write occurred. File and directory fsync, power loss, device protection, safe sign-out and all writer coordination remain unresolved. Transport and UI remain disabled for V1; existing legacy behavior is unchanged.

### Held source-draft coordinated lease

The held journal requires a long-lived source-draft OS lease for staging; only explicit coordinated methods use the lease. Source lease precedes the job-attempt lock, with nonblocking acquisition and permanent lock files. The existing editor continues using its original uncoordinated save and remove methods. This intentionally preserves its behavior but means existing or older app processes can bypass the lease and change the source draft; the journal and transport remain disconnected. Job-wide exclusion across distinct drafts, editor lifecycle, conflict-safe dismissal, authority, power-loss durability and device filesystem behavior remain unqualified.

An earlier candidate also applied transient locks to ordinary editor writes. Independent review found a contention failure during `NewEstimateView.onDisappear` could release the editor after failing to persist its final edits, so that change was removed. Earlier logs `/tmp/thorbis-source-lease-two-process.log` and `/tmp/thorbis-source-lease-exact.log` apply only to that superseded candidate and do not establish behavior of the current code.

The current candidate's lightweight, separate-process check `/tmp/thorbis-source-lease-held-only.log` confirms that coordinated same-key and case-variant owners exclude one another while uncoordinated legacy save/remove retain their previous behavior. Source and driver hashes are in `/tmp/thorbis-source-lease-held-only-hashes.log`. This macOS standalone check is not an iOS app, simulator, device, authority or crash test. The uncoordinated bypass is an explicit integration blocker, not a safety guarantee.

### Held editor lifecycle coordinator

`AtomicEstimateEditorLifecycle` is a disconnected prototype around the coordinated source lease and shared job marker. It opens only an exact actor/organization/origin/job/customer/location draft scope, exposes pending markers as a non-editable state, saves before staging legacy or V1, and keeps the lease and in-memory draft with the caller if a controlled close cannot persist. A staging error is `stageUncertain` and refuses retry or close; successful staging is pending, never evidence of server success. There is no discard, send, cleanup or success API. An observed missing marker is explicitly not proof of no previous server write.

The standalone run `/tmp/thorbis-estimate-lifecycle-green.log` exercised the real lifecycle, store, journal and command with extracted builder mapping and minimal model stubs: failed close retained the owner, a later successful close released it, a legacy marker prevented re-stage and survived reopening, and a marker-write failure blocked retry/close. Focused XCTest sources were parsed but not run on simulator. The prototype is not wired into `NewEstimateView`: interactive and external dismissal, scene/process termination, session/authority changes, conflict handling, all legacy/V1 create/retry/discard paths, old app versions and other uncoordinated source writers still bypass it. File/directory durability, real-device behavior and authoritative post-result/cleanup remain unqualified. Never enable V1 or claim end-to-end editor protection on this evidence.

The lifecycle additionally checks the existing source draft before treating a locally missing marker as editable. A legacy draft marked uncertain, already created, holding an atomic operation, or requiring review remains pending; it cannot be overwritten or restaged. `/tmp/thorbis-estimate-lifecycle-final.log` adds a standalone reopen check that an old uncertain draft survives unchanged. This is still not a UI or real-session test.

Independent review identified that a normal existing source draft could be overwritten by editor defaults on reopen. The held coordinator now enters `needsRestore` after decoding a non-pending saved draft; save and staging remain disabled until the caller acknowledges the exact decoded draft. Closing without acknowledgment releases the lease without writing. Corrupt or mismatched source data throws and remains unchanged. `/tmp/thorbis-estimate-lifecycle-restore-final.log` passes standalone reopen/default-overwrite and corrupt-source checks plus prior pending/failed-close cases; focused XCTest sources are parsed, not simulator-executed. No product UI is wired.

The lifecycle now converts every decoded saved line before exposing a draft for restoration, refuses unknown groups, inconsistent catalog baselines, more than 500 lines, or duplicate line IDs, and leaves the original file untouched. Incomplete text such as an empty quantity or in-progress price remains restorable; it is not treated as corrupt. `/tmp/thorbis-estimate-real-draft-semantic.log` passed corrupt-group, partial-baseline, duplicate-ID and incomplete-input cases using the actual lifecycle/store and extracted unmodified `CommercialNewEstimateDraft`/line decoding, with minimal model stubs. Focused XCTest sources remain unrun on simulator; the UI and transport stay disconnected.

### Held source-change detection

The lifecycle now records the exact stored envelope bytes read with the decoded source draft, compares them again before a controlled save, and rereads the result. A changed, missing or unreadable source blocks the save/close and retains the lease and in-memory draft; it does not overwrite a newer known file. `/tmp/thorbis-estimate-stale-source-red.log` reproduced the former stale overwrite, and `/tmp/thorbis-estimate-stale-source-green.log` passed with the held guard. `/tmp/thorbis-estimate-real-draft-after-snapshot.log` also passed prior extracted-draft semantic and incomplete-input cases. These lightweight macOS tests use the real store/lifecycle and extracted mapping with model stubs; XCTest source was parsed only.

This is not an atomic compare-and-swap: an uncoordinated process can change the file after the check and before the write. Old app versions and current uncoordinated editor paths still bypass the lease, and unknown future fields, filesystem access failure, crash/power-loss durability, real-device behavior and authority are not fully qualified. UI/transport remain disconnected, and this check must not be described as full cross-process protection.

### Uncertain local write recovery

Once a source write has been attempted, any write or readback error now leaves the held lifecycle in `writeUncertain`, retaining the lease and intended draft rather than claiming the write failed. A separate read-only reconciliation can resume only if a currently readable saved draft exactly matches that intended content; a missing, unreadable or different draft stays held and is never overwritten by reconciliation. A write that changed the file just before a readback failure no longer traps retries behind the stale snapshot when the matching file can be verified. The source store's default read behavior is unchanged; an injectable read is used only for failure tests.

`/tmp/thorbis-estimate-uncertain-green.log` passed lightweight standalone actual lifecycle/store/journal checks with extracted mapping and model stubs: failure after a successful write, later matching recovery, and refusal to overwrite a newer different draft. Existing XCTest sources were parsed but not run on simulator. The guard is not an atomic compare-and-swap, and unknown fields, uncoordinated writers, runtime authority, actual editor dismissal, process death and power loss remain unresolved. The prototype stays disconnected and the transport remains disabled.

### Held local uncertain-write retry (2026-11-03)

The disconnected lifecycle can observe an unchanged, nonempty prior source snapshot after an ambiguous local write. It then requires an explicit retry with the same encoded intended draft and refuses close or staging while the retry is required. This is a current-file observation, not proof of the prior write's outcome. A changed or unreadable source remains held; initial absence is handled by the subsequent first-save recovery change below. The normal save checks the source again before retry; uncoordinated older writers can still race that check. No live editor or transport was connected.

The standalone Swift harness `/tmp/thorbis-estimate-prior-retry.swift` failed to compile before the API existed (`/tmp/thorbis-estimate-prior-retry-red.log`), and passed after the change (`/tmp/thorbis-estimate-prior-retry-green.log`), including preserved older/newer work and exact-intent retry. The XCTest regression was added but not run in Xcode; source and test syntax parsed successfully and `git diff --check` passed. This is not app, device, crash-durability, or cross-process integration qualification. Existing editor exits, authority, coordination with all writers, and authoritative server recovery remain prerequisites before wiring.

### Held first-save retry (2026-11-03)

A first save that returns an uncertain error can now observe that its initially absent draft remains absent and offer an explicit retry of the exact in-memory intent; this is not proof of the earlier write outcome. The held lifecycle now reads its coordinated source using `lstat`: only ENOENT is classified as absent; other access, nonregular-file, read, and decoding failures stay held. A new or corrupt source blocks retry. The observation and subsequent write are not atomic against legacy or other uncoordinated writers, and this remains disconnected pending full editor and writer coordination.

The lightweight exact-source harness `/tmp/thorbis-estimate-absent-retry.swift` passed (`/tmp/thorbis-estimate-absent-green.log`) covering absent retry success, a newer draft arriving before retry, and corrupt content. A behavioral baseline before the change failed at reconciliation (`/tmp/thorbis-estimate-absent-behavior-red.log`); a separate initial missing-enum compile failure is `/tmp/thorbis-estimate-absent-red.log`. New XCTest cases were syntax-parsed, not run in Xcode. No simulator or production integration test ran.

### Held job editor save/close safeguard (2026-11-03)

In this isolated candidate the existing job-bound new-estimate editor tracks failures in local autosave and removal, displays a retry action, blocks interactive dismissal while a failure is known, and reattempts local persistence before its explicit close for an already-created estimate. An intentional discard remains available for unsent work. Standalone creation keeps its existing behavior; atomic transport and the separate lifecycle are still disabled/disconnected. This safeguard does not provide a compare-and-swap or recover ambiguous writes under concurrent writers, cannot prevent a parent from removing the view, and does not guarantee crash or power-loss durability. Session changes and pending-created recovery require app-level testing and independent review before any release.

The lightweight macOS store harness `/tmp/thorbis-job-exit-real-store.swift` passed against the actual commercial draft store and guard (`/tmp/thorbis-job-exit-real-green.log`), demonstrating an injected pre-write failure preserves the old file and a retry is readable in a new store instance. The initial `/tmp/thorbis-job-exit-gate-red.log` is a missing-file compilation failure, not a behavior red. The SwiftUI view and new XCTest were syntax-parsed only; no typechecked Xcode build, UI, simulator, device, process-termination, ambiguous-write or real session test has run. Harness coverage does not establish that the view correctly invokes the guard.
