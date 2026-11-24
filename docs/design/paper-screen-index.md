# Paper screen index (iOS)

This is the work list for making every iOS screen match the Paper "Thorbis Mobile" design exactly. Each row is one phone screen in Paper, mapped to the SwiftUI code in `Thorbis/Sources`.

Date: 2026-11-16

## Progress (2026-11-16, branch `paper-v2-tokens`, not yet built by CI)

The status column below is the starting point. Since then:

- **Restyled to Paper** (layout, words, sizes): every Update row in these areas — Schedule and Jobs (18, 18C, 19, 79, 80, 20, 20A, 57F), Job details (21, 21A, 21B, 21K, 23, 24), job and field tools (21C, 21D, 21F, 21H, 21M, 21N, 21O, 21P, 21U, 53, 53A, 53B, 75, 82, 83, 83A, F7, P1), Customers (47, 48N, 47A), customer records (48F, 85, 85C, 86, 86A, 86C, 87, 87A, 87B, 88, 88A, 88B), Messages and Search (49N, 49C, 51, 76, 77, 73B), Dashboard and Money (52, 58, 54, 59, 54A, 60, 20E, 20F), estimates and invoices (33, 34, 34A, 35, 35A–E, 35L, 36, 40, 40A–D, 40L, 89, 89A), payments and customer pages (37, 38, 38A–C, 38F, 38H, 39, 39A, 39C, 39E, 39F, 39H, 39I, 39M, 39T), login and setup (04–17, 09A, 09B, 11A, 11B, 14A, 15A, 29A, 61, 61N, 61A, 61B, 97), team and settings (55, 61D, 62, 62A–E, 63, 65, 65A, 65F, 65G, 73A, 91, 91A, 96), and the drawer/sidebar (29N, 57N, 58N and their tablet sidebars). Each kept what the app's data supports; the gaps are listed in the port plan.
- **Shared styles follow Paper**: canvas, 20pt cards, Paper type sizes with 34 Bold titles, blue pill commits, 22 Bold sheet titles, filled fields, section labels with trailing counts, segments, list rows.
- **New screens built**: 01–03 intro, 05A–05C and 29B join a team, 21R Running late, F3A Can't start, 30/32 Add materials (scan, paste), 48C Edit customer, 65B Edit profile, 65C My notifications, 67 Account and data, 67B Change password, 68 Delete account (server refuses until it issues a re-authentication proof), 69 Privacy and permissions, 85B Cancel membership, 98C guided tour (one step), P5 legal page (no legal text supplied yet).
- **Still New, not buildable today**: 20B/20C saved views (no route), 39D Enter card, 39J/39R card reader, 39Q Scan a check (no route or SDK), 85A autopay and 85E book tune-ups (no routes), 85D plan editor (route exists, no phone design), 95 Customer display settings, TE7 Insert link, 11B direct connect (no route), 12D apprentice role.
- **Second pass, also restyled**: field mode (F1 stop card and progress card, F2 driving, F3 arrived, F6 paid then next stop, F7 quick capture, F8 menu rows), 21E pause sheet, 21T status menu, menus generally, the text editor (TE1 full-screen editor, TE6 customer view), states (73, 73C, 73E, 74, toasts), patterns (P2 chip, P3 picker, P4 confirm, P6 export title), system surfaces (94 Lock Screen and island, 94D widgets, 94B one title), tablet-only (T01, T10B, T12C, T12E, T54A), the delivery log (96B), call playback, review requests and the customer view home.
- **Left out in the second pass, and why**:
  - No data or route: TE2 clipboard bar, TE3/TE4 AI help, TE5 Markdown (descriptions are plain text); F1 "collected" and server "on time"; F2 "customer was texted"; F6 receipt, review request, follow-up, break; 21T step times and amounts; 96B stat tiles and recipient names; P2 full filter sheet; P6 PDF/CSV, date range, send-to; 73C "Contact support" and error references; 94 company row and Pause; widget drive time.
  - No such role: T12D apprentice. T12C and T12E are shown to office and owner, because there are no dispatcher or accountant roles.
  - System-owned: 94A caller ID (no extension) and 94C push text (the server writes it).
- **Third pass (full audit of every area, then cross-area fixes)**:
  - Shared pieces rebuilt: page menus open as Paper's bottom sheet (21K, F8, 21T, estimate and invoice menus; row menus and selects stay popovers), sheets use Paper's three headers (Cancel pill under the commit, close circle, Done pill in the header), a confirm with a reason field (Ownership transfer, Remove member), 28 Bold `Theme.heading()`, 44 Bold `Theme.display()`, 52 Bold payment amounts, foldable section labels.
  - Built because the routes exist after all: 48B/48H archive and restore customers, 35B/35E estimate versions and restore, 70 Location explainer (the app asks for location for drive time), 71 permission explainers, 09B logo crop, 86A unit page, 88A truck page, 20A full filter sheet with a date range, 75 New job composer, 19 setup checklist, 73B outbox, F4 working and F5 wrap-up field layouts, 23/24 Money tab, 21B Activity tab, 39A Finish job, 89 deposit chips, 34/34A price book, 53B assigned tech and notify.
  - Still left out, no data or route: tax rows, due dates and terms, card on file, receipts, review requests, cost and margin, bank balances, payroll, period tabs, per-alert notification choices, Google/Apple sign-in, job type, priority, distance, drive miles, "customer was texted", cancel reasons and trip fee (the cancel route takes no body), AI help, Markdown, video in the photo grid, team tab in Messages.
  - Kept different on purpose: 44pt tap targets where Paper draws smaller; seven colours one shade off for contrast; notifications stay grouped by day inside Messages; the job's Money bar keeps the money step; Delete account says nothing was deleted until the server can issue a sign-in check.
  - Not checked: T58 iPad widgets (not found in the tablet file).

Scope:
- Phone codes come from the main phone file, Missing screens, Navigation, Long descriptions, Field mode, and the Second, Third and Fourth pass files. Light, Archive and backup copies are skipped because they match the dark screens one for one.
- Every phone row also has a tablet twin, named `T` plus the code (for example T21S, TF3A, TP2). The twin uses the same Swift view with the iPad layout (`TabletLayout.swift`, `TabletRoot`). Field mode is TF1 to TF8. Tablet uses rails instead of the 29, 57 and 58 sidebars, and has no 18A. Tablet-only screens have their own table at the end.
- Rows marked "superseded by …N" have a newer Navigation screen. Build to the N screen.
- The Coverage artboard in the Navigation file compares Paper with the React Native app and the web, not with iOS. Its "no route yet" notes, such as call detail and bottom tabs, are not iOS evidence. Swift has the call thread (`CommsCallThreadView`) and a left drawer.
- "API exists" means one of three things: the iOS client already calls the route, the route is in `Thorbis-TanStack/services/api/openapi.json`, or Better Auth has it built in (organization invitations, password reset and change, update user). A screen that needs no server, such as an OS permission prompt or a static page, counts as New.
- Check API rows against `Thorbis-TanStack` main: `services/api/src/routes/manifest.ts` (the source) and `services/api/openapi.json` (generated from it). A route that exists only on an open web PR counts as Needs API and is listed in [GAPS.md](../GAPS.md).
- Routes known to be missing always win: pipeline and leads, marketing, workflows, banking, bills, payroll runs, vendors and purchase orders, message threads, customer-wide media, fleet sync, time clock, truck stock, receipts and training. Two-step sign-in is also missing, because the auth config has no `twoFactor` plugin.
- `Theme.swift` already carries Paper's tokens: dark `#1F1F1F`, brand `#2F6BFF` (drawn one shade off as `#2F6AFF`), and the light set. Screen layouts and words have not been compared with Paper one by one yet, so every existing screen is Update and none is Match.

Status legend:
- **Match**: the code already has the screen. Its layout may still need Paper styling.
- **Update**: the Swift screen exists, but its layout or words clearly differ from Paper.
- **New**: there is no Swift screen, but the API exists or no API is needed.
- **Needs API**: there is no server route for it.
- **Not on iOS**: Apple commerce rules ban it (72, 15B, 10B), or it is a web page on the customer's own phone and not iOS work.

Preview names are `--paper-preview-screen <name>` (with `--paper-preview`). "sheet:" means `--paper-preview-sheet`. A dash means there is no preview name.

## Onboarding & setup

| Code | Paper screen | Swift view / route | Preview name | Status | Notes |
|---|---|---|---|---|---|
| 01 | App intro 1 (Run your day) | — | — | New | No intro screens; static |
| 02 | App intro 2 (Whole job) | — | — | New | Static |
| 03 | App intro 3 (Get paid) | — | — | New | Static |
| 04 | Login | `LoginView` | state-login | Update | Also state-login-error |
| 05 | Sign up | `SignUpView` (Onboarding.swift) | onboard-signup | Update | |
| 05A | You're invited | — | — | New | Better Auth accept invitation |
| 05B | Join the team | — | — | New | Better Auth invitation |
| 05C | You're in | — | — | New | |
| 06 | Forgot password | `PasswordResetRequestView` (LoginView.swift) | — | Update | |
| 06A | Two-step code | — | — | Needs API | No twoFactor plugin |
| 06B | Set a new password | — | — | New | Better Auth reset; web link today |
| 07 | Check your email | `PasswordResetRequestView` sent state | — | Update | Check the sent state |
| 08 | Setup 1 (Welcome) | `SetupWizardView` | onboard-wizard | Update | |
| 09 | Setup 2 (Company) | `SetupWizardView` .company / `CreateCompanyForm` | onboard-company | Update | |
| 09A | Setup 2 (Validation errors) | `SetupWizardView` .company | onboard-company | Update | Error state |
| 09B | Logo | `CompanyLogoPicker` | — | Update | |
| 10 | Setup 3 (Communication) | `SetupWizardView` .messages | onboard-setup | Update | Email only in code |
| 10A | Setup 3 (Port number) | — | — | Needs API | Telephony numbers |
| 10B | Pick a phone number | — | — | Not on iOS | Apple commerce rule |
| 11 | Setup 4 (Import) | `SetupWizardView` .customers → `CustomerImportView` | — | Update | |
| 11A | Setup 4 (Import in progress) | `CustomerImportView` | — | Update | /v1/customer-imports |
| 11B | Import from another app | `CustomerImportView` | — | Update | File import only; direct connect needs API |
| 12 | Setup 5 (Connect apps) | — | — | Needs API | Integrations |
| 12A | Setup 5 (App connected) | — | — | Needs API | |
| 13 | Setup 6 (Services) | `SetupWizardView` .services | — | Update | Price book |
| 14 | Setup 7 (Team) | `SetupWizardView` .team / `InviteMemberSheet` | — | Update | |
| 14A | Setup 7 (Invite sent) | `InviteMemberSheet` | — | Update | |
| 14B | Role picker | `MemberRoleSheet` | — | Update | Paper has 8 roles; code has 3 work roles |
| 15 | Setup 8 (Payments) | `SetupWizardView` .payments / `PaymentsSetupView` | — | Update | Stripe onboarding |
| 15A | Setup 8 (Payouts verified) | `PaymentsSetupView` | payments | Update | merchant-readiness |
| 15B | Add payment method (plan) | — | — | Not on iOS | Apple commerce rule |
| 16 | Setup 9 (Operations) | `SetupWizardView` .hours / `OperatingDetailsView` | onboard-details | Update | |
| 16A | On-call routing | — | — | Needs API | |
| 17 | Setup 10 (You're ready) | `SetupWizardView` .done | — | Update | |
| 29A | Switch workspace | `WorkspaceSelectionView` | state-workspaces | Update | |
| 29B | Join another workspace | — | — | New | Accept invitation in app |
| 73F | Access requested | — | — | Needs API | No access-request route |

## Schedule & today

| Code | Paper screen | Swift view / route | Preview name | Status | Notes |
|---|---|---|---|---|---|
| 18 | Schedule | `ScheduleView` (PaperWorkViews.swift) | schedule | Update | |
| 18A | Schedule (bottom bar option) | `ScheduleView` + bottom bar | bar-live | Update | Phone only |
| 18B | Create menu | `FloatingCreateButton` | create-menu | Update | |
| 18C | Next stop | `NextStop` lead card | next-stop | Update | |
| 19 | Today (empty state) | `ScheduleView` | schedule + `--paper-preview-empty` | Update | |
| 53 | Office · Schedule | `DispatchBoardView` | dispatch-board | Update | |
| 53A | Assign a technician | `JobAssignmentView` / PaperRoute.assign | job-assign | Update | |
| 53B | Reschedule visit | `JobScheduleView` / `QuickScheduleSheet` | job-schedule | Update | |
| 57F | Waiting for a slot | `ScheduleView` unscheduled | schedule-unscheduled | Update | |
| 79 | Schedule (week view) | `ScheduleView` week | schedule-week | Update | |
| 80 | Schedule (map view) | `ScheduleMapView` | schedule-map | Update | |
| 21R | Running late | — | — | New | Schedule plus job notices routes exist |

## Field mode

| Code | Paper screen | Swift view / route | Preview name | Status | Notes |
|---|---|---|---|---|---|
| F1 | Today (field) | `ScheduleView` my day | my-day | Update | |
| F2 | Driving | `NextStop` active | next-stop-active | Update | |
| F3 | Arrived | `JobDetailView` on site (TechnicianFlow) | job-onsite | Update | |
| F3A | Can't start | — | — | New | Job progress/followups routes exist |
| F4 | Working (capture) | `MediaCaptureFlow` | job-media | Update | |
| F4A | Recording voice note | `JobVoiceNoteSheet` (NoteDictation) | — | Update | Dictation, not audio |
| F5 | Wrap up | `JobCloseoutView` | job-closeout | Update | |
| F6 | Paid — next stop | `InvoicePaymentCollectionSheet` → `NextStop` | invoice-payment | Update | |
| F6A | Review request | `ReviewRequestsView` (settings only) | — | Needs API | Manual send has no route; auto send exists |
| F7 | Quick capture | `MediaCaptureFlow` / `QuickNotesRow` | — | Update | |
| F8 | Job menu | `JobBrief` ••• menu | job | Update | |

## Jobs

| Code | Paper screen | Swift view / route | Preview name | Status | Notes |
|---|---|---|---|---|---|
| 20 | Jobs | `JobsView` | jobs | Update | |
| 20A | Jobs (filters sheet) | `JobsView` filters (JobFiltering.swift) | jobs-filters | Update | |
| 20B | Jobs (saved views) | — | — | New | /v1/query saved views |
| 20C | Saved views (+ save sheet) | — | — | New | Same as 20B |
| 20L | Jobs (long titles) | `JobsView` | jobs | Update | |
| 20S | Jobs from a menu shortcut | `FilteredJobsView` / PaperRoute.filteredJobs | — | Update | |
| 21 | Job details | `JobDetailView` (PaperJobDetailView.swift) | job | Update | |
| 21A | Job details (Activity · photos) | `JobMediaView` | job-media | Update | |
| 21B | Job details (Activity) | `JobDetailView` activity | job-activity | Update | |
| 21C | Camera · tag at capture | `MediaCaptureFlow` / `BurstCameraOverlay` | — | Update | |
| 21D | Photo markup | `PhotoMarkupView` | — | Update | |
| 21E | Job (pause with reason) | `JobStatusMenuPanel` / JobActionAPI | — | Update | Check the reason sheet |
| 21F | Job checklist | `JobChecklistSheet` | tool-checklist | Update | |
| 21G | On my way (customer notified) | `JobAtAddressView` (notices) | job | Update | |
| 21H | Book a follow-up | `FollowUpBookingSheet` / `JobFollowUpsView` | job-followups | Update | |
| 21I | Parts used | — | — | Needs API | Truck stock |
| 21J | Job time and profit | `JobHours` | — | Update | Profit needs cost data |
| 21K | Job actions | `JobBrief` menu | job | Update | |
| 21L | Job details (long) | `JobDetailView` | job | Update | |
| 21M | Scan data plate | `DataPlateScannerSheet` | tool-scan | Update | |
| 21N | Measure | `SiteMeasureView` | — | Update | |
| 21O | At this address | `JobAtAddressView` | job-history | Update | |
| 21P | Before and after | `MediaCompareView` | — | Update | before-after route |
| 21Q | Job notes (read all) | `JobNoteDetailView` / notes list | job-notes | Update | |
| 21S | Photo viewer | `MediaPhotoViewer` / `JobMediaDetailView` | — | Update | |
| 21T | Change job status | `JobStatusMenuPanel` | — | Update | |
| 21U | Cancel job | JobOperationsViews cancel / JobActionAPI | — | Update | /v1/jobs/{id}/cancel |
| 21V | Document viewer | `DocumentPreviewController` | — | Update | |
| 21W | Add document | `MediaView` fileImporter | — | Update | |
| 21X | Address actions | `AddressLink` / `Directions` | — | Update | |
| 21Y | Log a reading | — | — | Needs API | No readings route |
| 21Z | Ask the office | OnsiteTools call office | job-onsite | Update | |
| 22 | Job details (add drawer) | `JobDetailView` add menu (`JobAddRow`) | job | Update | |
| 23 | Job details (Money · estimates) | `JobCustomerDocumentsView` | job-estimates | Update | |
| 24 | Job details (Money · invoice) | `JobCustomerDocumentsView` | job-invoice | Update | |
| 25 | Job details (edit field sheet) | `JobDetailView` edit sheets | — | Update | |
| 26 | Job details (contacts drawer) | `JobContactsSection` | job | Update | |
| 26A | Contacts drawer (quick add) | `CustomerContactSheet` | — | Update | |
| 26B | Contact | `CustomerContactDetailView` / PaperRoute.contact | — | Update | |
| 27C | On break | — | — | Needs API | Time clock |
| 75 | New job (composer) | `NewJobSheet` / `BookJobSheet` | new-job | Update | |
| 82 | Intake (incoming call → job) | `BookJobSheet` / `JobBookingCallSection` | book-job | Update | Also book-job-filled |
| 83 | Job wrap-up (sign & close) | `JobCloseoutView` | job-closeout | Update | |
| 83A | Finish with a balance | `JobCloseoutView` | job-closeout | Update | |
| 83B | Drafted from your voice note | — | — | Needs API | AI drafting |
| 99 | Checklist templates | `JobChecklistTemplates` | tool-checklist-pick | Update | Templates live on the device |
| 99A | Checklist template | `JobChecklistTemplates` | — | Update | Templates live on the device |

## Estimates & invoices

| Code | Paper screen | Swift view / route | Preview name | Status | Notes |
|---|---|---|---|---|---|
| 20E | Estimates | `EstimatesView` / PaperRoute.estimates | estimates | Update | |
| 20F | Invoices | `InvoicesView` / PaperRoute.invoices | invoices | Update | |
| 30 | Add materials (scan) | — | — | New | Price book search exists |
| 30A | Photo match | — | — | Needs API | AI match |
| 31 | Add materials (voice) | — | — | Needs API | Needs a parse route |
| 32 | Add materials (paste list) | — | — | New | Client parse plus price book search |
| 33 | Add materials (price book) | `PriceBookCartPicker` | builder-picker | Update | |
| 34 | Price book | `WorkspacePriceBookView` | price-book | Update | Internal feature gate |
| 34A | Price book item (edit) | `PriceBookItemEditor` | sheet: price-book-new | Update | |
| 35 | Create estimate | `NewEstimateView` / EstimateBuilder | new-estimate | Update | |
| 35A | Line items (inline edit) | `BuilderLineRow` / `EstimateLineGroupsEditor` | builder-line | Update | Also builder-options |
| 35B | Estimate revisions | `EstimateRevisionEditorView` | estimate-revision | Update | |
| 35C | Estimate detail | `EstimateDetailView` | estimate-detail | Update | |
| 35D | Estimate actions | `EstimateDetailView` menu | estimate-detail | Update | |
| 35E | Estimate revision | `EstimateRevisionEditorView` | estimate-revision | Update | |
| 35L | Create estimate (long) | `NewEstimateView` | estimate-draft | Update | |
| 36 | Sign estimate | `SignatureCaptureSheet` | signature | Update | |
| 37 | Present to customer | `CustomerEstimatePresentation` | present-estimate | Update | |
| 37L | Present (long) | `CustomerEstimatePresentation` | present-estimate-detail | Update | |
| 40 | Edit invoice | `InvoiceLineEditorView` | invoice-editor | Update | |
| 40A | Invoice discounts and combined bill | `InvoiceDiscountSheet` | invoice-editor | Update | No combined-bill route |
| 40B | Send to customer | `InvoiceDetailView` issue / `sendFieldEstimate` | invoice-detail | Update | Action exists; no text/email send sheet |
| 40C | Invoice detail | `InvoiceDetailView` | invoice-detail | Update | |
| 40D | Add discount or credit | `InvoiceDiscountSheet` / `EstimateDiscountSheet` | — | Update | |
| 40L | Edit invoice (full text) | `InvoiceLineEditorView` | invoice-editor-line | Update | |
| 81B | Supplier results | — | — | Needs API | Supplier search |
| TE1 | Text editor (writing) | Line description editor | builder-line | Update | |
| TE2 | Text editor (select/copy/paste) | Line description editor | — | Update | |
| TE3 | Text editor (AI help) | — | — | Needs API | AI |
| TE4 | Text editor (AI suggestion) | — | — | Needs API | AI |
| TE5 | Text editor (Markdown) | Line description editor | — | Update | |
| TE6 | Text editor · Customer view | `ReadOnlyDocumentDescription` | — | Update | |
| TE7 | Insert link | — | — | New | Client only |
| TE8 | Write from | — | — | Needs API | AI |

## Payments

| Code | Paper screen | Swift view / route | Preview name | Status | Notes |
|---|---|---|---|---|---|
| 39 | Collect payment | `InvoicePaymentCollectionSheet` | invoice-payment | Update | |
| 39A | Payment received | `InvoicePaymentCollectionSheet` done | invoice-payment | Update | |
| 39C | Scan to pay | `InvoicePaymentLinkView` | invoice-payment + `--paper-preview-pay-link ready` | Update | |
| 39D | Enter card | — | — | New | card-payments route |
| 39F | Collect payment (before Tap to Pay) | `TapToPayReadiness` | — | Update | |
| 39G | Bank transfer | `InvoiceCollectionOption` | — | Update | |
| 39H | Record a payment | `InvoicePaymentCollection` record | — | Update | |
| 39I | Refund | `InvoicePaymentRefundForm` | invoice-payment-refund-form | Update | |
| 39J | Card reader | — | — | New | Stripe Terminal; check reader support |
| 39M | Payment detail | `InvoicePaymentDetailSheet` | invoice-payment-refund | Update | |
| 39Q | Scan a check | — | — | New | Record payment plus photo |
| 39R | Pair a card reader | — | — | New | Same as 39J |
| 39S | Refund issued | `InvoicePaymentRefundStatusPanel` | invoice-payment-refund-confirmation | Update | Also pending, reconciliation |
| 39T | Custom amount | `InvoicePaymentCollection` custom amount | invoice-payment | Update | |
| 54A | Payments | `CompanyPaymentsView` (PaymentsList.swift) | payments | Update | |
| 89 | Request deposit | `JobDepositSheet` | — | Update | deposit-requests |
| 89A | Billing schedule | `BillingScheduleDetailView` | billing-detail | Update | Beta plus entitlement |
| 90 | Payouts | — | — | Needs API | Only merchant readiness |
| 90A | Banking | — | — | Needs API | Banking |
| 90B | Payout detail | — | — | Needs API | |
| 90C | Move money | — | — | Needs API | Banking |
| 90D | Team card | — | — | Needs API | Banking |
| 90E | Statements | — | — | Needs API | Banking |
| 90F | Transaction detail | — | — | Needs API | Banking |

## Customers

| Code | Paper screen | Swift view / route | Preview name | Status | Notes |
|---|---|---|---|---|---|
| 47 | Customers | `CustomersView` | customers | Update | |
| 47A | New customer | `NewCustomerSheet` | new-customer | Update | |
| 48 | Customer detail | `CustomerDetailView` | customer | Update | Superseded by 48N |
| 48N | Customer detail (linked records) | `CustomerDetailView` | customer | Update | |
| 48A | Customer (hold and delivery problem) | `CustomerDetailView` + `NoticeDeliveryLogView` | customer | Update | Check the hold state |
| 48B | Archive customer | — | — | New | Customer archive route |
| 48C | Edit customer | — | — | New | customers.update (used by self-edit) |
| 48D | Customer · Jobs tab | `CustomerDetailView` jobs | customer-jobs | Update | |
| 48E | Customer · Billing tab | `CustomerDetailView` money | customer-money | Update | |
| 48F | Customer · Media tab | `CustomerRecordsView` | customer-records | Update | Built from each job; no customer-wide route |
| 48G | Customer · Activity tab | `CustomerHistoryPage` | customer-activity | Update | No calls or messages in history |
| 48H | Archived customers | — | — | New | Customer list filter |
| 85 | Maintenance plan (membership) | `CustomerMembershipSection` | — | Update | /v1/memberships |
| 85A | Membership autopay | — | — | New | Verify write route; iOS only reads memberships |
| 85B | Cancel membership | — | — | New | Verify write route; iOS only reads memberships |
| 85C | Maintenance plans | `LocalWorkspaceView` .agreements | local-agreements | Update | Device-local; plans API exists |
| 85D | Plan editor | — | — | New | Verify write route; iOS only reads plans |
| 85E | Book tune-ups | — | — | New | Jobs routes plus memberships; verify |
| 86 | Equipment | `LocalWorkspaceView` .equipment / `CustomerEquipmentSection` | local-equipment | Update | /v1/equipment read |
| 86A | Equipment detail | `EquipmentEditor` | equipment-editor | Update | Also equipment-sections |
| 86B | Warranty registration | — | — | Needs API | |
| 86C | Add equipment | `EquipmentEditor` | equipment-editor | Update | |
| 87 | Property | `PropertyDetailView` | property-detail | Update | |
| 87A | Properties | `PropertiesView` | properties | Update | |
| 87B | Add property | `ServiceLocationSheet` | — | Update | |
| 95 | Customer display settings | — | — | New | Org facts; no screen |
| 97 | Import customers | `CustomerImportView` / PaperRoute.importCustomers | — | Update | |

## Messages

| Code | Paper screen | Swift view / route | Preview name | Status | Notes |
|---|---|---|---|---|---|
| 28 | Content portal | — | — | Needs API | |
| 28A | Announcement | — | — | Needs API | Team channels |
| 49 | Team messages | — | — | Needs API | Superseded by 49N |
| 49N | Messages (Customers and Team) | `CommsInboxView` / PaperRoute.inbox | inbox | Update | Team side needs API |
| 49C | Customer conversation | `CommsLocalThreadView` / `CommsCallThreadView` | inbox | Update | No message thread route; local drafts |
| 49D | New message | `CommsComposeSheet` | — | Update | |
| 50 | Channel thread (#dispatch) | — | — | Needs API | Team channels |
| 50A | Message composer (extras) | `CommsTextComposer` / `CommsCannedRepliesSheet` | — | Update | |
| 50B | Channel info | — | — | Needs API | |
| 51 | Call detail (transcript) | `CommsCallThreadView` / `CommsCallCard` (CommsInboxThread.swift) | inbox | Update | /v1/calls |
| 73B | Saved on this phone | `SavedWorkReviewView` (the offline outbox; same sheet as 73A, shown when nothing was refused) | sheet: saved-work | Update | |

## Money & office

| Code | Paper screen | Swift view / route | Preview name | Status | Notes |
|---|---|---|---|---|---|
| 27 | Time clock | — | — | Needs API | Time clock |
| 27A | Ask for time off | — | — | Needs API | |
| 27B | Fix a missed clock-out | — | — | Needs API | |
| 41 | Purchase order | — | — | Needs API | Vendors/POs |
| 41A | Receive purchase order | — | — | Needs API | |
| 42 | Vendors & purchase orders | — | — | Needs API | |
| 42A | Vendor detail | — | — | Needs API | |
| 42B | New vendor | — | — | Needs API | |
| 43 | Vendors & POs (PO tab) | — | — | Needs API | |
| 44 | Receipt scanner | — | — | Needs API | Receipts |
| 45 | Receipt scanner (camera) | — | — | Needs API | |
| 46 | Receipts | — | — | Needs API | |
| 46A | Receipt detail | — | — | Needs API | |
| 52 | Office · Dashboard | `OwnerHomeView` / PaperRoute.home | owner-home | Update | Office variant |
| 54 | Office · Money | `MoneyOverviewView` / `ReportsView(includesRevenue:)` | revenue | Update | |
| 55 | Office · Team + payroll | `TeamView` | team | Update | Payroll needs API |
| 55A | Time off requests | — | — | Needs API | |
| 56 | Office · Payroll tab | — | — | Needs API | Payroll runs |
| 56A | Approve timesheets | — | — | Needs API | |
| 56B | Payroll run | — | — | Needs API | |
| 56C | Timesheet | — | — | Needs API | |
| 59A | Bills | — | — | Needs API | Bills |
| 59B | Bill detail | — | — | Needs API | |
| 82A | Pipeline (leads) | — | — | Needs API | |
| 82B | Lead detail | — | — | Needs API | |
| 82C | New lead | — | — | Needs API | |
| 84 | Inventory (truck stock) | — | — | Needs API | |
| 84A | Restock request | — | — | Needs API | |
| 84B | Stock item | — | — | Needs API | |
| 84C | Add stock item | — | — | Needs API | |
| 88 | Fleet | `LocalWorkspaceView` .fleet | local-fleet | Update | Device-local; sync needs API |
| 88A | Vehicle detail | `LocalWorkspaceEditor` | local-fleet | Update | Device-local |
| 88B | Add vehicle | `LocalWorkspaceEditor` | — | Update | Device-local |
| 92 | Workflows | — | — | Needs API | |
| 92A | Marketing | — | — | Needs API | |
| 92B | Reply to review | — | — | Needs API | |
| 92C | Campaign | — | — | Needs API | |
| 92D | Lead sources | — | — | Needs API | |
| 92E | Workflow | — | — | Needs API | |
| 92F | Approval request | — | — | Needs API | |
| 93 | QuickBooks | — | — | Needs API | Not connected on web either |

## Owner & admin

| Code | Paper screen | Swift view / route | Preview name | Status | Notes |
|---|---|---|---|---|---|
| 58 | Owner · Dashboard | `OwnerHomeView` | owner-home | Update | |
| 58B | Owner · Morning briefing | — | — | Needs API | AI summary |
| 58C | Licenses and compliance | — | — | Needs API | |
| 59 | Owner · Money | `MoneyOverviewView` / `WorkspaceRevenueView` | revenue | Update | |
| 60 | Owner · Reports (P&L) | `ReportsView` | reports | Update | P&L needs costs |
| 60A | Profit and loss | — | — | Needs API | Costs and bills |
| 61 | Owner · Business settings | `BusinessSetupView` | — | Update | Superseded by 61N |
| 61N | Business settings | `BusinessSetupView` / PaperRoute.businessSetup | — | Update | |
| 61A | Hours, tax and terms | `OperatingDetailsView` | onboard-details | Update | |
| 61B | Company profile | `CompanyDetailsView` | — | Update | |
| 61C | Locations | — | — | Needs API | No branch route |
| 61D | Roles | `RoleEditorView` | — | Update | |
| 61E | Integrations | — | — | Needs API | |
| 62 | Owner · Team & permissions | `TeamView` | team | Update | |
| 62A | Ownership and closing | `TransferOwnershipPrompt` | — | Update | |
| 62B | Team member | `MemberAccessView` | — | Update | |
| 62C | Invite member | `InviteMemberSheet` | team + sheet: team-invite | Update | |
| 62D | Pending invite | `TeamInvites` | team | Update | |
| 62E | Offboard member | `RemoveMemberPrompt` | — | Update | |
| 63 | Owner · Role permissions (Office) | `RoleEditorView` | — | Update | |
| 64 | Course detail (EPA 608 renewal) | — | — | Needs API | Training |
| 64A | Lesson | — | — | Needs API | Training |
| 64B | Certification exam | — | — | Needs API | Training |
| 81 | AI assistant (Brain) | — | — | Needs API | |
| 81A | AI approvals | — | — | Needs API | |
| 91 | Team goals | `TeamGoalsView` | — | Update | |
| 91A | My scorecard | `ScorecardView` | scorecard | Update | |

## Settings

| Code | Paper screen | Swift view / route | Preview name | Status | Notes |
|---|---|---|---|---|---|
| 65 | Settings | `SettingsView` | settings | Update | Paper splits it into several screens |
| 65A | Menu and start screen | `CustomizeMenuView` | customize-menu | Update | |
| 65B | Edit profile | — | — | New | Better Auth update user |
| 65C | My notifications | — | — | New | /v1/notice-preferences |
| 65D | Saved signature | — | — | Needs API | No user-signature storage |
| 65E | Sign out | `SettingsView` confirm | state-signing-out | Update | |
| 65F | What's new | `WhatsNewHistoryView` / `WhatsNewSheet` | whats-new | Update | |
| 65G | Appearance | `SettingsView` appearance | settings | Update | |
| 67 | Account and data | — | — | New | deletion-requests route |
| 67A | Two-step sign in | — | — | Needs API | No twoFactor plugin |
| 67B | Change password | — | — | New | Better Auth change password |
| 68 | Delete account — confirm | — | — | New | /v1/account-lifecycle/deletion-requests; App Store rule |
| 69 | Privacy and permissions | — | — | New | OS settings only |
| 70 | Permission — Location | `PermissionPrimerView` (location) | — | Built | Explainer before the drive-time prompt |
| 71 | Permission — Notifications | `PushNotifications` | — | Update | System prompt only |
| 72 | Subscription and billing | — | — | Not on iOS | Apple commerce rule |
| 96 | Notification rules | `NoticeSettingsView` | notices | Update | |
| 96A | Edit rule | `NoticeSettingsView` | notices | Update | |
| 96B | Delivery log | `NoticeDeliveryLogView` | notice-log | Update | |
| 98 | Help | — | — | Needs API | Help content |
| 98A | Help article | — | — | Needs API | |
| 98B | Support chat | — | — | Needs API | |
| 98C | Guided tour | — | — | New | Static |

## Patterns & states

| Code | Paper screen | Swift view / route | Preview name | Status | Notes |
|---|---|---|---|---|---|
| 29 | Sidebar (Technician) | `AppDrawer` (CreamSheet.paperLayout) | menu + `--paper-preview-role tech` | Update | Superseded by 29N |
| 29N | Sidebar (Technician) | `AppDrawer` | menu + role tech | Update | |
| 57 | Sidebar (Office) | `AppDrawer` | menu + role office | Update | Superseded by 57N |
| 57N | Sidebar (Office) | `AppDrawer` | menu + role office | Update | |
| 57A | Sidebar (Manager) | `AppDrawer` | — | Update | Role doesn't exist (3 work roles) |
| 57B | Sidebar (CSR) | `AppDrawer` | — | Update | Role doesn't exist |
| 57C | Sidebar (Dispatcher) | `AppDrawer` | — | Update | Role doesn't exist |
| 57D | Sidebar (Apprentice) | `AppDrawer` | — | Update | Role doesn't exist |
| 57E | Sidebar (Accountant) | `AppDrawer` | — | Update | Role doesn't exist |
| 58A | Sidebar (Owner) | `AppDrawer` | menu + role owner | Update | Superseded by 58N |
| 58N | Sidebar (Owner) | `AppDrawer` | menu + role owner | Update | |
| 66 | Row actions (swipe + menu) | `JobRowSwipes` | jobs | Update | |
| 73 | Offline (working) | `OfflineBanner` | offline | Update | Also offline-job etc. |
| 73A | Changes that need attention | `SavedWorkReviewView` | sheet: saved-work | Update | |
| 73C | Couldn't load | `ListErrorRow` / `FieldProblem` | state-errors | Update | |
| 73D | No access | `JobAccessBanner` | state-errors | Update | |
| 73E | Loading | list skeletons (`CustomerSkeleton` etc.) | state-loading | Update | |
| 74 | Back online (syncing) | sync bar | bar-syncing | Update | |
| 76 | Search | `SearchScreen` / `SearchRoutePage` | search | Update | Also search-typed etc. |
| 76A | Search (no results) | `SearchScreen` | search-empty | Update | |
| 77 | Notifications | `NotificationsFeedView` / `StaffNoticesPage` | inbox | Update | /v1/staff/notices |
| P1 | Date and time picker | `QuickScheduleSheet` | job-schedule | Update | |
| P2 | Filter sheet | `RecordFilterBar` / jobs filters | jobs-filters | Update | |
| P3 | Pick a record | `CustomerPickerSheet` | — | Update | |
| P4 | Confirm (destructive) | `ThorbisConfirmAction` dialogs | state-sheets | Update | |
| P5 | Legal page | — | — | New | Static |
| P6 | Export | `ReportExportMenu` | reports | Update | .xlsx routes |

## Customer-facing

The tech's phone is in customer mode for these, except the "web" rows, which are pages on the customer's own phone.

| Code | Paper screen | Swift view / route | Preview name | Status | Notes |
|---|---|---|---|---|---|
| 38 | Choose options (shop) | `CustomerEstimatePresentation` | present-estimate | Update | |
| 38A | Your cart (review and approve) | `CustomerPresentationCommit` | present-estimate-review | Update | |
| 38B | Customer view (home) | `CustomerJobDocumentBook` | customer-view | Update | |
| 38C | Approve several estimates | `CustomerJobDocumentBook` | customer-view-estimates | Update | |
| 38D | Financing offer | `CustomerFinancingLine` | present-estimate-financing | Update | /v1/financing/offer |
| 38E | Approved (customer's phone) | — | — | Not on iOS | Customer web page |
| 38F | Financing | `FinancingTermsSheet` | present-estimate-financing | Update | |
| 38G | Financing approved | CustomerFinancing | — | Update | |
| 38H | Update my details | `CustomerSelfEditView` | customer-view-details | Update | |
| 39B | Pay link (customer's phone) | — | — | Not on iOS | Web; staff side is `InvoicePaymentLinkView` |
| 39E | Estimate response (customer's phone) | `PublicEstimateActionView` | public-estimate | Update | |
| 39K | Track your technician | — | — | Not on iOS | Customer web page |
| 39L | Leave a review | — | — | Not on iOS | Customer web page |
| 39N | Paid (customer's phone) | — | — | Not on iOS | Customer web page |
| 39O | Estimate declined (customer's phone) | — | — | Not on iOS | Customer web page |
| 39P | Thanks for your feedback | — | — | Not on iOS | Customer web page |
| 100 | Booking page (customer web) | — | — | Not on iOS | Customer web page |
| 100A | Booking confirmed | — | — | Not on iOS | Customer web page |

## System surfaces

| Code | Paper screen | Swift view / route | Preview name | Status | Notes |
|---|---|---|---|---|---|
| 94 | Lock screen (job in progress) | `JobLiveActivity` | glance-lock | Update | Also glance-island |
| 94A | Incoming call (caller ID) | CustomerPhoneLookup | — | Update | Check caller ID |
| 94B | Siri and Shortcuts | `ThorbisIntents` | — | Update | |
| 94C | Push notifications | `PushNotifications` | — | Update | APNs off on server |
| 94D | Home screen widgets | `GlanceGallery` widgets | glance-widgets | Update | |
| 94E | In a call | — | — | Needs API | VoIP calling |

## Tablet-only screens

| Code | Paper screen | Swift view / route | Preview name | Status | Notes |
|---|---|---|---|---|---|
| T01 | Schedule (split view) | `PaperTabletSchedule` / `TabletWeekBoard` | schedule (iPad) | Update | |
| T10B | Menu and start screen | `CustomizeMenuView` | customize-menu (iPad) | Update | |
| T12C | Dispatcher schedule | `DispatchBoardView` | dispatch-board (iPad) | Update | Role doesn't exist |
| T12D | Apprentice schedule | `PaperTabletSchedule` | — | Update | Role doesn't exist |
| T12E | Accountant money | `MoneyOverviewView` | revenue (iPad) | Update | Role doesn't exist |
| T40 | Error (500) | `ListErrorRow` / `FieldProblem` | state-errors (iPad) | Update | |
| T41 | Permission denied | `JobAccessBanner` / states | state-errors (iPad) | Update | |
| T42 | Loading skeleton | list skeletons | state-loading (iPad) | Update | |
| T54 | Help | — | — | Needs API | Help content |
| T54A | Payments | `CompanyPaymentsView` | payments (iPad) | Update | |
| T58 | Home screen widgets (iPad) | `GlanceGallery` | glance-widgets (iPad) | Update | |

## Counts

| Status | Rows |
|---|---|
| Match | 0 |
| Update | 226 |
| New | 36 |
| Needs API | 82 |
| Not on iOS | 12 |
| **Total** | **356** |

Counts include the 11 tablet-only rows and the old rows that a newer …N screen supersedes. Tablet twins of phone rows are not counted separately.

## New screens, most used first

These are ranked by how often a field tech or office user would open each one.

1. 21R Running late (tech, daily)
2. F3A Can't start (tech, weekly)
3. 48C Edit customer (office, daily)
4. 39D Enter card (tech, when Tap to Pay fails)
5. 70 Permission — Location (every tech, first run)
6. 30 Add materials (scan) (tech, estimates)
7. 32 Add materials (paste list) (tech and office, estimates)
8. 20B / 20C Saved views (office, daily)
9. 85E Book tune-ups (office, members; verify the route)
10. 85A Membership autopay (office; verify the route)
11. 85B Cancel membership (office; verify the route)
12. 48B Archive customer and 48H Archived customers (office)
13. 39Q Scan a check (tech, check payers)
14. 39J / 39R Card reader and pairing (tech, once per reader)
15. 65C My notifications (everyone, occasional)
16. 65B Edit profile (everyone, rare)
17. 05A / 05B / 05C Accept an invite (every new hire, once)
18. 29B Join another workspace (rare)
19. 06B Set a new password (rare)
20. 67B Change password (rare)
21. 67 Account and data, and 68 Delete account (rare, but App Store review requires it)
22. 85D Plan editor (owner, rare; verify the route)
23. 95 Customer display settings (owner, rare)
24. 69 Privacy and permissions (rare)
25. TE7 Insert link (office, rare)
26. 01 / 02 / 03 App intro, 98C Guided tour, P5 Legal page (first run or rare)
