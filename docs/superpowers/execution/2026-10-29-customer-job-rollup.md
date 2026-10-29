# Customer job roll-up — in progress

This branch implements job-grouped modern and historical photo browsing, guarded reconciliation and incomplete states, customer/job record scope validation, and explicit account-location choice on jobs. The server does not yet support multiple job-specific contacts or service locations; do not present account records as linked job relationships.

The final source passed `xcodebuild build-for-testing` on October 29. A final `test-without-building` run stalled in CoreSimulator app launch and was interrupted before any test case executed. Earlier focused runs against intermediate revisions passed mixed-source 15+20 photos, job location choices, and scoped helper tests; they do not qualify the final revision. The final customer, scope, legacy, Live Activity lifecycle and native gallery tests remain required. Legacy photo throughput with a multi-megabyte image and real-device ActivityKit behavior remain unverified. Do not upload this branch until the applicable checks and fresh review pass.

Evidence: `/private/tmp/thorbis-customer-final-build.log`, `/private/tmp/thorbis-customer-final-qualified.log`, `/private/tmp/thorbis-customer-final-xcode.sample`. Build 83 remains the latest confirmed internal TestFlight build at the time of this record.

A second final-source retry used a newly created dedicated iPhone simulator. It also stalled during CoreSimulator app installation; the attempt was interrupted after 90 seconds with no tests executed. Evidence: `/private/tmp/thorbis-customer-fresh-device.log` and `/private/tmp/thorbis-customer-fresh-xcode.sample`. The new simulator is `B80AE818-3E9D-4248-8221-9B178FAAC268`; its data was not erased. The earlier build-for-testing succeeded; the final runtime and performance checks remain open.
