# Job cards and customer document reading: staging evidence

Staged source `1680f64` combines customer document descriptions with the job financial-card changes. This is not a release approval.

- iPhone SE iOS 18.2 focused run: 48 passed, one terminated with signal TERM in the customer invoice discount/refund/cash paging test (`/private/tmp/thorbis-job-reader-staging-run2.xcresult`). This is a failed run.
- That specific payment-history test passed on an isolated rerun against the same staged source (`/private/tmp/thorbis-job-reader-money-retry.xcresult`).
- The staged run passed the selected long-description, mixed-total, two-card, section-navigation and largest-text chooser tests. This is focused coverage, not a full suite or VoiceOver qualification.
- The pre-existing technician invoice navigation stall and wrong-invoice selection remain unresolved. This staging branch is held from TestFlight pending the applicable release checks.
- Customer location redesign and editable technician description canvases are not included.
