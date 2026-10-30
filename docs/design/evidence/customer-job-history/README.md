# Customer job history

Paper source: [48 · Customer detail](https://app.paper.design/file/01KY0S86CYXENWSH216F3ZB058/B-0), whose compact job history presents a job, status and date. For the hierarchy of a service history, the [Tesla iOS service-history reference](https://mobbin.com/screens/a1ea4590-a32c-4634-94b0-5dd3e669e2af) displays a service title, status and date. This implementation adapts the existing Thorbis row; it does not infer locations, assignees or completed dates.

The new line uses only the job's parseable scheduled instant, includes year and local clock time, and leaves malformed and missing values absent. Navigation and access controls are unchanged. Customer activity is outside this change.

The baseline UI regression `/private/tmp/customer-jobs-red.log` failed because neither fixture year appeared. The first green UI run passed, but its combined test process later stalled in simulator service initialization before the release-note tests; no success is claimed for that combined run. An isolated UI run `/tmp/customer-jobs-build/Logs/Test/Test-Thorbis-2026.10.30_07-49-17--0400.xcresult` passed both year values, missing and invalid schedules, an exact local clock-time assertion, and navigation to a job. Further screenshot review exposed cramped row spacing. A 7-point padding follow-up could not be verified because CoreSimulator failed to launch the app with Mach error -308, so it was removed from this candidate; row spacing remains an improvement opportunity.

Not covered: release-note tests (the combined run stalled before they launched), other time zones or locales, extremely long job titles, largest accessibility sizes, VoiceOver, RTL, iPad, live backend, and physical devices. Screenshots use synthetic read-only preview data.
