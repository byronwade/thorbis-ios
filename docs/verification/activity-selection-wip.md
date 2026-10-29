# Activity selection WIP verification

This branch is not ready to ship. The activity fresh-read changes in this commit have not been built or run. The added FieldAPI test checks that the job and notes requests bypass the local URL cache and send `Cache-Control: no-cache`; it has not executed.

The preceding source at commit `1dfbe73` built for testing successfully; its log is `/private/tmp/thorbis-activity-final-build-v5.log`. The focused test attempt executed zero test cases. CoreSimulator stalled in `installApplication`; the interrupted run is recorded in `/private/tmp/thorbis-activity-focused-v5.log`, `/tmp/thorbis-activity-focused-v5.xcresult`, and `/private/tmp/thorbis-activity-v5-sample.txt`. Earlier focused activity, session, and payment tests also did not execute. No runtime pass is established.

Release blockers:

- On a cold offline open, previously fetched server history and the note composer remain unavailable because the old job cache is keyed only by job ID and the current session snapshot does not establish a durable per-job grant. Locally queued notes are separately scoped to the verified actor and organization.
- A durable solution needs an actual per-job offline authorization contract and failure-safe persistence. A server-side revocation cannot be detected while disconnected, so its lease and expiry semantics must be explicit.
- `PaperJobInvoiceContent` is currently uninstantiated; its invoice activity model has not been qualified for authority changes.
- Run the fresh-read transport test, activity and authority tests, and payment/refund accessibility checks on a working simulator. Review the final diff and validate the offline behavior before considering a build.
