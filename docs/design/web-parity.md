# iOS ↔ web parity checklist

The goal is a production iOS app at parity with the Thorbis web app (`Thorbis-TanStack/apps/web`). This file tracks each web feature against the app. **Done** means the app does it against the real API contract; it does not mean pixel parity.

| Web feature (apps/web/src/features) | iOS | Notes |
| --- | --- | --- |
| My day, Schedule, Unscheduled | Done | Schedule tab with Today, Week and Unscheduled. Next up carries the next lifecycle step. |
| Schedule map | Done | Schedule → Map: the day's stops as numbered pins from each job's service location, with Open job and Directions. |
| Jobs list, Job detail, job flow | Done | Overview, Estimates, Invoice, Media and Activity. The lifecycle runs from the server's transitions. |
| Job closeout, follow-ups, follow-up booking | Done | Wrap-up checklist, follow-ups, and booking a return visit into an arrival window (falls back to office review when nobody is free). |
| Job deposit request, commercial recovery | Partial | Deposit request done (Invoice tab). Commercial recovery is not native yet. |
| Customers, customer record, people and places | Done | Contacts and service locations. |
| Customer intake | Done | Name, phone, email, address, account type, preferred contact. Also available from the new-job composer. |
| Customer SMS consent, phone lookup | Partial | Job texts consent on the customer (GET/POST /v1/customers/{id}/sms-consent). Phone lookup not yet. |
| Estimates, estimate detail and workflow | Done | Build from the Price Book on a job, link, send, approve or decline (with an in-person customer signature), revise, option packages. |
| Invoices, invoice detail and workflow | Done | Create from the job, edit lines, issue, customer authorization signature, collect, record payment, refund. |
| Payments (collect) | Partial | Card payment link, cash, check and already-collected. Tap to Pay (Stripe Terminal) is built and the server is live; it stays hidden until Apple grants the entitlement. |
| Money, reports | Done (read) | Money (revenue). Reports: estimate conversion, jobs and schedule backlog. The payment-activity report and XLSX export are web only. |
| Billing schedules | Done | List, schedule progress (billed, remaining, deposits, retainage), bill the remainder, release retainage, and deposit request on a job. Each command keeps its idempotency key until the server answers. Gated by `progress_billing`. |
| Pipeline (requests) | Not yet | |
| Price book, price item | Done | Browse, detail, and for owners: add, edit (new revision) and remove items. |
| Properties, equipment, fleet, agreements | Partial | Equipment and memberships are on the server (customer equipment with warranty, membership plans, member pricing on estimates). Fleet and properties stay "On this phone" records. |
| Team, team member, roles, role members | Done (read) | Team & permissions list with roles for owners and admins. Invites and role changes are web only. |
| Inbox, notices | Done | Staff notices with mark-read. |
| Search | Done | Searches the whole company through the Search Gateway (`GET /v1/search`): jobs, customers, estimates, invoices and billing schedules. Offline, or if the gateway fails, it searches the jobs and customers saved on the phone and says so. |
| Settings, notice settings | Done | Account, appearance and sign-out, plus the job-notice matrix (owner, dispatcher and technician × email and in-app). The delivery log is web only. |
| Offline queue, sync banner | Done | Cached workspace, queued steps and notes, photos kept until uploaded. |
| Workflows, agent / Brain | Not yet | |
| Customer portal, document action page | Done | Public estimate decision screen. |
| Account deletion | Blocked | Server endpoint exists, but production has no reauthentication or retention policy configured. |
| Mobile menu layout | Done | Customize menu per phone; owners can save a company-wide layout (GET/POST /v1/organization/mobile-layout). |
| Push notifications | App side done | Registers with POST /v1/devices; the server sends once its APNs key is configured. |
