# Job invoice creation review — 2026-11-05

Tested source: `b615f7c1bc4120b62e0017638a79ded2d937beec` on iPhone 17 Pro Simulator. The release candidate differs from that source only by the existing `docs/release/build-168.md` record and this evidence file; Swift, tests and project configuration are identical.

The final focused simulator run passed 47 unit tests (`JobCommercialDocumentsTests` and `WhatsNewTests`) and five mounted `JobDocumentsUITests`. These cover the returned draft and repeated taps, foreign-job and failed responses, retired API authority during refresh, invoice-view revocation, and interrupted POST recovery. No invoice was written to a server. The simulator build used the checksum-verified local Stripe 5.8.1 package; tracked production `project.yml` was restored.

An earlier invalidation test failed because it expected a draft row to remain visible after the API request was retired. The revised test waits for the creation task to finish and checks that the stale detail never opens and the scoped recovery message appears. The final run passed. Result bundle: `/private/tmp/thorbis-create-invoice-review-1105d.xcresult`; log: `/private/tmp/thorbis-create-invoice-review-d.log`.

Actual task cancellation suppresses the recovery message. An API invalidation that interrupts a still-active task may show it only when actor, organization, job, API origin, saved-copy scope and job access still match.
