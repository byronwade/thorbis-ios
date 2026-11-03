# Draft recovery access: work in progress

This candidate is not release-ready. A locally recovered estimate or invoice draft is hidden until a fresh read authorizes the same document and verifies its revision. A recovered new-estimate draft also checks its job, customer and any known saved estimate. A routine in-session authority refresh retires the lease; an existing editor opened without a recovered draft retains its prior offline behavior until that authority changes. Reopened saved drafts require a live check, including after connectivity returns.

A newly created local draft is removed when its raw text, formatting and other editable values return to the original baseline. A previously recovered draft is intentionally retained even if its contents appear to return to the baseline: SwiftUI state changes also arise from restoration and automatic classification, so the candidate cannot yet prove that an apparent undo was a deliberate user action. The technician can explicitly discard through the confirmation flow. Consequently, a recovered draft that was silently reverted to baseline can still require explicit discard before reopening a newer server revision. Do not infer a person’s intent from background classification.

An exact-source simulator build succeeded after the SwiftUI views were split. Four authorization-guard unit tests passed; four UI tests passed for estimate and invoice undo to baseline and raw whitespace/numeric discard confirmation. The job-access denial UI test produced its expected red result before the isolated 403 fixture was added; the revised fixture has not yet been run. The existing invoice catalog test failed its Close line assertion, and an untouched-parent comparison remains pending. Same-session denial, a late reload response, offline/reconnect and cleanup failure still need view-level verification. No migration, deployment or release is authorized by this evidence.

## Lifecycle and access follow-up

On the separate draft integration worktree, the first six-case UI run exposed a real hidden cleanup-error message, plus two fixture problems: the invoice preview returned an issued record after access was restored, and a request-count assumption did not account for an extra read. The ordinary-editor offline/reconnect case, same-session estimate job-access revocation/restoration case, and saved-estimate/link cleanup-failure relaunch case passed in that first run. The failed cases and their original log remain in `/tmp/thorbis-draft-lifecycle-red.log` and `/tmp/thorbis-draft-auth-derived/Logs/Test/Test-Thorbis-2026.11.02_22-56-07--0500.xcresult`.

After surfacing a fixed, non-sensitive cleanup failure message on the locked estimate and invoice views and correcting the isolated preview fixtures, a three-case iPhone simulator rerun passed: failed conflict cleanup reported the error and retained the recovered draft; a deliberately held estimate reload response released after dismissal did not delete the draft; and same-session invoice access revocation hid then restored the edited quantity. Result bundle: `/tmp/thorbis-draft-auth-derived/Logs/Test/Test-Thorbis-2026.11.02_23-04-58--0500.xcresult`. The no-network resource-read/reconnected-relaunch and 403 job-access/relaunch UI cases previously passed in `/tmp/thorbis-draft-auth-derived/Logs/Test/Test-Thorbis-2026.11.02_22-21-55--0500.xcresult`.

These tests exercise selected preview fixtures, not production or physical devices. The full recovery suite, cross-actor/organization lifecycle, cleanup failures across all editor types, simultaneous authorization checks, and offline resource authorization remain additional review or test work. Previously recovered drafts still require explicit confirmed discard after a full apparent undo. The invoice picker Close line issue was separately reproduced on release head and is handled in an independent branch; this draft integration is not release-ready or deployed.

## Discard follow-up and final source identity

The pre-fix screen run reproduced missing discard confirmation after a failed undo-cleanup for both estimates and invoices, and after a title-only new-estimate edit. Its customer-only case failed earlier because the test selected a similarly named background job; that was a test-selector failure, not product evidence. The log is `/tmp/thorbis-draft-discard-red.log` and the result bundle is `/tmp/thorbis-draft-auth-derived/Logs/Test/Test-Thorbis-2026.11.02_23-10-45--0500.xcresult`.

After the fixes and selector correction, all four screen cases passed on the final source: estimate and invoice failed-undo cleanup retained the editor and displayed the removal failure; title-only and customer-only new-estimate cancellation required confirmation and did not restore discarded values after relaunch. Result: `/tmp/thorbis-draft-auth-derived/Logs/Test/Test-Thorbis-2026.11.02_23-14-22--0500.xcresult`. A before/after SHA-256 comparison of the listed application, preview and test files was identical across this run; manifests are `/tmp/thorbis-draft-discard-green-before.sha` and `/tmp/thorbis-draft-discard-green-after.sha`. Final hashes follow:

```
1d579883ba6a0cb621845b8621c2ab195ddc487b9ce133d5baaadfb70232d49b  Thorbis/Sources/CommercialDraftAccess.swift
1fcac1470d85782335958c4a03eb0968477c08d0893b664104756b6d0fe974d2  Thorbis/Sources/CommercialDraftStore.swift
71797999a6e2893915c04ebe801ca007ddae47cd55273bfe8bdbb0063363cbcd  Thorbis/Sources/EstimateRevisionEditorView.swift
0c4d8c2e74834dc1f515edd1d9ccee8b936e63ccc21fe5080a46c350b33de7fd  Thorbis/Sources/InvoiceLineEditorView.swift
433ed89e59d5370ea7e117360058f724726ee27fa7dd310b3b4376341a5b1146  Thorbis/Sources/NewEstimateView.swift
5bc864e6c5eb5e58155b61c21ffcf8cba972470a36c7f9a8ade15d994c6be4c7  Thorbis/Sources/FieldAPI.swift
bb9d1021e9ce71ff8fed50da75a71fdba14d3963d6ffa4fcc3496f10ac6b6af2  Thorbis/Sources/EstimateRecoveryPreview.swift
a0b6fe3dc4af80d5085feed24591e3d86e5e61d6e2bdf5fa8d6065e35ce9c1b1  Thorbis/Sources/PaperPreview.swift
6f7d8f54166d3f89ad9ef415576c7a61ebce7ea88bd03b2df165ea29b7299d63  ThorbisUITests/EstimateCatalogReviewUITests.swift
6ca4aaddb5e58d113e0eb333c61820cb3866ba836b773aa25a75df1b6b02af20  ThorbisUITests/EstimateCreationRecoveryUITests.swift
938ca777b04e13ab8c2075ac829bf5a9f68bbb70a759372030e60dc47cb26823  ThorbisUITests/InvoiceCatalogQuickEditUITests.swift
```

The earlier lifecycle and authorization/undo tests used earlier WIP snapshots; the subsequent product changes added the new discard guard and new-estimate baseline tracking, and tests changed as documented above. Only the four discard cases are claimed against the final frozen source. Earlier passing results remain useful evidence but should be rerun against the final commit before release. A full recovery suite, cross-actor/organization lifecycle, cleanup failures across all editor types, concurrent authorization checks, physical devices, and offline resource authorization remain unverified. No production deployment or TestFlight release is represented by this WIP.
