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
