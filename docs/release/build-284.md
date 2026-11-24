# Build 284

Uploaded to TestFlight from `paper-v2-tokens` at bd4f1d47 on 2026-11-20 (PR #563).

Owner: "keep doing research and keep improving... over and over." This round followed competitor research (ServiceTitan, Housecall Pro, Jobber, ServiceM8 and others).

Visible now
- "You're here. Mark arrived?" near the job's address while driving (within 125 m, app open, existing location access only). One tap runs the normal arrive step with method `geofence`; it never arrives by itself.
- New estimate: "Copy a past estimate" (this customer's first, then your own). Lines copy at their old prices; discounts, price book links and option packages do not.
- Job "+": "Maintenance plan" signs the customer up from the job and refreshes member pricing.

Built, hidden until the server turns each feature on
- `job_reopen`: "Reopen job" on a completed job, with an optional reason.
- `invoice_revisions`: "Add to invoice" for an approved estimate (asked once after approval, never silent); editing an issued or paid invoice; "Changes" history on the invoice; a note when the customer has not signed the current version.

Checks: 1,486 unit tests pass (1 skipped), stock-control lint passes, 123 UI tests pass across the job, invoice, payment, estimate and customer-view classes. The full UI suite was not re-run this round. Not checked on a real phone, with real GPS, or against a live server.

Server drafts this round (byronwade/Thorbis-TanStack, none merged or deployed): #1616 large media uploads and storage on the Vercel runtime, #1617 job checklists. By the server's code and runbook, job media does not work in production until storage (R2) is configured.

Still open
- The phone still caps uploads at 8 MB and keeps checklists on the phone; both wait for app work against #1616 and #1617.
- The location purpose string does not mention arrival.
- Automatic "on my way" texts need an SMS provider on the server.
