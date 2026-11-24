# Build 286

Uploaded to TestFlight from `paper-v2-tokens` at 4b32daab on 2026-11-21 (PR #563).

Owner: "fix anything that's repetitive… make the jobs and pages feel more productive and fun to look at… Navigation between jobs and customers and estimates and invoices and activity is funky and too complicated."

- One page top: job, customer, estimate and invoice share `RecordHeader` (number + status badge, 28pt title, one line). The job bar is Back, +, ⋯; Share, reschedule, running late and assign moved into ⋯.
- One fact once: the "Step N of 5" card and the status/time chip row are gone from Job details; Details no longer repeats customer and address.
- Links: a pill row under the title opens customer, estimate(s) and invoice(s) from a job, and customer, job and source estimate from an invoice.
- One way to add: Money keeps the section "+" only. "Show estimates" and "Customer view" are one "Show to customer" row. The floating "New estimate" pill is gone.
- Lists: Jobs, Customers, Estimates and Invoices use search, one chip row and the same two-line row. Photos' stage chips are one "Show" menu.
- Customer: hub rows in record order with Estimates, Invoices and Photos and files; the sub-page has three tabs instead of five.
- From the first end-to-end run against a local server: next step never returns to On my way; member estimate saves; member price not discounted twice; approved total read from the acceptance receipt; Add note focuses the field; Checklist in "+" at every stage; Paid screen and wrap-up no longer trap an in-progress job; reopened job opens on Working; refused reads (403) remembered per sign-in; service-context read first.
- Too-many-tries messages say "Wait a few minutes".

Checks: 1,547 unit tests pass (1 skipped), stock-control lint passes. 409 UI tests ran across 41 classes with 1 failure, the Saved Work landscape test, which passes after a simulator restart. Before/after screenshots reviewed in dark and light, largest text, iPhone SE and iPad.

Not checked: nothing here was run against a live server. Add-note focus has no automated test. PriceBook and CommsInboxScreenshot UI classes were not run. At the largest text size the job header fills most of the first screen. Not checked on a real phone.
