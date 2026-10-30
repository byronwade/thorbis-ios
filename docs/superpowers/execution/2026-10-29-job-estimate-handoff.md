# Job estimate handoff — implementation and review

Runtime source: `3f5d70e8b580c00ab150a8d4759abea48895a06b`, draft [PR83](https://github.com/byronwade/thorbis-ios/pull/83), stacked on82. [Design](../specs/2026-10-29-job-estimate-handoff-design.md), [plan](../plans/2026-10-29-job-estimate-handoff.md), [full execution evidence](../../design/evidence/job-estimate-handoff/execution.md). [TestFlight79](../../release/build-79.md) is processed, assigned to Internal Testers (2), with test notes Saved.

The technician presents every verified estimate for the current job from one primary action; Add estimate and individual actions remain reachable. Customers independently select estimates, review exact terms/discounts and sign each within one protected handoff. Already-approved estimates stay visible; drafts never auto-send. Existing invoice/payment/document routes remain.

## Review and accepted fixes

One fresh whole-task review examined immutable candidate2805afb vs cfcda2c: no Critical/Minor, two Important recovery findings. Both were accepted and fixed with actual behavioral RED/GREEN: an unknown attempt remains reachable after another selection changes; interrupted preparation/upload can resume after exact membership/terms revalidation with the same signature/asset. Coordinator reviewed the11-file bounded fix delta1047c65 and found no additional material issue. No second independent review was substituted for regression evidence.

## Qualification

- Reviewed-candidate affected units196/196, recorded as historical coverage. Final affected units33/33 and strict normal-layout phone journeys8/8.
- Initial final iPad9 cases:6 passed/3 failed. Recording proved DEBUG disclosure midpoint hit the iPadOS system multitasking ellipsis. A test-only leading point retained unique/hittable geometry and explicit expanded/collapsed assertions. Corrected exact-discovery run executed those3 cases, all passed. The intervening0-selected run is explicitly not qualification.
- Final187-path manifest SHA256`8ccf1c9ee60b8517114ab94f1bd0db2808c26ee0f0c1367329560b2990b10076`. Coordinator independently verified every hash. Only the native test helper differs from phone-qualified f0a69028; application source is identical. Evidence42-file manifest6b13aafb was independently checked.
- Coordinator inspected clean phone/iPad completion and largest-text dark signing renders, canonical receipt counts, fresh signature isolation and recovery. Physical-device VoiceOver/RTL, sunlight use and performance targets are not certified.

## Rulings and practical limits

- Independent estimates may be selected together; packages remain exclusive within one estimate. Existing per-document consent/signatures remain required because no qualified aggregate signature/approval endpoint exists. A mistaken grouping could approve unintended work.
- A bounded App-owned presentation owner sits above actual session phase/generation replacement. Scope retirement clears private contents while preserving authenticated exit; a job-owned cover would expose staff on replacement, reproduced before the fix. Generic covers/auth/resync remain unchanged.
- Capture the real JobRecord location; independently validate document location using canonical association checks. Do not invent document-location-equals-job-location. Incorrect association assumptions could reject valid work or admit unrelated work.
- Retain exact unresolved bytes/asset/signer/time/token/nonce above ephemeral child navigation. Confirmed items never replay. Reconcile canonical public acceptance, including accepted option/price/signer, instead of inferring from aggregate status. Errors here could duplicate evidence or misstate approval.
- Live-authority predicates supplement existing API-generation guards around each current-revision/token request. Standalone defaults remain compatible. A false authority predicate could expose stale scope or block legitimate work.
- Keep legacy storage error type/text and transfer semantics. Only wrapped transport/nil-status or5xx storage failures gain pre-submission recovery; refusals, unsafe targets, identity mismatch and cancellation stay excluded. Overbroad recovery could hide a security/identity failure.
- Compact Paper adaptation removes repeated headings/selection labels while retaining56pt customer targets,17pt minimum text and explicit navigation. Large text scrolls; full terms are not claimed to fit one viewport.
- Use important affected checks and actual native journeys per user instruction rather than repetitive full CI/scheme runs. Coverage outside those boundaries remains a stated gap.

Historical intermittent simulator tap stops remain recorded without a causal repair claim; all original selectors passed the final strict phone run. TestFlight notes request physical-iPhone interaction testing. The prior saved-work relaunch uncertainty remains separate.

## Deferred minor

Completed overview copy still says “Choose any work to approve” and just-confirmed rows say “Already approved / no approval needed”. Clear approved counts/statuses remain; polish is deferred to the next UI batch. No feature is removed.

Broader customer catalog quote/bill-once admission, secure manual card entry, Tap to Pay distribution qualification and private check capture/deposit remain separate held work. No provider/backend deployment, new offline financial queue or physical-device qualification is implied.
