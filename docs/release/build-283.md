# Build 283

Uploaded to TestFlight from `paper-v2-tokens` at 463e9908 on 2026-11-20 (PR #563).

Owner: "working through a job is relatively difficult... technicians shouldn't be locked out of anything, so if they dispatch, they should still be able to add notes, images, estimates, collect payments. Same thing goes for when they arrive or when they close the job."

Job screen
- A "+" at the top of every job at every stage: Estimate, Show estimate to customer, Invoice, Payment, Photo or video, Note, Contact. A cancelled job keeps Note and Contact.
- Collect and Show estimate ride above the main button whenever there is a balance or an estimate to show. The status step stays the main button. No estimate pill before arrival; "+" covers it.
- Description, booking call and contacts (Call and Text per person) stay on screen while driving, arrived and working.
- Working: Estimate tile and Photos and files tile. "Can't start" is offered before arrival too.
- Photos: pick many photos and videos at once; several PDFs at once. Files stay capped at 8 MB (the server cannot finish a larger upload yet).
- Estimates: the create request names the job (`jobId`); a refused create says so plainly. "Edit" on a draft saves with `expectedUpdatedAt`; on today's server it says the draft can't be changed yet and keeps the edits.

Plans and memberships
- Add, edit and stop selling a maintenance plan (owners). Edit and remove a customer's membership.
- Push registration, text consent and reschedule undo are skipped when their server feature is off.

Checks: 1,445 unit tests pass (1 skipped), stock-control lint passes. 204 job, estimate, hand-off, payment and tab bar UI tests on the final build: 1 test failed in the long run and passed re-run alone (`JobOverviewUITests.testCustomerLinkIsComfortableAndOpensCustomerProfile`). The full UI suite was last run before the job-screen changes (447 tests, 1 failure in `CommsInboxUITests`, not reproduced in two reruns). Not checked on a real phone or against a live server. Picking many items from a real photo library is covered by logic tests only.

Server drafts this round (byronwade/Thorbis-TanStack, none merged or deployed): #1608 job service context, #1609 request hardening, #1610 staff roster leak, #1611 customer notes, #1612 job reopen, #1613 technician estimate create, #1614 invoice revisions, #1615 draft estimate edits; earlier #1604–#1607 legal text and account deletion.

Still open
- Technician estimate create and draft edits need #1613 and #1615 deployed.
- Growing invoice and reopen have no app screens yet.
- Files over 8 MB: the server's multipart confirm step is broken.
- Sign-in throttling, email verification at sign-up, sole-owner account deletion.
