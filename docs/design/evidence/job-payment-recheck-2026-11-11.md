# Customer payment recheck — 11 November 2026

A customer can choose Pay from an invoice in the job document book. The app reads the selected invoice and payment history again before asking the technician to unlock. When that recheck could not verify collection, it previously returned without explaining why. The change keeps the same invoice, job, permission and payment-history checks and shows a customer-sized message directing the customer to the technician. Moving to another document clears that message. Invoice reading, signing, payment actions and authenticated handback remain available.

The error uses the existing `CustomerProblemBanner` and Thorbis customer type tokens. No new Paper layout or payment provider behavior is claimed. The exact staff-unlock return is checked again against the captured session, API scope, current job, document selection and invoice model. A changed authority cannot open collection.

| Check | Evidence / scope |
| --- | --- |
| Baseline | `job-payment-recheck-red-1111.log`: mounted test tapped Pay, injected a failing fresh payment-history read, and failed because the warning did not appear. |
| Warning and document switch | `job-payment-green-warning-clean-1111.log`: one mounted test passed on a clean iPhone 17 Pro simulator using production source 8f1742a3. |
| Existing handback | `job-payment-green-tests-1111.log`: normal and declined technician handback and exact job-linked invoice collection passed on 8f1742a3. The complete run failed two new tests; see below. |
| Release notes | The nine What’s New tests passed on 8f1742a3. |
| Authority retirement | The first test used wording from a different legacy screen and failed. Its recording showed the protected job-document screen and no collection. The corrected test initially failed in preview setup; after a debug-only bounded wait for the preview job, `job-payment-retirement-previewfix-1111.log` passed on a clean iPhone 17 Pro simulator at 69d27bc5. |
| Simulator reliability | An isolated rerun on the original simulator restarted during automation setup and ran zero tests. A separate clean simulator was used for the passing warning and authority-retirement tests. A later preview run landed on Today before opening its requested job; the debug-only preview route now waits briefly for its sample job. The cause of the runner restart is not established. |
| Release and device | No merge, new archive, physical-device test, VoiceOver test, backend deployment or TestFlight upload is claimed. Prior exported build 235 does not contain this change. |

The simulator test project used the locally extracted Stripe Terminal 5.8.1 XCFramework from the ZIP matching the official package checksum; `project.yml` was changed only in the test worktree and is not part of the commit.
