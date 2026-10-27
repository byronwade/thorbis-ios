# iOS ↔ web parity checklist

The goal is a production iOS app at parity with the Thorbis web app (`Thorbis-TanStack/apps/web`). This file tracks each web feature against the app. **Done** means the app does it against the real API contract; it does not mean pixel parity.

| Web feature (apps/web/src/features) | iOS | Notes |
| --- | --- | --- |
| My day, Schedule, Unscheduled | Done | Schedule tab with Today, Week and Unscheduled. Next up carries the next lifecycle step. |
| Schedule map | Not yet | Job list records carry no coordinates. Service locations do; the map needs a per-job location read. |
| Jobs list, Job detail, job flow | Done | Overview, Estimates, Invoice, Media and Activity. The lifecycle runs from the server's transitions. |
| Job closeout, follow-ups, follow-up booking | Done / partial | Wrap-up checklist and follow-ups. Booking a follow-up into capacity is not native yet. |
| Job deposit request, commercial recovery | Not yet | |
| Customers, customer record, people and places | Done | Contacts and service locations. |
| Customer intake | Done | Name, phone, email, address, account type, preferred contact. Also available from the new-job composer. |
| Customer SMS consent, phone lookup | Not yet | |
| Estimates, estimate detail and workflow | Done | Build from the Price Book on a job, link, send, approve or decline, revise, option packages. |
| Invoices, invoice detail and workflow | Done | Create from the job, edit lines, issue, collect, record payment, refund. |
| Payments (collect) | Partial | Card payment link, cash, check and already-collected. Tap to Pay needs Apple's entitlement and a terminal. |
| Money, reports | Partial | Money (revenue report). Operations, schedule and payment-activity reports are not native yet. |
| Billing schedules | Not yet | |
| Pipeline (requests) | Not yet | |
| Price book, price item | Done (read) | Browse and detail; editing is web-only for now. |
| Properties, equipment, fleet, agreements | Device-only | "On this phone" records; the server has no contracts for these yet. |
| Team, team member, roles, role members | Not yet | APIs exist (`/v1/organization/role-members`, `/roles`). |
| Inbox, notices | Done | Staff notices with mark-read. |
| Search | Done (local) | Searches loaded jobs and customers. Server search (`/v1/search`) is not used yet. |
| Settings, notice settings | Partial | Account, appearance, sign-out. Notice preferences are not native yet. |
| Offline queue, sync banner | Done | Cached workspace, queued steps and notes, photos kept until uploaded. |
| Workflows, agent / Brain | Not yet | |
| Customer portal, document action page | Done | Public estimate decision screen. |
| Account deletion | Blocked | Server endpoint exists, but production has no reauthentication or retention policy configured. |
