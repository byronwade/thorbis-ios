# SDD ledger — plan: docs/superpowers/plans/2026-10-28-invoice-payment-clarity.md

Issue BYR-1579, In Progress, assigned to the user. Spec is docs/superpowers/specs/2026-10-28-invoice-payment-clarity.md. Inline execution; current working root /private/tmp/thorbis-ios-payment-ux, branch codex/byr-1579-invoice-payments-clarity, baseline27e325b.

Baseline code is identical to the verified TestFlight70 source plus documentation: 389/389 tests passed in the previous batch. Backend authority was checked at fresh origin/main db80ec547. Current source has 146 indexed files, 2913 nodes after rebuilding CodeGraph.

Pre-flight: Task1 readiness gates the current collection sheet; Task2 changes only receipt presentation/mapping; Task3 replaces its payment-link destination. Execute these changes sequentially in that same view and retain existing mutation/reconciliation handlers.

Ruling: work in /private/tmp after the Documents checkout stalled on git add and file reads — native create_worktree rejected the projectless parent as Not a git repository, and attach_worktree rejected the manual checkout as unmanaged; a bare clone plus linked worktree keeps Git and source outside FileProvider — cost if wrong: temporary checkout needs explicit path use and later manual cleanup. No original uncommitted files were deleted.

Research: Linear is reconnected. get_agent_context is unavailable (Tool not found), so issue reads and fresh code are the context. BYR-352 is Backlog, blocked by BYR-344 In Review; BYR-346's Merged contract split does not activate ACH. Vault BYR-832 is Ready, callback overlap BYR-856 is blocked, HTTP admission BYR-1203 unresolved. No new provider capability is activated by this UI maintenance ticket.

Apple audit: archive70 lacks payment.acceptance; the portal App ID capability is unchecked and lists Development provisioning only. No existing request/approval state was exposed. No forms, terms or capability settings were changed.

Previous batch: TestFlight70 processed and assigned Internal Testers (user and Hayley), automatic Xcode distribution enabled. PR73 draft attached; latest pushed source27e325b. The original scratch workspace and a new execution-log copy remain in the stalled Documents checkout.

Task1 RED: Swift tests failed on missing TapToPayReadiness and Phase.unavailable; Python audit suite failed because the audit module did not exist. Expected failures observed.

Task1 Ruling: a legacy archive without the new policy marker is unverifiable, not a disabled-build proof — archive70 predates the runtime gate and could still offer Tap — cost if wrong: older archives fail the new audit and require a new build. Update the planned archive70 expectation to rejection; the next explicit-disabled archive must pass.

Task1 GREEN audit: 9/9 Python checks pass; bash syntax passes; legacy archive70 is correctly refused for its absent policy marker. Swift focused checks running.

Ruling: deliver the readiness guard as the first small beta, followed by the QR/receipt UI batch — the user explicitly requests frequent builds, and the unqualified Tap default is a current flow defect — cost if wrong: one extra full verification/archive and a review per independently released batch. Further feature work is reviewed against the preceding released commit, not as a repeated review of addressed findings.

Task1 verification: focused Swift38/38, Python9/9, and full scheme393/393 pass with zero failures/skips. Full result readiness-full.xcresult. Fresh review dispatched for released Task1 batch at0ae06d2. ASC currently tops at70; candidate71 reserved. No QR/receipt changes in this release.

Final review (Task1 batch): fresh gpt-6-astra review found one Important: an audited validation IPA was followed by a separately signed upload export. Reproduced in release-boundary integration tests: enabled upload exported twice, and missing exact-IPA transport credentials still uploaded. Fix uses one export, distribution audit, then Transporter for that same IPA; missing transport prerequisites stop the upload. Current disabled builds retain Xcode signed-account upload.

Final: minor (deferred): Simulator controller no-request test also has unsupported hardware, so it does not independently mutation-test removal of the controller build flag. Pure readiness tests cover false build with supported device; follow-up injects controller eligibility when enabling real-device Tap qualification.

Final: Ruling: Tasks2/3 and new ACH execution remain separate future batches; existing aggregate Tap reconciliation is unchanged and still requires BYR-350/BYR-436 exact-attempt qualification — current flag remains false — cost if wrong: those capabilities cannot be activated until the separate qualification is complete.

Final: Ruling: Tap-enabled uploads require existing Transporter plus ASC API-key authentication for exact-IPA transport; no re-export fallback — Apple CLI supports assetFile transport, while this host currently lacks Transporter and configured key transport — cost if wrong: a future enabled release stops after audited export until those prerequisites exist. Current disabled71 uses the established Xcode account path. Official reference: https://help.apple.com/itc/transporteruserguide/en.lproj/static.html .

Final: fixed separately re-signed upload artifact — test_enabled_upload_transmits_the_single_audited_export and test_missing_transport_credentials_never_reexports_or_uploads RED→GREEN; full Python suite12/12, bash syntax and diff checks pass. Swift app source unchanged from full393/393 verification. No second review requested per executing-plans.

Task1 upload: archive71 signed app/widget1.0(71), strict signature and disabled-policy audit passed. Xcode upload succeeded13:44:28EDT; Apple processing pending. StripeTerminal dSYM warning remains non-blocking. Evidence docs/release/build-71.md. PR74 created and attached.

Task2 Ruling: start receipt UI after successful71 upload while Apple processes its immutable package; finish internal availability verification alongside development — the user requests continuous work and no source edits can affect the accepted71 package — cost if wrong: an Apple processing issue must be resolved before considering the delivery gate complete.

Task2 RED: new selection tests could not access the private old choice enum and lacked explicit received-bank/card mapping and pending-method restoration. Expected build failure observed. Extracted selection policy, removed duplicate method state/picker, and kept existing record/retry mutation handlers.

Task2 native test investigation: menu and bank confirmation rendered correctly, but the test assumed Cancel exists. Captured hierarchy proves iOS26 presents a popover with PopoverDismissRegion instead. Test now dismisses that native outside region when no Cancel button exists; no payment submission is performed.

Task2: unit32/32 and native menu/confirmation1/1 pass. Canonical all-four-method API test remains green; every pending tender maps back to its original selection. No requests sent outside read-only preview.

Ruling: task-done validates the completed xcresult artifacts rather than rerunning unchanged passing tests — developer instructions prohibit redundant repeats; verification command asserts Passed, zero failures and skips for each result — cost if wrong: artifact paths must remain tied to this task; fresh full-scheme verification still follows final source changes.
Task 2: complete (commits a5bb596..3c6dc7b, tests: python3 .superpowers/sdd/2026-10-28-invoice-payment-clarity/verify-results.py .superpowers/sdd/2026-10-28-invoice-payment-clarity/task-2-green.xcresult .superpowers/sdd/2026-10-28-invoice-payment-clarity/task-2-ui-fixed.xcresult → .superpowers/sdd/2026-10-28-invoice-payment-clarity/task-2-ui-fixed.xcresult 1 passed)

Task3 RED: presentation/QR/invoice-balance tests failed on missing types, as expected. Added bounded local encoder and expiry policy; canonical paid state requires paid status plus zero USD balance. A changed balance hides the prior link. Preview injects a ready/expired inert example.invalid link; all transport mutation blocking remains unchanged.

Task3 investigation: expiry/URL/balance checks6/6 passed; independent Vision decode failed before decoding because Simulator could not create its inference context. Test now selects Vision-supported CPU compute stages using the public supportedComputeStageDevices API; renderer unchanged. Native tests added for ready/copy/status/Done, largest-text dark sharing and expired recovery.

Apple approval evidence update: found original2026-10-27 development-only approval, Case23157370. No distribution approval found. BYR-436 updated; Apple requests three flow videos and checklist. No email, terms or portal mutations.

Task1 delivery verified: Apple processed71, build577d345e-4b9e-4a78-af58-695747158433, assigned Internal Testers. No external review required for the existing internal group. Plan Task1 delivery gate is satisfied.
Task 1: complete (commits 27e325b..3c6dc7b, tests: python3 .superpowers/sdd/2026-10-28-invoice-payment-clarity/verify-release-71.py → Tap to Pay audit passed: disabled in this build)

Task3 native checks: all4 invoice UI checks and release-note checks passed. Vision on Simulator returned no barcode even after supported CPU selection. A standalone macOS diagnostic using the exact renderer independently decoded both preview and escaped-query URLs with BOTH Vision and CIDetector.

Task3 Ruling: use independent CIDetector QR decoding in Simulator tests and retain native macOS Vision evidence — Simulator Vision inference/CPU behavior is unreliable here, while both independent decoders confirm exact payloads on macOS — cost if wrong: Simulator-specific Vision regressions are not diagnosed by this unit check; physical camera testing remains a separate qualification. No test is skipped and the renderer is unchanged.

Task3 self-check: keep Check payment status available if a paid invoice still has an error/incomplete/mismatched history; hide it only for reconciled paid data. This preserves recovery during projection delays.

Task3 focused: independent Simulator CIDetector7/7 presentation/decoder/balance tests pass. Previous native4/4 and notes9/9 checks passed. Full scheme follows on final source; screenshots retained under docs/design/evidence/build-72 using inert preview links and sample customer.

Full scheme first run:406/407 passed, zero skips; only existing JobOverview More→Reschedule check timed out waiting for Save schedule. Failure hierarchy retained the native menu after the synthesized tap. No Job UI source changed in this batch. A focused unchanged reproduction passed1/1. No tests skipped or auto-retried; inspect final review and run one full confirmation after any required fixes.

Final review (Tasks2/3 batch): fresh gpt-6-astra review a5bb596..c777c54 found no Critical or Important issues; approve subject to final green verification.

Final: minor (deferred): QR-encoding fallback retains Scan to pay/camera headings even though Share/Copy work; follow-up should use sharing-only instructions in the no-image state.

Final: Ruling: physical camera scanning and live provider checkout remain unproven — two native macOS decoders and Simulator CIDetector prove the exact payload, native UI proves handoff, and server/API contracts are unchanged; no live-money test is authorized by this software verification — cost if wrong: a physical/device/provider issue may still require follow-up; Share/Copy remain alternatives.

Final: Ruling: actual ACH debit and Apple distribution qualification are outside this released UI batch — ACH choices explicitly record received transfers and Tap policy remains false; development approval is not publishing approval — cost if wrong: those executable rails stay unavailable until their separate gates pass.

Final: Ruling: the reviewer did not diagnose the preexisting scheduling failure — source is unchanged and isolated reproduction passes; run a fresh full confirmation without skips or automatic retries before upload — cost if wrong: a repeated failure delays72 and requires deeper diagnosis.

Final verification: full confirmation407/407 passed, zero failures/skips, without source changes or test retries. Existing More→Reschedule passes in this full run. Additional iPad handoff1/1 passed (QR/copy/status/Done), and portrait screenshot visually inspected. Candidate72 archiving from c777c54 app source (0792e0a adds qualification notes only); all prior71 features retained.

Task3 upload: candidate72 archive succeeded, app/widget1.0(72), strict signature and explicit-disabled Tap audit passed. Xcode upload succeeded14:15:40EDT. Apple processing pending. Non-blocking StripeTerminal dSYM warning retained in docs/release/build-72.md.

Task3 delivery verified: Apple processed72 (70ac097b-acb6-49ff-a4c8-55c7ae9a5dc1), Internal Testers2, testing notes saved. User confirms next priority is job-only ALL documents and cart/catalog for BOTH technicians and customers; BYR-1580 created. Tap setup work defers to that steering; no source changes to it.
Task 3: complete (commits 3c6dc7b..dd30f51, tests: python3 .superpowers/sdd/2026-10-28-invoice-payment-clarity/verify-results.py .superpowers/sdd/2026-10-28-invoice-payment-clarity/qr-full-confirmation.xcresult .superpowers/sdd/2026-10-28-invoice-payment-clarity/ipad-handoff.xcresult → .superpowers/sdd/2026-10-28-invoice-payment-clarity/ipad-handoff.xcresult 1 passed)
