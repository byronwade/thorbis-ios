# API gaps

The iOS app only shows records the Thorbis API returns. Missing routes are listed here instead of filled with invented data.

## Customer records compiled from jobs

- A job has no list of contacts and no list of service locations. `JobRecord` has one optional `locationId`, and that id is the organization branch, not a service address. Contacts and service locations stay on the customer (`GET /v1/customers/{id}/contacts`, `GET /v1/customers/{id}/locations`).
- There is no customer-wide media, notes, or documents route. The customer profile loads each job (`GET /v1/jobs/{id}/notes`, `GET /v1/jobs/{id}/media`) and groups the rows. Documents are media whose kind is not `photo`.
- Customer history (`GET /v1/customers/{id}/history`) emits `contact`, `location`, `estimate`, `job`, `invoice`, and `payment`. It does not emit calls, messages, or photos. A payment entry has no invoice id, so it cannot open a payment or an invoice.
- `GET /v1/invoices?customerId=` can come back empty for a technician who can still read invoices on an assigned job. The profile also reads `GET /v1/jobs/{id}/invoices` and keeps the customer list when that route answers 404 or 405. Estimates and invoices are skipped entirely when the person lacks `estimate.view` or `invoice.view`.
