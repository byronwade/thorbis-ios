# API gaps

The iOS app only shows records the Thorbis API returns. A missing route is listed here, and a rejected request is shown as the server's error.

## Draft estimate lines

`POST /v1/estimates/{id}/revise` replaces the lines of a sent or declined estimate. On the API's main branch it does not edit an unsent draft. A never-issued draft is refused (409, expected revision 0, current none), and a changed draft is refused (409, "a replacement draft already exists").

Web PR #1615 (BYR-1612) lets revise edit an unsent draft in place when the body carries the draft's `updatedAt` as `expectedUpdatedAt`. Without it the answer is 409 `draft_token_required`; with an old one it is 409 `stale_draft`. The app already sends `expectedUpdatedAt`. Until #1615 merges, saving draft lines fails against production, and the editor keeps the edits on screen with the server's error.

Approved estimates stay on the change-order path. Issued, paid, and void invoices do not accept line edits. Draft invoice lines still save through `POST /v2/invoices/{id}/lines`.

## Customer records compiled from jobs

- A job has no list of contacts and no list of service locations. `JobRecord` has one optional `locationId`, and that id is the organization branch, not a service address. Contacts and service locations stay on the customer (`GET /v1/customers/{id}/contacts`, `GET /v1/customers/{id}/locations`).
- There is no customer-wide media, notes, or documents route. The customer profile loads each job (`GET /v1/jobs/{id}/notes`, `GET /v1/jobs/{id}/media`) and groups the rows. Documents are media whose kind is not `photo`.
- Customer history (`GET /v1/customers/{id}/history`) emits `contact`, `location`, `estimate`, `job`, `invoice`, and `payment`. It does not emit calls, messages, or photos. A payment entry has no invoice id, so it cannot open a payment or an invoice.
- Customer notes: none on the API's main branch. Web PR #1611 adds `GET` and `POST /v1/customers/{id}/notes`. Until it merges, the app keeps customer notes on this phone only (`CustomerNotesStore`).
- `GET /v1/invoices?customerId=` can come back empty for a technician who can still read invoices on an assigned job. The profile also reads `GET /v1/jobs/{id}/invoices` and keeps the customer list when that route answers 404 or 405. Estimates and invoices are skipped entirely when the person lacks `estimate.view` or `invoice.view`.

## Activity

- Calls have a log and a detail (`GET /v1/calls`, `GET /v1/calls/{id}`, `GET /v1/calls/{id}/recording`, `POST /v1/calls/{id}/link`). There is no text-message thread route: a message row opens the job or the contact only when that row already names one. A row that names neither stays closed.
- Customer history payments do not include an invoice id, so those rows cannot open a payment or an invoice. A payment on an invoice's own activity does, because that screen already has both ids.
- Customer history does not include photos, notes, calls, or messages. Job activity is notes and status changes. A photo opens only when a row already names the job and the file.

## Routes the app calls that are not on the API's main branch yet

The web repository lists every route this app calls in `contracts/mobile/ios-endpoints.json`, and its `pnpm check` refuses a change that drops one. The routes below are marked pending there, each with the web pull request that adds it. Until that pull request merges, the screen behaves as described.

| Route | Web PR | Until it merges |
| --- | --- | --- |
| `POST /v1/account-lifecycle/reauthentications` | #1605 (BYR-1606), then #1606 and #1607 | Delete account says it is not available yet. #1607 also approves the retention policy, so deletion works only after all three. |
| `GET /v1/jobs/{id}/service-context` | #1608 (BYR-1599) | The job reads the customer, contacts and locations separately (`JobServiceContextLoader`). |
| `GET`/`POST /v1/jobs/checklist-templates` and its `{templateId}`, `archive`, `restore` routes | #1617 (BYR-1599) | Checklists are hidden: the `job_checklists` feature is off. |
| `GET`/`POST /v1/jobs/{id}/checklist-runs`, `.../answers`, `.../complete` | #1617 (BYR-1599) | Same as above. |
| `POST /v1/jobs/{id}/reopen` | #1612 (BYR-1611) | Reopen is hidden: the `job_reopen` feature is off. |
| `POST /v1/invoices/{id}/approved-estimates`, `GET /v1/invoices/{id}/revisions` | #1614 (BYR-1611) | Changing an issued invoice is hidden: the `invoice_revisions` feature is off. |

Draft line edits (#1615) use a route that exists on main with an older contract. Customer notes (#1611) have no route on main yet, so the app keeps them on the phone. Both are described in their sections above.
