# API gaps

The iOS app only shows records the Thorbis API returns. A missing route is listed here, and a rejected request is shown as the server's error.

## Draft estimate lines

There is no separate route that replaces the lines of a draft estimate. `POST /v1/estimates` creates a draft. `POST /v1/estimates/{id}/revise` is the route the app uses to save line changes on a draft, a sent estimate, or a declined estimate. A never-issued draft sends `expectedRevisionNumber` 0. A draft that already has `currentRevisionNumber` sends that number. The revise response is the updated draft. If the server rejects a draft, the editor shows that error and does not treat the save as successful.

`docs/superpowers/plans/2026-10-27-estimate-revision-options.md` still describes revise as sent or declined only, and says an existing draft cannot be changed through that endpoint. This repository has no newer draft-update route. The editor still submits the revise request, which is the only write the API client has for line changes, and it leaves the form open with the server's error when that request is rejected.

Approved estimates stay on the change-order path. Issued, paid, and void invoices do not accept line edits. Draft invoice lines still save through `POST /v2/invoices/{id}/lines`.

## Customer records compiled from jobs

- A job has no list of contacts and no list of service locations. `JobRecord` has one optional `locationId`, and that id is the organization branch, not a service address. Contacts and service locations stay on the customer (`GET /v1/customers/{id}/contacts`, `GET /v1/customers/{id}/locations`).
- There is no customer-wide media, notes, or documents route. The customer profile loads each job (`GET /v1/jobs/{id}/notes`, `GET /v1/jobs/{id}/media`) and groups the rows. Documents are media whose kind is not `photo`.
- Customer history (`GET /v1/customers/{id}/history`) emits `contact`, `location`, `estimate`, `job`, `invoice`, and `payment`. It does not emit calls, messages, or photos. A payment entry has no invoice id, so it cannot open a payment or an invoice.
- `GET /v1/invoices?customerId=` can come back empty for a technician who can still read invoices on an assigned job. The profile also reads `GET /v1/jobs/{id}/invoices` and keeps the customer list when that route answers 404 or 405. Estimates and invoices are skipped entirely when the person lacks `estimate.view` or `invoice.view`.

## Activity

- There is no call thread and no message thread. A call or message row opens the job, or the contact, only when that row already names one. A row that names neither stays closed.
- Customer history payments do not include an invoice id, so those rows cannot open a payment or an invoice. A payment on an invoice's own activity does, because that screen already has both ids.
- Customer history does not include photos, notes, calls, or messages. Job activity is notes and status changes. A photo opens only when a row already names the job and the file.
