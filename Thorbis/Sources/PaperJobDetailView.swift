import SwiftUI
import UIKit

struct JobDetailView: View {
    let jobId: String
    let showsBack: Bool
    /// Today's stop card's Customer view circle: open the job, then its Customer view once loaded.
    let opensCustomerView: Bool

    init(jobId: String, showsBack: Bool = true, opensCustomerView: Bool = false) {
        self.jobId = jobId
        self.showsBack = showsBack
        self.opensCustomerView = opensCustomerView
        #if DEBUG
        // The old five sections' links land on the three that hold them now: estimates and
        // invoices on Money, photos as Activity's Photos filter.
        let previewTabs = ["offline-job-money": "Money", "job-invoice": "Money", "job-estimates": "Money", "job-activity": "Activity", "job-notes": "Activity", "job-media": "Activity", "job-invoice-empty": "Money"]
        _selectedTab = State(initialValue: PaperPreview.enabled ? previewTabs[PaperPreview.screen] ?? "Overview" : "Overview")
        if PaperPreview.enabled, PaperPreview.screen == "job-media" { _activityFilter = State(initialValue: "Photos") }
        // The composer with a quick note already tapped in, ready to edit before saving.
        if PaperPreview.enabled, PaperPreview.screen == "job-notes" { _note = State(initialValue: NoteDraftText.joined("", QuickNotes.phrases[2])) }
        #endif
    }
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @EnvironmentObject var session: SessionController
    @EnvironmentObject var outbox: FieldOutbox
    @EnvironmentObject private var pendingMedia: PendingMediaStore
    @Environment(\.dismiss) private var dismiss
    @State private var job: JobRecord?
    @EnvironmentObject private var estimateHandoffPresenter: JobEstimateHandoffPresenter
    @StateObject private var customerWindowAnchor = CustomerWindowAnchor()
    @State private var customerPaymentInvoiceID: String?
    @State private var documentInvoiceID: String?
    @State private var overviewDocument: OverviewJobDocumentRoute?
    @State private var notes: [JobNoteRecord] = []
    @State private var note = ""
    /// Speech-to-text into `note`; it only fills the draft, saving still goes through `saveNote`.
    @StateObject private var dictation = NoteDictation()
    /// The drive to this job's place while it is still ahead (the map strip's pill).
    @StateObject private var eta = NextStopETA()
    @Environment(\.scenePhase) private var scenePhase
    @State private var reason = ""
    @State private var nextAction = ""
    @State private var showPause = false
    @State private var busy = false
    @State private var error: String?
    @State private var selectedTab = "Overview"
    /// True while the job is scrolled past the top of its sections (the tabs are pinned).
    @State private var tabsPinned = false
    @StateObject private var documents = JobDocumentCollections()
    @State private var documentGeneration: UUID?
    @State private var overviewEstimatesAuthority: CustomerHandoffExitAuthority?
    @State private var preparingEstimate = false
    @State private var overviewInvoicesAuthority: CustomerHandoffExitAuthority?
    private var invoiceRead: JobDocumentRead<InvoiceRecord>? { documents.invoices }
    private var invoices: [InvoiceRecord] { invoiceRead?.records ?? [] }
    private var invoicesLoaded: Bool { invoiceRead != nil }
    private var invoicesFailed: Bool { invoiceRead?.isComplete == false }
    @State private var selectedInvoiceID: String?
    @State private var overviewPaymentRefreshing = false
    @State private var overviewNavigationRevision = UUID()
    @State private var invoicePaymentModel: InvoicePaymentCollectionModel?
    @State private var loadedInvoiceModelID: String?
    @State private var invoicePaymentLoads = JobInvoicePaymentLoads()
    @State private var paymentRoute: JobInvoicePaymentRoute?
    @State private var activityFilter = "All"
    @State private var activityFilterBeforePhotos = "All"
    #if DEBUG
    @State private var previewPaymentRevalidated = false
    @State private var previewOverviewPaymentHold = false
    #endif
    @State private var showSchedule = false
    private var estimateRead: JobDocumentRead<EstimateRecord>? {
        guard let job, let read = documents.estimates, read.scope == scope(for: job),
              documentGeneration == session.generation,
              overviewEstimatesAuthority?.isCurrent(api: api, session: session) == true else { return nil }
        return read
    }
    private var jobEstimates: [EstimateRecord] { estimateRead?.records ?? [] }
    private var estimatesLoaded: Bool { estimateRead != nil }
    private var estimatesFailed: Bool { estimateRead?.isComplete == false }
    @State private var showNewEstimate = false
    @State private var committed = 0
    /// Set when the person opens a wrap-up row; the next drop in rows left plays a light tap.
    @State private var wrapUpTapArmed = false
    @State private var wrapUpTaps = 0
    @State private var creatingInvoice = false
    @State private var reviewInvoiceID: String?
    @State private var showDeposit = false
    /// TF-01: the estimate opened from the next step; it goes straight to the customer when asked.
    @State private var openEstimate: OpenedEstimate?
    /// Set by a new estimate's save, opened once its sheet has closed (TF-06).
    @State private var createdEstimateID: String?
    @State private var showWrapUp = false
    /// The on-site commit at "0 left": one confirm, then the job completes in place.
    @State private var confirmComplete = false
    /// The customer’s locations are account records, not verified job-site associations.
    @State private var locations: [ServiceLocationRecord] = []
    @State private var locationsContext: String?
    @State private var locationsFailed = false
    /// The primary contact's phone (else the customer's), for one-tap Call and Text.
    @State private var customerPhone: String?
    /// JS-06: every contact on the account, and the account for its preferred channel.
    @State private var contacts: [CustomerContactRecord] = []
    @State private var customerRecord: CustomerRecord?
    @State private var contactsLoaded = false
    @State private var contactsFailed = false
    @State private var contactsContext: String?
    @State private var customerAuthorityID: String?
    /// JS-09/JS-10: this visit in counts, and the customer's other visits. Nil until read.
    @State private var followUps: [FieldFollowUpRecord]?
    @State private var mediaCount: String?
    @State private var mediaCountContext: String?
    @State private var mediaCountRequest = UUID()
    @State private var visits: [JobVisitRecord] = []
    /// True once visit history answered for this job, so an unread history is never shown as none.
    @State private var visitsLoaded = false
    @State private var bookingCall: BookingCallRecord?
    @State private var showAssign = false
    @State private var pauseReasonProblem: String?
    @State private var pauseNextProblem: String?
    /// Paper 21E: the reason chip picked in the pause sheet; the note under it adds to it.
    @State private var pauseChoice: String?
    /// Paper F2: when the drive should end, pinned when the drive time arrives so it never drifts.
    @State private var driveArrival: Date?
    @State private var showFollowUps = false
    @State private var showRunningLate = false
    @State private var showCantStart = false
    /// Paper 21K / 21T "Cancel job": Wrap up opens straight on its cancel confirm.
    @State private var wrapUpCancels = false
    /// Paper F8 "Full job details" and 21K "At this address": bumped to scroll Overview to `detailsScrollTarget`.
    @State private var detailsScroll = 0
    @State private var detailsScrollTarget = "job-property-history"
    @State private var cantStartNote: String?
    @State private var handoff: DeviceHandoff?
    /// The first page of the visit's photos (the strip on Overview, thumbnails in Activity).
    @State private var mediaPhotos: [MediaAssetRecord] = []
    @State private var mediaHasMore = false
    /// The server's closeout checklist, read while on site for "Before you wrap up". Nil hides it.
    @State private var closeout: FieldCloseout?
    /// The workspace's business phone, when this role can read it, for the on-site call circle.
    @State private var officeContact: OfficeContact?
    /// The customer's equipment on file (Paper 21 "Equipment", F3 "Know before you knock"). Empty
    /// when the read is refused or an older server has no such route.
    @State private var equipment: [EquipmentRecord] = []
    /// Paper 26A: the quick-add contact sheet, from the Contacts label's plus.
    @State private var showAddContact = false
    @State private var showScan = false
    @State private var showChecklist = false
    @State private var memberPricing: MemberPricing?
    /// A capture the toolkit asked the media screen to open (camera, scan, measure).
    @State private var mediaLaunch: JobMediaLaunch?
    @State private var followUpKind: FieldFollowUpRequest.Kind = .notifyOffice
    /// The draft invoice opened in the line editor by Add part.
    @State private var partsInvoice: InvoiceRecord?
    @State private var shareJob: SharedText?
    @FocusState private var noteFocused: Bool
    #if DEBUG
    @State private var previewOpenedCustomerView = false
    #endif
    /// Set once the stop card's Customer view has opened, so coming back never opens it again.
    @State private var openedCustomerViewOnArrival = false
    @Environment(\.openURL) private var openURL
    @Environment(\.inboxText) private var inboxText
    @Environment(\.inboxEmail) private var inboxEmail
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Paper 21: three sections. Photos are Activity's Photos filter (Paper 21A), one chip away.
    private let tabs = ["Overview", "Money", "Activity"]
    /// Paper 21B's filter chips, in its order.
    private let activityFilters = ["All", "Notes", "Photos", "Status", "Money"]
    private var showsPhotos: Bool { selectedTab == "Activity" && activityFilter == "Photos" }
    /// Paper's map: a job out on its visit opens in Field mode (F2 to F8), a screen of its own with
    /// no sections. "More › Full job details" closes it onto Job details (Paper 21), whose
    /// "Field mode" card opens it again.
    @State private var fieldModeOpen = JobDetailView.opensInFieldMode
    /// The design preview opens Job details (Paper 21) for every job screen name, as it did before
    /// field mode was a screen of its own; `job-onsite`, `--paper-preview-field-mode` and
    /// `--paper-preview-field-step` open field mode. The app itself always starts in field mode.
    private static var opensInFieldMode: Bool {
        #if DEBUG
        guard PaperPreview.enabled else { return true }
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--paper-preview-full-details") { return false }
        return PaperPreview.screen == "job-onsite" || arguments.contains("--paper-preview-field-mode")
            || arguments.contains("--paper-preview-field-step")
        #else
        return true
        #endif
    }
    /// Paper 21O "At this address", pushed from More.
    @State private var showAtAddress = false
    /// Paper F4A "Recording voice note": the sheet, when it began and the draft as it was before.
    @State private var showVoiceNote = false
    @State private var voiceNoteStarted = Date()
    @State private var voiceNoteBefore = ""
    @State private var voiceNoteDiscarded = false
    /// Paper 22 "Add to job": the sheet, and the row picked in it (run once the sheet has gone).
    @State private var showAdd = false
    @State private var pendingAdd: (() -> Void)?
    /// Paper 21J "Time and profit", from the job's More menu.
    @State private var showTime = false
    /// Paper F5: the tech moved on from Working to Wrap up without an estimate to approve first.
    @State private var wrapUpStageOpen = false
    /// The visit was under way on this screen, so a job paid and completed here stays on Paper F6
    /// "Paid" instead of dropping back to Job details.
    @State private var visitSeen = false

    /// Retire a mounted sheet on material authority or job changes. A routine
    /// authority revision alone does not discard a technician's entered amount.
    /// This token does not establish fresh per-invoice authorization.
    private var paymentAuthorityToken: [String] {
        [session.generation.uuidString,
         session.user?.id ?? "", session.activeOrganization?.id ?? "", String(session.policyVersion ?? 0),
         session.authorityGeneration ?? "",
         api.requestGeneration.uuidString, api.savedCopyScopeRevision.uuidString,
         api.savedCopyScope ?? "", api.normalizedOrigin ?? "", job?.id ?? "",
         job?.organizationId ?? "", job?.customerId ?? "",
         String(session.can("job.view", feature: "jobs")),
         String(session.can("invoice.view", feature: "invoicing")),
         String(session.can("invoice.payment.create", feature: "payments"))]
    }

    private var liveActivityKey: String {
        guard let job else { return "" }
        return [job.id, job.status, outbox.pendingStatus(for: job.id) ?? "",
                session.generation.uuidString, session.authorityRevision.uuidString,
                String(session.can("job.view", feature: "jobs")),
                // The card's street and access labels arrive with the job's locations.
                street(job) ?? "", liveActivityAccess(job) ?? ""].joined(separator: "|")
    }

    private var liveMediaCountContext: String? {
        guard session.can("job.view", feature: "jobs"), let actor = session.user?.id,
              let organization = session.activeOrganization?.id, let job, job.organizationId == organization,
              let policy = session.policyVersion, let origin = api.normalizedOrigin else { return nil }
        return [actor, organization, job.id, session.generation.uuidString, session.authorityRevision.uuidString,
                String(policy), api.requestGeneration.uuidString, origin].map { "\($0.utf8.count):\($0)" }.joined()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OfflineBanner().padding(.top, 4)
            SavedCopyNote(savedAt: api.savedCopyDate("/v1/jobs/\(jobId)"))
            // Offline, a load with no saved copy clears `error` (the banner above says so); what is
            // left is an action that needs a connection, which must say so rather than fail silently.
            if let error { ErrorBanner(message: error) { await retry() }.padding(.top, 4) }
            if let issue = documentReadIssue {
                ErrorBanner(message: issue) { await retry() }.padding(.top, 4)
            }
            if let job {
                if showsPhotos {
                    // Photos keep their own scrolling grid and capture bar (camera, scan, measure),
                    // so the one-line header, sections and filters stay fixed above them.
                    if !typeSize.isAccessibilitySize { header(job, compact: true) }
                    tabBar(job)
                    // Paper 21A: Activity's filter chips stay over the photos, Photos chosen.
                    activityFilterChips.padding(.horizontal, 16).padding(.bottom, 8)
                    JobMediaView(jobID: jobId, launch: $mediaLaunch)
                } else {
                    // At accessibility sizes, the full job header can be taller than the
                    // screen. Keep the section chooser reachable above the scrolling content.
                    if typeSize.isAccessibilitySize, !inField(job) { tabBar(job) }
                    ScrollViewReader { proxy in
                    ScrollView {
                    // The tabs pin under the nav bar, so switching Overview, Invoice or Activity
                    // never means scrolling back to the top first.
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    // Paper 23, 24 and 21B: Money and Activity keep the job's whole header (number,
                    // title, who and where, the chips); only the visit's steps stay on Overview.
                    fullHeader(job, showsSteps: inField(job))
                    // At accessibility sizes a fixed action can cover most of a small screen.
                    // Keep the same action early in the scrollable content instead.
                    if typeSize.isAccessibilitySize { primaryAction }
                    // Where the sections start; it reports when the tabs are pinned (scrolled past).
                    Color.clear.frame(height: 0).id("job-sections")
                        .onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).minY < -1 } action: { tabsPinned = $0 }
                    Section {
                        VStack(alignment: .leading, spacing: 20) {
                            switch selectedTab {
                            case "Money": moneyContent(job)
                            case "Activity": activityContent(job)
                            default: overviewContent(job)
                            }
                        }
                        // Paper 21: cards sit 16 in from the screen's edges, 14 under the sections on
                        // Overview and 16 on Money and Activity (the tab bar keeps 6 of it).
                        .padding(.horizontal, 16)
                        .padding(.top, inField(job) ? 0 : selectedTab == "Overview" ? 8 : 10)
                        .padding(.bottom, 28)
                    } header: {
                        // Pinned, the tabs keep the canvas behind them so rows never show through.
                        // Paper 23: Money is one page with no jump chips, so the header is the tabs alone.
                        if !typeSize.isAccessibilitySize, !inField(job) { tabBar(job).background(Theme.canvas) }
                    }
                    }
                    }
                    // Each section gets a scroll view of its own, starting at the top. Kept at the old
                    // offset, a section shorter than where the page was scrolled to (Money opened from
                    // Due on site far down Overview) had the lazy stack measure its content short, then
                    // long, then short again every frame, never settling (the app hung). A scrollTo
                    // from there did not help: the offset never moved.
                    // The field steps coming or going changes the height the same way, so that resets it too.
                    .id("\(selectedTab)-\(inField(job))")
                    // A section opened while the tabs are pinned (the pinned tabs, or Due on site, Open
                    // and See all far down the page) starts at its top, with the tabs still pinned.
                    .onChange(of: selectedTab) {
                        guard tabsPinned else { return }
                        proxy.scrollTo("job-sections", anchor: .top)
                    }
                    // Paper F8 "Full job details" / 21K "At this address": the menu asks for a place on Overview.
                    .onChange(of: detailsScroll) {
                        withMotion(.snappy) { proxy.scrollTo(detailsScrollTarget, anchor: UnitPoint(x: 0.5, y: 0.14)) }
                    }
                    #if DEBUG
                    // `--paper-preview-scroll-history`: screenshots start at "At this address".
                    .task {
                        guard PaperPreview.enabled else { return }
                        let args = ProcessInfo.processInfo.arguments
                        // `--paper-preview-scroll-toolkit`: screenshots start at the on-site toolkit.
                        let target = args.contains("--paper-preview-scroll-history") ? "job-property-history"
                            : args.contains("--paper-preview-scroll-toolkit") ? "job-toolkit"
                            // `--paper-preview-scroll-wrapup`: at "Before you wrap up" and what's on the invoice.
                            : args.contains("--paper-preview-scroll-wrapup") ? "job-wrap-up" : nil
                        // `--paper-preview-scroll center|bottom`: the job loads after the scroll view
                        // appears, so the app-wide default anchor never moves it; scroll once it has.
                        if target == nil, let anchor = PaperPreview.scrollAnchor {
                            try? await Task.sleep(for: .seconds(3))
                            proxy.scrollTo(anchor == .bottom ? "job-details" : "job-latest-activity", anchor: anchor == .bottom ? .bottom : .center)
                            return
                        }
                        guard let target else { return }
                        try? await Task.sleep(for: .seconds(3))
                        proxy.scrollTo(target, anchor: UnitPoint(x: 0.5, y: 0.22))
                    }
                    #endif
                    }
                    // Paper v2: the job is drawn straight on the canvas; its sections are the cards.
                }
            } else if error == nil {
                // MA-13: the record's shape while it loads, not a lone spinner.
                VStack(alignment: .leading, spacing: 10) {
                    Capsule().fill(Theme.fill).frame(width: 140, height: 12)
                    Capsule().fill(Theme.fill).frame(width: 240, height: 24)
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { _ in Capsule().fill(Theme.fill).frame(width: 80, height: Theme.chipHeight) }
                    }
                    SkeletonRows(count: 4, leading: false).padding(.horizontal, -Theme.gutter).padding(.top, 12)
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 12)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Loading job")
                Spacer(minLength: 0)
            }
            // The Money action is a sibling of the scroll view, so document
            // controls cannot draw or receive taps underneath the payment bar.
        }
        .background(Theme.canvas)
        .background(CustomerWindowAnchorView(anchor: customerWindowAnchor))
        .foregroundStyle(Theme.foreground)
        // Paper v2 (21 Job details): each section is a 13 Semibold label over its own card (radius 20)
        // on the canvas, so the job is no longer a Record room.
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar { toolbarActions }
        .toolbar(.hidden, for: .tabBar)
        .deviceHandoffs($handoff)
        .sheet(item: $shareJob) { TextShareSheet(text: $0.text).presentationDetents([.medium, .large]) }
        .sensoryFeedback(.success, trigger: committed)
        // A light tap as a wrap-up row the person opened turns done (phase 4). Armed by opening a
        // row, so rows that arrive done with loaded data never tap.
        .onChange(of: WrapUpList.left(wrapUpRows)) { old, new in
            guard new < old else { return }
            if wrapUpTapArmed { wrapUpTaps += 1 }
            wrapUpTapArmed = false
        }
        .sensoryFeedback(.impact(weight: .light), trigger: wrapUpTaps)
        .thorbisConfirm("Complete this job?", message: "Everything before wrap up is done.", isPresented: $confirmComplete,
                        actions: [ThorbisConfirmAction("Complete job") { Task { await completeHere() } }])
        .sheet(isPresented: $showDeposit) { SheetSurface {
            // Paper 89: the approved estimate's total feeds the 25% and 50% chips, when it is loaded.
            JobDepositSheet(jobID: jobId, estimateTotalCents: depositEstimateTotal, subtitle: depositSubtitle) { invoice in
                selectedInvoiceID = invoice.id
                Task { await loadInvoices() }
            }
        } }
        .thorbisDestination(item: $documentInvoiceID) { id in
            InvoiceDetailView(id: id, expectedJobScope: job.flatMap { scope(for: $0) }, invoiceReference: jobInvoiceReference(id))
                .onDisappear { Task { await loadInvoices(); await loadCloseout() } }
        }
        .thorbisDestination(item: $overviewDocument) { route in
            if overviewDocumentIsCurrent(route) {
                switch route.kind {
                case .estimate:
                    EstimateDetailView(id: route.documentID, jobID: route.scope.jobID)
                        .onDisappear { if let job { Task { await loadJobEstimates(job); await loadInvoices(); await loadCloseout() } } }
                case .invoice:
                    InvoiceDetailView(id: route.documentID, expectedJobScope: route.scope,
                                      invoiceReference: jobInvoiceReference(route.documentID))
                        .onDisappear { Task { await loadInvoices(); await loadCloseout() } }
                        .task {
                            #if DEBUG
                            if ProcessInfo.processInfo.arguments.contains("--paper-preview-overview-retire") {
                                await PaperPreview.expireDocumentSessionForTesting(session)
                            } else if PaperPreview.isJobDocumentsPreview,
                                      ProcessInfo.processInfo.arguments.contains("--paper-preview-overview-revalidate") {
                                try? await Task.sleep(for: .seconds(5))
                                guard !Task.isCancelled else { return }
                                await session.revalidate()
                            }
                            #endif
                        }
                }
            } else {
                PaperEmptyState(symbol: "lock", title: "Document unavailable", message: "Return to the job and refresh to open this document.", problem: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.canvas)
            }
        }
        .thorbisDestination(item: $reviewInvoiceID) { id in
            InvoiceDetailView(id: id, returnsWhenPaid: true, expectedJobScope: job.flatMap { scope(for: $0) }, invoiceReference: jobInvoiceReference(id))
                .onDisappear { Task { await loadInvoices(); await loadCloseout() } }
        }
        .thorbisDestination(item: $openEstimate) { opened in
            EstimateDetailView(id: opened.id, jobID: jobId, presentsOnOpen: opened.present)
                .onDisappear { if let job { Task { await loadJobEstimates(job); await loadInvoices(); await loadCloseout() } } }
        }
        .sheet(isPresented: $showScan) { SheetSurface {
            if let job { DataPlateScannerSheet(job: job) { showScan = false; Task { await load() } } }
        } }
        .sheet(isPresented: $showChecklist) { SheetSurface {
            if let job { JobChecklistSheet(job: job) { showChecklist = false; Task { await load() } } }
        } }
        .thorbisDestination(isPresented: $showWrapUp) {
            JobCloseoutView(jobID: jobId, place: job.flatMap { street($0) }, startsCancel: wrapUpCancels)
                .onDisappear { wrapUpCancels = false; Task { await loadCloseout() } }
        }
        // Add part: the price book on the job's draft invoice, as the invoice screen edits it.
        .sheet(item: $partsInvoice, onDismiss: { Task { await loadInvoices(); await loadCloseout() } }) { invoice in SheetSurface {
            NavigationStack {
                InvoiceLineEditorView(invoice: invoice) { updated in
                    updateInvoice(updated)
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        } }
        // v2: assigning a tech is a modal (one task), not a pushed page.
        .sheet(isPresented: $showAssign, onDismiss: { Task { await load() } }) { SheetSurface { JobAssignmentView(jobID: jobId) } }
        .task {
            #if DEBUG
            // Screenshot-only: the job's modals open over the job (job-assign, --paper-preview-pause).
            guard PaperPreview.enabled else { return }
            let opensAssign = PaperPreview.screen == "job-assign"
            let opensPause = ProcessInfo.processInfo.arguments.contains("--paper-preview-pause")
            // `--paper-preview-at-address`: Paper 21O opens over the job.
            if ProcessInfo.processInfo.arguments.contains("--paper-preview-at-address") {
                try? await Task.sleep(for: .seconds(2))
                showAtAddress = true
                return
            }
            if PaperPreview.screen == "job-voice-note" {
                try? await Task.sleep(for: .seconds(2))
                voiceNoteStarted = Date()
                showVoiceNote = true
                return
            }
            if PaperPreview.screen == "job-cancel" {
                try? await Task.sleep(for: .seconds(2))
                wrapUpCancels = true
                showWrapUp = true
                return
            }
            if PaperPreview.screen == "job-add" {
                try? await Task.sleep(for: .seconds(2))
                showAdd = true
                return
            }
            if PaperPreview.screen == "job-time" {
                try? await Task.sleep(for: .seconds(2))
                showTime = true
                return
            }
            // The job's other sheets, each by its own preview name.
            let sheetNames = ["job-add-contact", "job-running-late", "job-cant-start", "job-checklist", "job-scan", "job-reschedule"]
            guard opensAssign || opensPause || sheetNames.contains(PaperPreview.screen) else { return }
            try? await Task.sleep(for: .seconds(1.5))
            switch PaperPreview.screen {
            case "job-add-contact": showAddContact = true
            case "job-running-late": showRunningLate = true
            case "job-cant-start": showCantStart = true
            case "job-checklist": showChecklist = true
            case "job-scan": showScan = true
            case "job-reschedule": showSchedule = true
            default: if opensAssign { showAssign = true } else { showPause = true }
            }
            #endif
        }
        .task(id: job?.status) {
            if let job, JobFieldSteps.step(for: job.status) != nil { visitSeen = true }
        }
        .thorbisDestination(isPresented: $showAtAddress) {
            if let job { atAddressScreen(job) }
        }
        .sheet(isPresented: $showAdd, onDismiss: { pendingAdd?(); pendingAdd = nil }) { SheetSurface {
            if let job {
                let rows = addRows(job)
                JobAddSheet(billing: rows.billing, onTheJob: rows.onTheJob) { row in
                    pendingAdd = row.action
                    showAdd = false
                }
            }
        } }
        // Swiping the sheet away is Stop: the words stay in the draft, and the note field opens.
        .sheet(isPresented: $showVoiceNote, onDismiss: {
            dictation.stop()
            if voiceNoteDiscarded { note = voiceNoteBefore; return }
            guard dictation.problem != .denied else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                if selectedTab == "Activity" { noteFocused = true }
            }
        }) { SheetSurface {
            JobVoiceNoteSheet(dictation: dictation, text: note, before: voiceNoteBefore, started: voiceNoteStarted,
                              onDiscard: { voiceNoteDiscarded = true; showVoiceNote = false },
                              onStop: { showVoiceNote = false })
        } }
        .thorbisDestination(isPresented: $showTime) {
            if let job {
                JobTimeView(job: job, title: menuTitle(job),
                            technician: assignedDisplayName(for: job).flatMap { $0 == "Assigned" ? nil : $0 })
            }
        }
        .thorbisDestination(isPresented: $showFollowUps) {
            JobFollowUpsView(jobID: jobId, initialKind: followUpKind).onDisappear { Task { await loadFollowUps() } }
        }
        // Paper 26A: add a contact to the account from the job, then read the contacts again.
        .sheet(isPresented: $showAddContact) { SheetSurface {
            if let job {
                CustomerContactSheet(customerID: job.customerId) { _ in
                    Task { await loadContacts(job) }
                }
            }
        } }
        // Paper 21R and F3A, from the job's ••• menu.
        .sheet(isPresented: $showRunningLate) {
            if let job { RunningLateSheet(job: job, customer: customerRecord) }
        }
        .sheet(isPresented: $showCantStart) {
            SheetSurface {
                CantStartSheet(jobID: jobId) { outcome in
                    showCantStart = false
                    guard let outcome else { return }
                    // Truthful pending state: sent, or saved on this phone until it can send.
                    cantStartNote = outcome.message
                    Task {
                        await loadFollowUps()
                        try? await Task.sleep(for: .seconds(4))
                        cantStartNote = nil
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let cantStartNote {
                ThorbisToast(symbol: "hand.raised", message: cantStartNote)
                    .padding(.horizontal, Theme.gutter).padding(.bottom, 96)
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showNewEstimate, onDismiss: {
            // A saved estimate opens next, so the tech reviews it and hands it over (TF-06).
            if let id = createdEstimateID { createdEstimateID = nil; openEstimate = OpenedEstimate(id: id, present: false) }
        }) { SheetSurface {
            if let job {
                NewEstimateView(customerID: job.customerId, jobID: job.id, locationID: job.locationId, title: job.title) { estimate in
                    createdEstimateID = estimate.id
                    Task { await loadJobEstimates(job) }
                }
            }
        } }
        .task(id: customerAuthorityToken) {
            #if DEBUG
            if PaperPreview.isJobDocumentsPreview,
               ProcessInfo.processInfo.arguments.contains("--paper-preview-overview-hold-reload"),
               let authority = overviewInvoicesAuthority, !authority.isCurrent(api: api, session: session) {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
            }
            #endif
            if customerAuthorityID != customerAuthorityToken {
                customerAuthorityID = customerAuthorityToken
                locations = []
                locationsContext = nil
                locationsFailed = false
                contacts = []
                contactsContext = nil
                customerRecord = nil
                customerPhone = nil
                contactsLoaded = false
                contactsFailed = false
            }
            if documentGeneration != session.generation {
                #if DEBUG
                if PaperPreview.isJobDocumentsPreview, documentGeneration != nil,
                   ProcessInfo.processInfo.arguments.contains("--paper-preview-description-replace-session") {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                }
                #endif
                documentGeneration = session.generation
                documents.reset()
                selectedInvoiceID = nil
                invoicePaymentModel = nil
                loadedInvoiceModelID = nil
                paymentRoute = nil
            }
            await load()
            // The next step needs the job's paper, so it loads with the job, not only on its tab.
            await loadInvoices()
            if let job { await loadJobEstimates(job) }
            if opensCustomerView, !openedCustomerViewOnArrival, job != nil {
                openedCustomerViewOnArrival = true
                openCustomerView(.home)
            }
            #if DEBUG
            // `--paper-preview-screen customer-view[-estimates|-invoice|-details]`: Customer view, opened as a tech would.
            if PaperPreview.enabled, PaperPreview.screen.hasPrefix("customer-view"), !previewOpenedCustomerView {
                previewOpenedCustomerView = true
                switch PaperPreview.screen {
                case "customer-view-estimates": openCustomerView(.estimates)
                case "customer-view-invoice": if let invoice = invoices.first { openCustomerView(.invoice(invoice.id)) }
                case "customer-view-details": openCustomerView(.details)
                default: openCustomerView(.home)
                }
            }
            #endif
        }
        .refreshable {
            await SavedCopies.$liveOnly.withValue(true) {
                await load()
                if let job { await loadContacts(job) }
                await loadInvoices()
                if let job { await loadJobEstimates(job) }
            }
        }
        // The Lock Screen card follows the status shown here, queued steps included.
        .task(id: liveActivityKey) {
            guard let job else { return }
            let pending = outbox.pendingStatus(for: job.id)
            let generation = session.generation
            let authority = session.authorityRevision
            await JobLiveActivity.sync(job: job, status: pending ?? job.status, waitingToSync: pending != nil,
                                       customer: store.customerName(job.customerId), address: street(job),
                                       access: liveActivityAccess(job)) {
                session.generation == generation && session.authorityRevision == authority &&
                session.activeOrganization?.id == job.organizationId &&
                session.can("job.view", feature: "jobs")
            }
        }
        // Coming back from Assign, Wrap up or Follow-ups: the job may have moved on.
        .onAppear { customerWindowAnchor.visible = true; if job != nil { Task { await load() } } }
        .onChange(of: session.can("customer.view", feature: "core_crm")) { _, _ in
            locations = []
            locationsContext = nil
            locationsFailed = false
            contacts = []
            contactsContext = nil
            customerRecord = nil
            customerPhone = nil
            contactsLoaded = false
            contactsFailed = false
        }
        .onChange(of: paymentAuthorityToken) { _, _ in paymentRoute = nil }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { dictation.stop() }
        }
        .onDisappear { customerWindowAnchor.visible = false; overviewNavigationRevision = UUID(); dictation.stop() }
        .onChange(of: selectedTab) { previous, tab in
            overviewNavigationRevision = UUID()
            if tab != "Activity" { dictation.stop(); noteFocused = false }
            if tab == "Money" { Task { await loadInvoices() } }
            // Photos added under Activity show in the Overview count straight away (JS-09).
            // Back on site from a note or the camera, the wrap-up rows read the job again.
            if previous == "Activity", activityFilter == "Photos" || (tab == "Overview" && isOnSite) {
                Task { await loadMediaCount(); await loadCloseout() }
            }
        }
        .onChange(of: activityFilter) { previous, current in
            if current == "Photos", previous != "Photos" { activityFilterBeforePhotos = previous }
            if previous == "Photos" { Task { await loadMediaCount() } }
        }
        .onChange(of: selectedInvoiceID) { _, selectedID in
            guard let selectedID, let invoice = invoices.first(where: { $0.id == selectedID }) else { return }
            Task { await loadInvoicePayments(for: invoice) }
        }
        .safeAreaInset(edge: .bottom) {
            Group {
            // Paper 21B: the composer leads Activity's page, so Activity keeps the job's bar like
            // Overview. Photos have their own capture bar, and the bar steps aside for the keyboard.
            if !typeSize.isAccessibilitySize, !showsPhotos, !noteFocused { primaryAction }
            }
        }
        .sheet(isPresented: $showPause) { SheetSurface {
            // v2 modal: two sunk fields, one ink commit in the sheet's pad. The commit is never
            // pre-disabled: pressing it says what is missing under the field. The form keeps what was typed.
            // Paper 21E "Pause this job": reason chips, a note for the office, when to come back.
            ThorbisModalSheet(title: "Pause this job", subtitle: job.map { "\(menuTitle($0)) \u{00B7} \(jobNumber($0))" },
                              closeLabel: "Cancel", onClose: { showPause = false },
                              detents: [.height(500), .large], commitTitle: "Pause job", busy: busy,
                              commitIdentifier: "pause-commit", commit: { attemptPause() }) {
                pauseForm
            }
            .interactiveDismissDisabled(busy || !reason.isEmpty || !nextAction.isEmpty || pauseChoice != nil)
        } }
        .sheet(isPresented: $showSchedule, onDismiss: { Task { await load() } }) { SheetSurface {
            if let job {
                JobScheduleView(job: job, compact: true) { updatedJob in
                    self.job = updatedJob
                }
            }
        } }
        // A payment changes the balance the next step reads, wherever it was collected from.
        .sheet(item: $paymentRoute, onDismiss: { Task { await loadInvoices(); await loadCloseout() } }) { route in
            paymentSheet(route)
        }
    }

    /// The estimate this job was booked from, once the job's estimates are read in full.
    private var depositEstimate: EstimateRecord? {
        guard let estimateID = job?.estimateId, estimatesLoaded, !estimatesFailed,
              session.can("estimate.view", feature: "estimates") else { return nil }
        return jobEstimates.first { $0.id == estimateID }
    }

    /// Paper 89 "Estimate total": the approved estimate's one set of lines, in US dollars. Nil when
    /// it has pricing options or another currency, so a share is never taken of a guessed total.
    private var depositEstimateTotal: Int? {
        guard let estimate = depositEstimate, (estimate.options ?? []).isEmpty, !estimate.lines.isEmpty,
              estimate.lines.allSatisfy({ $0.unitPrice.currency == "USD" }) else { return nil }
        return paperLinesTotal(estimate.lines)
    }

    /// Paper 89's second line: "EST-1042 · Danielle Marlowe".
    private var depositSubtitle: String? {
        guard let job, let estimateID = job.estimateId else { return nil }
        let customer = store.customerName(job.customerId)
        let reference = "EST-\(estimateID.suffix(4).uppercased())"
        return customer == "Customer" ? reference : "\(reference) \u{00B7} \(customer)"
    }

    /// Paper 21E's reasons, in its order. "Other" needs the note to say why.
    private static let pauseReasons = ["Waiting on parts", "Customer not home", "Need a second tech", "Weather", "Other"]

    /// The reason the office reads: the chip, then the note ("Waiting on parts. 40/5 capacitor on
    /// order"); the note alone for Other or when no chip is picked.
    private var pauseReasonText: String {
        let noteText = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let choice = pauseChoice, choice != "Other" else { return noteText }
        return noteText.isEmpty ? choice : "\(choice). \(noteText)"
    }

    /// Paper 21E: which job, "Reason" over its chips, the note, then "Come back". The server takes
    /// the reason and the next step as words, so "Come back" stays a field rather than a picker.
    private var pauseForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                PaperSectionLabel(title: "Reason", inset: 0, gap: 0)
                FlowRow(spacing: 8, lineSpacing: 4) {
                    ForEach(Self.pauseReasons, id: \.self) { option in
                        pauseReasonChip(option)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                TextField("Add a note for the office", text: $reason, prompt: .placeholder("Add a note for the office"), axis: .vertical)
                    .font(Theme.font(16)).lineLimit(1...5).fieldWell()
                    .accessibilityIdentifier("pause-note")
                if let pauseReasonProblem { FieldProblem(message: pauseReasonProblem) }
            }
            // Paper 21E: "Come back" is one row, its answer on the right ("Tomorrow morning").
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 12) {
                    Text("Come back").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                        .fixedSize()
                    TextField("Tomorrow morning", text: $nextAction, prompt: .placeholder("Tomorrow morning"))
                        .font(Theme.font(16))
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel("Come back")
                        .accessibilityHint("The office sees this on the job")
                        .accessibilityIdentifier("pause-come-back")
                }
                .fieldWell()
                if let problem = pauseNextProblem ?? error { FieldProblem(message: problem) }
            }
        }
    }

    /// One reason chip: 40 tall in a 44pt target, brand-tinted when picked (tap again to clear).
    private func pauseReasonChip(_ option: String) -> some View {
        let selected = pauseChoice == option
        return Button {
            pauseChoice = selected ? nil : option
            pauseReasonProblem = nil
        } label: {
            PaperChoiceChipLabel(title: option, isOn: selected)
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("pause-reason-\(option.lowercased().replacingOccurrences(of: " ", with: "-"))")
    }

    @ViewBuilder private func paymentSheet(_ route: JobInvoicePaymentRoute) -> some View {
        if route.authorityToken == paymentAuthorityToken,
           let job, let scope = scope(for: job), route.belongs(to: scope),
           session.can("job.view", feature: "jobs"), session.can("invoice.view", feature: "invoicing"),
           session.can("invoice.payment.create", feature: "payments") {
            // Paper 39A: once paid, "Finish job" opens the wrap-up and "Book the next visit" the
            // return-visit form; each only when this person can do it on this job.
            InvoicePaymentCollectionSheet(model: route.model, invoice: route.invoice, invoiceReference: route.reference,
                                          onFinishJob: paidFinishJob(job), onBookNextVisit: paidBookNextVisit)
                .thorbisSheetSurface().presentationDetents([.large]).presentationDragIndicator(.visible)
                #if DEBUG
                .overlay(alignment: .topLeading) {
                    if PaperPreview.enabled, ProcessInfo.processInfo.arguments.contains("--paper-preview-payment-revalidate") {
                        Button(previewPaymentRevalidated ? "Preview revalidated" : "Preview revalidate") {
                            Task {
                                let previous = session.authorityRevision
                                if ProcessInfo.processInfo.arguments.contains("--paper-preview-payment-revoke") {
                                    PaperPreviewProtocol.revokePaymentPermission()
                                }
                                await session.revalidate()
                                previewPaymentRevalidated = session.authorityRevision != previous
                            }
                        }
                        .accessibilityIdentifier(previewPaymentRevalidated ? "preview-payment-revalidated" : "preview-payment-revalidate")
                    }
                }
                #endif
                #if DEBUG
                .task {
                    guard PaperPreview.enabled,
                          ProcessInfo.processInfo.arguments.contains("--paper-preview-payment-scope-aba") else { return }
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    let original = api.savedCopyScope
                    api.savedCopyScope = (original ?? "preview") + "-other"
                    api.savedCopyScope = original
                }
                #endif
        }
    }

    /// Paper 39A "Finish job": on site, for someone who may complete jobs, the paid screen's commit
    /// opens the job's wrap-up (its checks, then Complete). Nil leaves the commit as "Done".
    private func paidFinishJob(_ job: JobRecord) -> (() -> Void)? {
        guard ["arrived", "in_progress"].contains(shownStatus(job)),
              session.can("job.complete", feature: "jobs") else { return nil }
        return { showWrapUp = true }
    }

    /// Paper 39A "Book the next visit": the job's return-visit request, for someone who may edit it.
    private var paidBookNextVisit: (() -> Void)? {
        guard session.can("job.edit", feature: "jobs") else { return nil }
        return {
            followUpKind = .officeScheduling
            showFollowUps = true
        }
    }

    /// Native bar with Thorbis circles: our back on the left (`thorbisDestination`), share and
    /// the job's one menu on the right (HIG-005, JS-02).
    @ToolbarContentBuilder private var toolbarActions: some ToolbarContent {
        if let job, showsBarTitle(job) {
            // Paper F2 to F4: out on the visit the bar carries the job, centred: its title at
            // 17 Semibold over "Danielle Marlowe · JOB-2214" at 13 muted. The 34 Bold header is
            // left out there (`fullHeader`), so the steps lead the screen.
            ThorbisToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(menuTitle(job))
                        .font(Theme.font(17, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("job-title")
                    Text(barSubtitle(job))
                        .font(Theme.font(13)).monospacedDigit()
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .accessibilityIdentifier("job-number")
                }
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
        }
        if let job {
            // Paper 21: Share, then More. Field mode (F2) keeps More alone.
            if !inField(job) {
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    // Paper 21's Share circle. Its sheet leads with Share job, then the other ways
                    // the job goes out (Customer view, Email customer, Add to Calendar, Copy job ID)
                    // and the favorite star, which Paper 21K's More no longer carries.
                    ThorbisMenu(items: shareMenuItems(job), title: "Share", accessibilityLabel: "Share job",
                                presentation: .sheet, subtitle: menuSubtitle(job)) {
                        PaperIcon(.share, size: 20).frame(width: 44, height: 44).background(Theme.card, in: Circle())
                    }
                    .accessibilityIdentifier("job-share")
                }
            }
            ThorbisToolbarItem(placement: .topBarTrailing) {
                // One quiet circle (Job.dc.html): Share job sits in the menu with the rest, so it is always there.
                // Paper 21K: a bottom sheet titled "More" over "AC not cooling · JOB-2214". Out on the
                // visit it is Paper F8: the job as the title, "JOB-2214 · customer" under it, the
                // "Full job details" card, a close circle and field mode's larger rows.
                ThorbisMenu(items: moreMenuItems(job),
                            title: inField(job) ? menuTitle(job) : "More", accessibilityLabel: "Job actions",
                            opensOnAppear: Self.previewOpensMoreMenu,
                            presentation: .sheet,
                            subtitle: menuSubtitle(job),
                            lead: fullDetailsLead(job),
                            closeCircle: inField(job), fieldMode: inField(job)) {
                    // Paper: a 44pt card circle, no rim.
                    PaperCircleLabel(symbol: "ellipsis", size: 44, fill: Theme.card)
                }
            }
        }
    }

    /// JS-03: only what this person can do now, without the step the bar is carrying.
    private func menuGroups(_ job: JobRecord) -> [[JobMenuAction]] {
        JobMenu.groups(JobMenu.Inputs(
            transitions: availableTransitions(job).filter { nextStep != .transition($0) },
            canSchedule: session.can("job.assign", feature: "jobs"),
            canAssign: session.can("job.assign", feature: "jobs"),
            canBillWithoutEstimate: invoicesLoaded && !invoicesFailed && invoices.isEmpty && (onSiteWrapsUp || nextStep != .createInvoice)
                && job.status == "in_progress" && session.can("invoice.create", feature: "invoicing"),
            canRequestDeposit: invoicesLoaded && !invoicesFailed && invoices.isEmpty && job.estimateId != nil
                && session.can("invoice.create", feature: "progress_billing"),
            // The job's bar shows on Overview and Activity; on Money (and over the photos) Wrap up
            // stays in the menu. On site the bar walks the wrap-up rows, so the closeout screen
            // (checks, unpaid follow-up, cancel) stays in the menu.
            barIsWrapUp: !showsPhotos && nextStep == .wrapUp && !onSiteWrapsUp,
            canShowToCustomer: session.can("estimate.view", feature: "estimates") || session.can("invoice.view", feature: "invoicing"),
            canEditCustomer: session.can("customer.edit", feature: "core_crm"),
            canAddToCalendar: JobFiltering.date(job.scheduledFor) != nil,
            canEmail: customerEmail(job) != nil,
            canSendRunningLate: ["scheduled", "dispatched", "en_route"].contains(shownStatus(job))
                && JobFiltering.date(job.scheduledFor) != nil,
            canReportCantStart: shownStatus(job) == "arrived" && session.can("job.edit", feature: "jobs")))
    }

    /// The primary contact's email, else the account's, only while this customer's contacts are current.
    private func customerEmail(_ job: JobRecord) -> MailDraft? {
        guard customerContext(job) == contactsContext, contactsContext != nil else { return nil }
        let email = contacts.first(where: \.primary)?.email ?? contacts.first(where: { $0.email != nil })?.email ?? customerRecord?.email
        return MailDraft(recipient: email, subject: job.title)
    }

    /// Out on the visit (driving, arrived, working), the job follows Paper's field mode (F2 to F8).
    private func inField(_ job: JobRecord) -> Bool {
        fieldModeOpen && onVisit(job) && selectedTab == "Overview"
    }

    /// The visit is under way (driving, arrived or working): the statuses field mode has a step for.
    private func onVisit(_ job: JobRecord) -> Bool { fieldStep(job) != nil }

    /// Where the job is on field mode's five steps: Driving (also a dispatched job of this
    /// person's, today, before the drive starts), Arrived, Working, Wrap up, Paid. Nil when the
    /// job isn't this person's visit to run.
    private func fieldStep(_ job: JobRecord) -> Int? {
        let status = shownStatus(job)
        if let step = JobFieldSteps.step(for: status) {
            guard step == 2 else { return step }
            return fieldPaid ? 4 : fieldWrapsUp ? 3 : 2
        }
        if status == "completed", visitSeen, fieldPaid { return 4 }
        return startsVisit(job) ? 0 : nil
    }

    /// A dispatched job assigned to this person for today, with the drive as its next move: field
    /// mode opens on its first step, the commit reading "On my way".
    private func startsVisit(_ job: JobRecord) -> Bool {
        guard shownStatus(job) == "dispatched", let me = session.user?.id, job.assignedToUserId == me,
              let scheduled = JobFiltering.date(job.scheduledFor), Calendar.current.isDateInToday(scheduled) else { return false }
        return nextStep == .transition("en_route")
    }

    /// Paper F6 "Paid": the job's invoice has been issued and nothing is left owing on it.
    private var fieldPaid: Bool {
        guard session.can("invoice.view", feature: "invoicing"), invoicesLoaded, !invoicesFailed,
              let bill = WrapUpList.billingInvoice(invoices), bill.status != "draft", bill.status != "void",
              bill.amountPaid > 0, let due = TechJobFlow.due(bill) else { return false }
        return due == 0
    }

    /// The job's next stop for this person today: the earliest booked job that isn't this one.
    private var nextStopJob: Job? {
        guard let me = session.user?.id else { return nil }
        return PaperWorkGroups.scheduled(store.jobs)
            .filter { $0.id != jobId && $0.assignedToUserId == me }
            .filter { JobFiltering.date($0.scheduledFor).map(Calendar.current.isDateInToday) == true }
            .min { (JobFiltering.date($0.scheduledFor) ?? .distantFuture) < (JobFiltering.date($1.scheduledFor) ?? .distantFuture) }
    }

    /// Paper F2 to F4: on the visit the job's title lives in the bar. At accessibility sizes a bar
    /// can't hold it whole, so the page keeps its own header there.
    private func showsBarTitle(_ job: JobRecord) -> Bool {
        inField(job) && !typeSize.isAccessibilitySize
    }

    /// Paper F2's second bar line: "Danielle Marlowe · JOB-2214".
    private func barSubtitle(_ job: JobRecord) -> String {
        let customer = store.customerName(job.customerId)
        return customer == "Customer" ? jobNumber(job) : "\(customer) \u{00B7} \(jobNumber(job))"
    }

    /// "Danielle" for a person, the whole name for a business, "customer" when the name isn't loaded.
    private func customerCallName(_ job: JobRecord) -> String {
        let name = store.customerName(job.customerId)
        if name == "Customer" { return "customer" }
        if customerRecord?.accountType == "commercial" { return name }
        guard let first = name.split(whereSeparator: \.isWhitespace).first else { return name }
        return String(first)
    }

    /// The customer's number, only while this customer's contacts are the ones loaded.
    private func customerReach(_ job: JobRecord) -> JobReach {
        JobReach(phone: customerContext(job) == contactsContext ? customerPhone : nil, email: nil)
    }

    /// Paper F8 "Job menu": on the visit the menu leads with Call and Text for the customer, then
    /// the office (Paper 21K's "Call the office" and "Text the office") when its phone is on file.
    private func reachMenuItems(_ job: JobRecord) -> [ThorbisMenuItem] {
        var items: [ThorbisMenuItem] = []
        if inField(job) {
            let reach = customerReach(job)
            let name = customerCallName(job)
            if let call = reach.call {
                items.append(ThorbisMenuItem("Call \(name)", icon: "phone") { openURL(call) })
            }
            if let text = reach.text {
                items.append(ThorbisMenuItem("Text \(name)", icon: "message") {
                    inboxText(text, name: store.customerName(job.customerId), openURL: openURL)
                })
            }
        }
        if let call = officeContact?.callURL {
            items.append(ThorbisMenuItem("Call the office", icon: "phone") { openURL(call) })
        }
        if let text = officeContact?.textURL {
            // Paper F8 words the office's text "Message dispatch"; Paper 21K, "Text the office".
            if inField(job) {
                items.append(ThorbisMenuItem("Message dispatch", icon: "arrow.left.arrow.right") { openURL(text) })
            } else {
                items.append(ThorbisMenuItem("Text the office", icon: "bubble.left") { openURL(text) })
            }
        }
        return items
    }

    /// "JOB-2214": the job's short number, as the header writes it.
    private func jobNumber(_ job: JobRecord) -> String { "JOB-\(job.id.suffix(4).uppercased())" }

    /// The job's name in a sheet's title or second line: its problem, else its street.
    private func menuTitle(_ job: JobRecord) -> String { job.title.isEmpty ? displayTitle(job) : job.title }

    /// Paper 21K: "AC not cooling · JOB-2214". Paper F8 (on the visit): "JOB-2214 · Danielle Marlowe".
    private func menuSubtitle(_ job: JobRecord) -> String {
        guard inField(job) else { return "\(menuTitle(job)) \u{00B7} \(jobNumber(job))" }
        let customer = store.customerName(job.customerId)
        return customer == "Customer" ? jobNumber(job) : "\(jobNumber(job)) \u{00B7} \(customer)"
    }

    /// Paper F8's brand card. The app has one job screen, so it opens Overview at the job's own
    /// details (the address, customer, money and activity under the field cards).
    private func fullDetailsLead(_ job: JobRecord) -> ThorbisMenuItem? {
        guard inField(job) else { return nil }
        return ThorbisMenuItem("Full job details", icon: "doc.text", subtitle: "Overview, money and activity") {
            withMotion(.snappy) { fieldModeOpen = false; selectedTab = "Overview" }
        }
    }

    /// Opens Overview (when another section shows) and scrolls it to one of its sections.
    private func showOnOverview(_ target: String) {
        detailsScrollTarget = target
        guard shownJobSection != "Overview" else { detailsScroll += 1; return }
        selectJobSection("Overview")
        // Each section has a scroll view of its own; scroll once Overview's has appeared.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            detailsScroll += 1
        }
    }

    /// The server allows cancelling and this person may: the same test Wrap up's Cancel job uses.
    private func canCancel(_ job: JobRecord) -> Bool {
        !session.isOffline && job.status != "completed" && outbox.pendingStatus(for: job.id) == nil
            && session.can("job.cancel", feature: "jobs") && job.allowedTransitions?.contains("canceled") == true
    }

    /// Paper 21K / 21T "Cancel job": Wrap up owns the guarded cancel, so the row opens it on its confirm.
    private func cancelMenuItem(_ job: JobRecord, icon: String) -> ThorbisMenuItem? {
        guard canCancel(job) else { return nil }
        return ThorbisMenuItem("Cancel job", icon: icon, isDisabled: busy, role: .destructive) {
            wrapUpCancels = true
            showWrapUp = true
        }
    }

    /// Everything in •••. Paper 21K draws eight rows: Time and profit, Save customer to contacts,
    /// At this address, Measure with camera, Call the office and Text the office in one card, then
    /// Pause job and Cancel job in a second, each with Paper's own glyph. Every other action lives
    /// at its door on the page (`jobDoors` below lists them). Paper F8 (on the visit) keeps its own
    /// menu: who to reach and "Can't finish — pause this job" first, everything else under it.
    private func moreMenuItems(_ job: JobRecord) -> [ThorbisMenuItem] {
        if inField(job) { return fieldMenuItems(job) }
        var items: [ThorbisMenuItem] = []
        var pause: ThorbisMenuItem?
        var wrapUp: ThorbisMenuItem?
        var deposit: ThorbisMenuItem?
        for action in menuGroups(job).flatMap({ $0 }) {
            if action == .transition("paused") {
                pause = menuActionItem(action, job: job)
            } else if action == .wrapUp {
                wrapUp = menuActionItem(action, job: job)
            } else if action == .deposit, !session.can("invoice.view", feature: "invoicing") {
                // Money's invoices card (the deposit's door) is locked without invoice.view.
                deposit = menuActionItem(action, job: job)
            }
        }
        // Paper 21K's first card, in its order, wearing its glyphs.
        let glyphs: [String: PaperGlyph] = [
            "Time and profit": .moreTime, "Save customer to contacts": .morePerson, "At this address": .moreEnvelope,
            "Measure with camera": .moreCamera, "Call the office": .morePhone, "Text the office": .moreBubble,
        ]
        for var item in deviceMenuItems(job) + reachMenuItems(job) {
            item.glyph = glyphs[item.title]
            items.append(item)
        }
        // Beyond Paper 21K, kept because Paper gives them no other door on Job details:
        // "Add to job" opens Paper 22 (its sheet has no drawn entry), and Wrap up's closeout
        // checklist when the bar at the bottom is not carrying it (Paper's home for it).
        let adds = addRows(job)
        if !(adds.billing.isEmpty && adds.onTheJob.isEmpty) {
            items.append(ThorbisMenuItem("Add to job", icon: "plus") { showAdd = true })
        }
        if let wrapUp { items.append(wrapUp) }
        if let deposit { items.append(deposit) }
        var stops: [ThorbisMenuItem] = []
        if var pause {
            pause.glyph = .morePause
            stops.append(pause)
        }
        if var cancel = cancelMenuItem(job, icon: "xmark.circle") {
            cancel.glyph = .moreCancel
            stops.append(cancel)
        }
        if !stops.isEmpty {
            stops[0].startsGroup = true
            items.append(contentsOf: stops)
        }
        return items
    }

    /// Paper F8, the field job menu: unchanged by the 21K trim (its own artboard). Who to reach
    /// and the pause first, everything else under it, Cancel job last.
    private func fieldMenuItems(_ job: JobRecord) -> [ThorbisMenuItem] {
        var actions: [ThorbisMenuItem] = []
        var pause: ThorbisMenuItem?
        for action in menuGroups(job).flatMap({ $0 }) {
            if action == .transition("paused") {
                pause = menuActionItem(action, job: job)
            } else {
                actions.append(menuActionItem(action, job: job))
            }
        }
        actions.append(contentsOf: deviceMenuItems(job))
        let share = ThorbisMenuItem("Share job", icon: "square.and.arrow.up") { shareJob = sharedJobText(job) }
        if let favorite = favoriteMenuItem(job) { actions.append(favorite) }
        if let show = showEstimatesItem(job) { actions.append(show) }
        var items = reachMenuItems(job)
        if let pause { items.append(pause) }
        var rest = actions + [share]
        rest[0].startsGroup = true
        items.append(contentsOf: rest)
        if var last = cancelMenuItem(job, icon: "xmark.circle") {
            last.startsGroup = true
            items.append(last)
        }
        return items
    }

    /// The job's estimates, handed to the customer to choose from (the locked Customer view on its
    /// estimates). Its door is the Money tab's estimates card (`showEstimatesRow`); field mode's menu.
    private func showEstimatesItem(_ job: JobRecord) -> ThorbisMenuItem? {
        guard !jobEstimates.isEmpty, session.can("estimate.view", feature: "estimates") else { return nil }
        return ThorbisMenuItem("Show estimates", icon: "iphone", subtitle: "Hand the estimates to the customer",
                               isDisabled: !canOpenCustomerView) { openCustomerView(.estimates) }
    }

    /// The header's Share circle (Paper 21): Share job, then what goes out to the customer or off
    /// the job (Customer view, Email customer, Add to Calendar, Copy job ID) and the favorite star.
    /// Each row is the action More carried, with the same permission and state gates.
    private func shareMenuItems(_ job: JobRecord) -> [ThorbisMenuItem] {
        var items = [ThorbisMenuItem("Share job", icon: "square.and.arrow.up") { shareJob = sharedJobText(job) }]
        let actions = menuGroups(job).flatMap { $0 }
        for action in [JobMenuAction.customerView, .email, .addToCalendar, .copyID] where actions.contains(action) {
            items.append(menuActionItem(action, job: job))
        }
        if let favorite = favoriteMenuItem(job) { items.append(favorite) }
        return items
    }

    /// The header's clock chip: when the visit is (Paper 21), and the moves that change or explain
    /// it: Schedule or Reschedule, Running late, Can't start, each with More's old gates.
    private func whenMenuItems(_ job: JobRecord) -> [ThorbisMenuItem] {
        let actions = menuGroups(job).flatMap { $0 }
        return [JobMenuAction.schedule, .runningLate, .cantStart].filter(actions.contains).map { menuActionItem($0, job: job) }
    }

    /// The header's person chip opens Assign (Paper 21's assignee chip), for whoever may assign.
    private func canAssignHere(_ job: JobRecord) -> Bool {
        menuGroups(job).contains { $0.contains(.assign) }
    }

    /// Paper 22's rows, each one only when this person can do it here. "Purchase order" is left
    /// out: an order isn't tied to a job in the app yet.
    private func addRows(_ job: JobRecord) -> (billing: [JobAddRow], onTheJob: [JobAddRow]) {
        var billing: [JobAddRow] = []
        var onTheJob: [JobAddRow] = []
        if session.can("estimate.create", feature: "estimates"), scope(for: job) != nil {
            billing.append(JobAddRow(id: "estimate", glyph: .addEstimate, title: "Estimate",
                                     subtitle: "Propose new work for approval") { buildEstimate() })
        }
        if menuGroups(job).contains(where: { $0.contains(.billWithoutEstimate) }) {
            billing.append(JobAddRow(id: "invoice", glyph: .addInvoice, title: "Invoice",
                                     subtitle: "Bill for completed work") { run(.createInvoice) })
        }
        if session.can("job.edit", feature: "jobs") {
            onTheJob.append(JobAddRow(id: "photo", glyph: .jobCamera, title: "Photo or video",
                                      subtitle: "Capture job-site media") {
                if UIImagePickerController.isSourceTypeAvailable(.camera) { openCapture(.camera(stage: nil)) } else { openPhotos() }
            })
        }
        if session.can("job.note", feature: "jobs") {
            onTheJob.append(JobAddRow(id: "note", glyph: .addNote, title: "Note",
                                      subtitle: "Log an update for the office") { openNoteTool() })
        }
        if session.can("customer.view", feature: "core_crm"), session.can("customer.edit", feature: "core_crm"),
           customerContext(job) != nil, customerContext(job) == contactsContext {
            onTheJob.append(JobAddRow(id: "contact", glyph: .addContact, title: "Contact",
                                      subtitle: "Add another person on this job") { showAddContact = true })
        }
        return (billing, onTheJob)
    }

    private func sharedJobText(_ job: JobRecord) -> SharedText {
        SharedText(JobShareText.text(title: job.title, customer: store.customerName(job.customerId), scheduledFor: job.scheduledFor))
    }

    /// "Add to favorites" / "Remove from favorites", for whoever may keep this job as a favorite.
    private func favoriteMenuItem(_ job: JobRecord) -> ThorbisMenuItem? {
        guard session.can("job.view", feature: "jobs"),
              let context = ScopedRecordFavorites.currentScope(session: session, api: api),
              context.organizationID.caseInsensitiveCompare(job.organizationId) == .orderedSame else { return nil }
        let favorites = ScopedRecordFavorites.shared
        let selected = favorites.isBound(to: context) && favorites.entries.contains { $0.kind == .job && $0.id == job.id.lowercased() }
        return ThorbisMenuItem(selected ? "Remove from favorites" : "Add to favorites", icon: selected ? "star.fill" : "star") {
            favorites.bind(context)
            favorites.toggle(.job, id: job.id)
        }
    }

    /// Paper 21K, in its order: "Save customer to contacts", "At this address" and "Measure with
    /// camera", when the loaded customer and the device allow them.
    private func deviceMenuItems(_ job: JobRecord) -> [ThorbisMenuItem] {
        var items: [ThorbisMenuItem] = []
        // Paper 21K leads with "Time and profit" (21J): the visit's drive and on-site time.
        if !inField(job) {
            items.append(ThorbisMenuItem("Time and profit", icon: "calendar") { showTime = true })
        }
        if customerContext(job) == contactsContext, contactsContext != nil,
           let record = customerRecord, record.id == job.customerId {
            items.append(ThorbisMenuItem("Save customer to contacts", icon: "person") {
                handoff = .contact(ContactCardDraft.make(customer: record))
            })
        }
        // On the visit, "Full job details" already opens there.
        if !inField(job) {
            // Paper 21K draws an envelope beside "At this address".
            items.append(ThorbisMenuItem("At this address", icon: "envelope") { showAtAddress = true })
        }
        if session.can("job.edit", feature: "jobs"), SiteMeasure.isSupported {
            items.append(ThorbisMenuItem("Measure with camera", icon: "camera") { openCapture(.measure) })
        }
        return items
    }

    private func menuActionItem(_ action: JobMenuAction, job: JobRecord) -> ThorbisMenuItem {
        switch action {
        case .transition(let target):
            if target == "paused", isOnSite {
                // Paper F8: on site the stop says what it is, its mark in the warning tone.
                // Paper F8: the row is amber, mark and words.
                return ThorbisMenuItem("Can't finish \u{2014} pause this job", icon: "pause.circle", tint: Theme.warning,
                                       isDisabled: busy, tintsTitle: true) { runTransition(target) }
            }
            // Paper 21K: Pause job shares the second card with Cancel job (`moreMenuItems`).
            return ThorbisMenuItem(transitionTitle(target), icon: transitionSymbol(target), isDisabled: busy,
                                   role: ["canceled", "cancelled"].contains(target) ? .destructive : nil) { runTransition(target) }
        case .schedule:
            return ThorbisMenuItem(job.scheduledFor == nil ? "Schedule" : "Reschedule", icon: "calendar") { showSchedule = true }
        case .addToCalendar:
            return ThorbisMenuItem("Add to Calendar", icon: "calendar.badge.plus") {
                handoff = JobCalendarDraft.make(job: job, customerName: store.customers.first { $0.id == job.customerId }?.name, locations: customerLocations).map(DeviceHandoff.calendar)
            }
        case .email:
            return ThorbisMenuItem("Email customer", icon: "envelope") { if let mail = customerEmail(job) { inboxEmail(mail, context: "job:\(job.id)") } }
        case .assign:
            return ThorbisMenuItem(job.assignedToUserId == nil ? "Assign technician" : "Reassign technician", icon: "person.crop.circle.badge.plus") { showAssign = true }
        case .billWithoutEstimate:
            return ThorbisMenuItem("Create invoice", icon: "doc.plaintext", subtitle: "Bill without an estimate", isDisabled: creatingInvoice) { run(.createInvoice) }
        case .deposit:
            return ThorbisMenuItem("Request a deposit", icon: "banknote", subtitle: "Bill part up front") { showDeposit = true }
        case .wrapUp:
            return ThorbisMenuItem("Wrap up", icon: "checkmark.seal", subtitle: "Closeout checklist") { showWrapUp = true }
        case .followUps:
            return ThorbisMenuItem("Follow-ups", icon: "list.bullet") { showFollowUps = true }
        case .customerView:
            return ThorbisMenuItem("Customer view", icon: "person.crop.rectangle", isDisabled: !canOpenCustomerView) { openCustomerView(.home) }
        case .copyID:
            return ThorbisMenuItem("Copy job ID", icon: "doc.on.doc") { UIPasteboard.general.string = job.id }
        case .runningLate:
            return ThorbisMenuItem("Running late", icon: "clock.badge.exclamationmark", subtitle: "Text the customer a new time") { showRunningLate = true }
        case .cantStart:
            return ThorbisMenuItem("Can't start", icon: "hand.raised", subtitle: "Tell the office why") { showCantStart = true }
        }
    }

    /// The job's name: its street when the job records a site, else its title (BYR-1593).
    private func street(_ job: JobRecord) -> String? {
        JobPropertyHistory.street(job: job, locations: customerLocations)
    }

    private func displayTitle(_ job: JobRecord) -> String { street(job) ?? job.title }

    /// Which access facts the job's own site has on record, for the Lock Screen card. Labels
    /// only ("Gate code · Dog on site"); the codes stay in the app.
    private func liveActivityAccess(_ job: JobRecord) -> String? {
        guard job.locationId != nil else { return nil }
        return JobPropertyHistory.accessPlace(job: job, locations: customerLocations).flatMap(JobServiceAddressesSection.accessSummary)
    }

    /// The status the screen shows: a queued offline step counts.
    private func shownStatus(_ job: JobRecord) -> String { outbox.pendingStatus(for: job.id) ?? job.status }

    /// OnSite.dc.html: once arrived (or working), the job screen is the technician's toolkit.
    private var isOnSite: Bool {
        guard let job else { return false }
        return ["arrived", "in_progress"].contains(shownStatus(job))
    }

    @ViewBuilder
    private func header(_ job: JobRecord, compact: Bool = false) -> some View {
        if compact { compactHeader(job) } else { fullHeader(job) }
    }

    /// Money and Activity only need to say which job this is: the street (or title) and its status.
    private func compactHeader(_ job: JobRecord) -> some View {
        // At accessibility sizes the status goes under the street so the street never breaks mid-word.
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                                  : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            Text(displayTitle(job))
                .font(Theme.font(20, weight: .medium))
                .tracking(-0.3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            statusWord(job)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .accessibilityElement(children: .contain)
    }

    /// Status as its glyph and word on a tinted chip; changing it lives on Overview and in •••.
    private func statusWord(_ job: JobRecord) -> some View {
        let queued = outbox.pendingStatus(for: job.id)
        return TimelineView(.everyMinute) { context in
            statusChipLabel(job, queued: queued, now: context.date, showsMenu: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Job status, \((queued ?? job.status).statusLabel)")
    }

    /// Paper 21L Job details: the problem as the 34 Bold title, "JOB-2214 · customer · street" under
    /// it in 15 muted, then the property chips (status, which opens the status popover; when; who;
    /// the estimate). The map strip moved onto Overview and Call, Text and Directions into the bar.
    /// Rescheduling and assigning live in the ••• menu.
    private func fullHeader(_ job: JobRecord, showsSteps: Bool = true) -> some View {
        // Paper F2 to F4: on the visit the bar carries the title (`toolbarActions`), so the page
        // starts at the steps.
        let barTitle = showsBarTitle(job)
        let subtitle = subtitleParts(job)
        return VStack(alignment: .leading, spacing: 0) {
            // Paper F2 to F4: out on the visit, the five steps lead the screen (Overview only;
            // Paper 23, 24 and 21B draw Money and Activity without them).
            if showsSteps, let step = fieldStep(job) {
                JobFieldSteps(current: step, allDone: step == 4)
                    .padding(.horizontal, 16 - Theme.gutter)
                    .padding(.bottom, barTitle ? 0 : 16)
            }
            if !barTitle {
                // Paper 21: the job's number (and its place's name) is a 13 Semibold eyebrow over
                // the 34 Bold title; who it is for and where sit under it at 15.
                Text(headerLines(eyebrowParts(job).joined(separator: " \u{00B7} ")))
                    .font(Theme.font(13, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(eyebrowParts(job).joined(separator: ", "))
                    .accessibilityIdentifier("job-number")
                    // A long press copies the full ID (also in •••).
                    .contextMenu { Button("Copy job ID", systemImage: "doc.on.doc") { UIPasteboard.general.string = job.id } }
                Text(job.title.isEmpty ? displayTitle(job) : job.title)
                    .font(Theme.font(34, weight: .bold))
                    .tracking(-0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("job-title")
                if !subtitle.isEmpty {
                    Text(headerLines(subtitle.joined(separator: " \u{00B7} ")))
                        .font(Theme.font(15))
                        .foregroundStyle(Theme.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                        .accessibilityLabel(subtitle.joined(separator: ", "))
                        .accessibilityIdentifier("job-subtitle")
                }
            }
            // Paper F2 to F5: field mode has no chips; the steps say where the visit is, and the
            // status sheet is on Job details.
            if !barTitle {
            FlowRow(spacing: 8, lineSpacing: 8) {
                statusControl(job)
                whenControl(job)
                assigneeControl(job)
                if let estimate = estimateChipText { JobHeaderChip(text: estimate) { EmptyView() } }
            }
            // Paper: the chips sit 14 under the header's words.
            .padding(.top, 14)
            // Paper: the chips start 16 in, with the cards; the title keeps the 20 gutter.
            .padding(.horizontal, 16 - Theme.gutter)
            }
            // What to know before touching anything leads Overview's cards (`fieldLead`).
        }
        .padding(.horizontal, Theme.gutter)
        // Paper F2: the steps sit 16 under the bar's title; Paper 21: the eyebrow 14 under the bar.
        .padding(.top, barTitle ? 8 : 14)
        // Paper 21: the sections sit 16 under the chips. Field mode: the cards 14 under the steps.
        .padding(.bottom, 14)
    }

    /// Paper 21's eyebrow: "JOB-2214 · Marlowe residence" (the job's number, then its place's name
    /// when the place on file has one of its own).
    private func eyebrowParts(_ job: JobRecord) -> [String] {
        var parts = [jobNumber(job)]
        if let locationID = job.locationId, let place = customerLocations.first(where: { $0.id == locationID }) {
            let label = place.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if !label.isEmpty, label != street(job), label != place.address { parts.append(label) }
        }
        return parts
    }

    /// "Danielle Marlowe · 412 Birchwood Ln · Member 15% off".
    private func subtitleParts(_ job: JobRecord) -> [String] {
        var parts: [String] = []
        let customer = store.customerName(job.customerId)
        if customer != "Customer" { parts.append(customer) }
        if let street = street(job), street != job.title { parts.append(street) }
        return parts
    }

    /// The clock chip opens the visit's time moves (Reschedule, Running late, Can't start) as an
    /// anchored menu, like the status chip beside it; a plain chip when there is none to make.
    @ViewBuilder private func whenControl(_ job: JobRecord) -> some View {
        let items = whenMenuItems(job)
        if items.isEmpty {
            whenChip(job)
        } else {
            // A finished job with no time still keeps its door (it reads "Not scheduled").
            let text = whenText(job) ?? "Not scheduled"
            ThorbisMenu(items: items, title: "Visit time", accessibilityLabel: "Visit time, \(text). Change time") {
                JobHeaderChip(text: text) { PaperIcon(.jobClock, size: 14, color: Theme.muted) }
            }
            .accessibilityIdentifier("job-when")
        }
    }

    /// The person chip opens Assign (Paper 53A) for whoever may assign; a plain chip otherwise.
    @ViewBuilder private func assigneeControl(_ job: JobRecord) -> some View {
        if canAssignHere(job) {
            let assignee = assignedDisplayName(for: job).flatMap { $0 == "Assigned" ? nil : $0 }
            Button { showAssign = true } label: { assigneeChip(job) }
                .buttonStyle(PressStyle())
                .accessibilityLabel(job.assignedToUserId == nil ? "Assign technician" : "Reassign technician")
                .accessibilityValue(assignee ?? "Unassigned")
                .accessibilityIdentifier("job-assignee")
        } else {
            assigneeChip(job)
        }
    }

    /// Paper 21's clock chip: "Today · 10:30 AM", "Arrived 9:12 AM", or when it isn't booked yet.
    @ViewBuilder private func whenChip(_ job: JobRecord) -> some View {
        if let text = whenText(job) {
            JobHeaderChip(text: text) {
                PaperIcon(.jobClock, size: 14, color: Theme.muted)
            }
        }
    }

    private func whenText(_ job: JobRecord) -> String? {
        if let scheduled = JobFiltering.date(job.scheduledFor) {
            return Calendar.current.isDateInToday(scheduled) ? "Today \u{00B7} \(scheduled.tradeTime)" : scheduled.visitLabel()
        }
        return job.status != "completed" && job.status != "canceled" ? "Not scheduled" : nil
    }

    /// Paper 21's person chip: the assignee's initials on the brand surface, then the short name.
    private func assigneeChip(_ job: JobRecord) -> some View {
        let assignee = assignedDisplayName(for: job)
        let named = assignee.flatMap { $0 == "Assigned" ? nil : $0 }
        let text = named.map { shortName($0) } ?? assignee ?? "Unassigned"
        return JobHeaderChip(text: text, leadingInset: named == nil ? 12 : 6) {
            if let named {
                Text(initials(named))
                    .font(Theme.font(11, weight: .semibold)).tracking(-0.22)
                    .foregroundStyle(Theme.brandText)
                    .frame(width: 22, height: 22)
                    .background(Theme.brandSurface, in: Circle())
                    .dynamicTypeSize(...DynamicTypeSize.large)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "person").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.subtle)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Paper 21L's "$480.00 est.": only when the job has one estimate with one set of lines, so the
    /// chip never sums papers the customer chooses between.
    private var estimateChipText: String? {
        guard session.can("estimate.view", feature: "estimates"), estimatesLoaded, !estimatesFailed,
              jobEstimates.count == 1, let estimate = jobEstimates.first, (estimate.options ?? []).isEmpty,
              let total = paperLinesTotal(estimate.lines) else { return nil }
        return "\(jobShortMoney(total, currency: estimate.lines.first?.unitPrice.currency ?? "USD")) est."
    }

    /// The note circle and, on site, the office's call circle, as 40pt card circles beside the chips.
    @ViewBuilder private var captureCircles: some View {
        if session.can("job.note", feature: "jobs") { noteCircle }
        if onSiteWrapsUp { callCircle }
    }

    /// The job's own place, when its service location is on file with a position.
    private func jobCoordinates(_ job: JobRecord) -> FieldCoordinates? {
        guard let locationID = job.locationId else { return nil }
        return customerLocations.first { $0.id == locationID }?.coordinates
    }

    /// Where this job sits, for the bar: "Today · Stop 3 of 6" on the person's day, else when it is.
    private func contextLine(_ job: JobRecord) -> String? {
        guard let date = JobFiltering.date(job.scheduledFor) else { return nil }
        guard Calendar.current.isDateInToday(date) else { return date.visitLabel() }
        let scope = ScheduleScope.initial(schedulesOwnDay: WorkRole(session).schedulesOwnDay, actorID: session.user?.id)
        let visits = TodayNumbers.visits(store.jobs, assignee: scope.assignee(session.user?.id, range: .today))
        let stops = TodayStopOrder.ordered(visits) { outbox.pendingStatus(for: $0.id) ?? $0.status }
        guard let at = stops.firstIndex(where: { $0.id == job.id }) else { return "Today" }
        return "Today · Stop \(at + 1) of \(stops.count)"
    }

    /// At accessibility sizes each " · " part gets its own line, so a "·" never ends a wrapped line.
    private func headerLines(_ text: String) -> String {
        typeSize.isAccessibilitySize ? text.replacingOccurrences(of: " \u{00B7} ", with: "\n") : text
    }

    /// The access facts for the job's place, from the loaded locations or, offline, the copy saved on this phone.
    private func accessBanner(_ job: JobRecord) -> JobAccessBanner? {
        if let place = JobPropertyHistory.accessPlace(job: job, locations: customerLocations) {
            let facts = JobPropertyHistory.facts(place)
            guard !facts.isEmpty else { return nil }
            return JobAccessBanner(facts: facts, caveat: job.locationId == nil ? "From the customer's only address on file, \(place.label.isEmpty ? place.address : place.label)." : nil)
        }
        guard customerLocations.isEmpty, let saved = JobDetailCache.history(job.id)?.history,
              saved.jobId == job.id, saved.organizationId == job.organizationId, !saved.facts.isEmpty else { return nil }
        return JobAccessBanner(facts: saved.facts, caveat: saved.scope == .customer ? "From the customer's only address on file." : nil)
    }

    private var customerAuthorityToken: String {
        let allowed = session.can("customer.view", feature: "core_crm")
        return "\(session.generation.uuidString)|\(session.authorityRevision.uuidString)|\(session.policyVersion.map(String.init) ?? "unavailable")|\(allowed)"
    }

    /// The job's customer as a navigable record: from the list when it's there, else from the
    /// account this screen read for the job, so a job opened from a link still reaches its customer.
    private func linkedCustomer(_ job: JobRecord) -> Customer? {
        guard session.can("customer.view", feature: "core_crm") else { return nil }
        if let listed = store.customers.first(where: { $0.id == job.customerId }) { return listed }
        guard customerContext(job) == contactsContext, let record = customerRecord,
              record.id == job.customerId, record.organizationId == job.organizationId else { return nil }
        return Customer(id: record.id, name: record.name, archived: record.archived, createdAt: record.createdAt)
    }

    private func customerContext(_ job: JobRecord) -> String? {
        guard let organizationID = session.activeOrganization?.id, let policyVersion = session.policyVersion,
              organizationID == job.organizationId,
              session.can("customer.view", feature: "core_crm") else { return nil }
        return JobLocationPolicy.context(generation: session.generation, authorityRevision: session.authorityRevision, policyVersion: policyVersion, canView: true,
                                         organizationID: organizationID, customerID: job.customerId)
    }

    private var customerLocations: [ServiceLocationRecord] {
        guard let job, let context = customerContext(job), locationsContext == context else { return [] }
        return JobLocationPolicy.accountLocations(locations, customerID: job.customerId, organizationID: job.organizationId)
    }

    /// Paper 21's bar: Call, Text and Directions as card circles, 8 apart, after the commit.
    /// Directions always require choosing an account location; no job site is inferred.
    private func reachCircles(_ job: JobRecord) -> some View {
        let phone = customerContext(job) == contactsContext ? customerPhone : nil
        let reach = JobReach(phone: phone, email: nil)
        return HStack(spacing: 8) {
            Button { if let call = reach.call { openURL(call) } } label: {
                barCircle("phone", enabled: reach.call != nil)
            }
            .buttonStyle(PressStyle())
            .disabled(reach.call == nil)
            .accessibilityLabel("Call \(store.customerName(job.customerId))")
            .accessibilityIdentifier("job-call")
            Button { if let text = reach.text { inboxText(text, name: store.customerName(job.customerId), openURL: openURL) } } label: {
                barCircle("message", enabled: reach.text != nil)
            }
            .buttonStyle(PressStyle())
            .disabled(reach.text == nil)
            .accessibilityLabel("Text \(store.customerName(job.customerId))")
            .accessibilityIdentifier("job-text")
            directionsCircle
        }
    }

    @ViewBuilder
    private var directionsCircle: some View {
        if customerLocations.count == 1, let only = customerLocations.first,
           let url = JobLocationPolicy.directions(for: only.id, in: customerLocations) {
            Button { openURL(url) } label: { barCircle("location") }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Directions")
                .accessibilityHint("Opens driving directions in Maps")
                .accessibilityIdentifier("job-directions")
        } else if !customerLocations.isEmpty {
            ThorbisMenu(items: customerLocations.map { place in
                ThorbisMenuItem(place.label, icon: place.kind == "billing" ? "creditcard" : "mappin.and.ellipse",
                                subtitle: "\(place.kind == "billing" ? "Billing" : "Service") · \(place.address)") {
                    if let url = JobLocationPolicy.directions(for: place.id, in: customerLocations) { openURL(url) }
                }
            }, title: "Directions to") {
                barCircle("location")
            }
            .accessibilityLabel("Directions")
            .accessibilityHint("Choose a customer location")
            .accessibilityIdentifier("job-directions")
        } else {
            barCircle("location", enabled: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Directions, no address on file")
                .accessibilityIdentifier("job-directions")
        }
    }

    /// Screenshot-only (`--paper-preview-screen job-more`): Paper 21K opens over the job.
    private static var previewOpensMoreMenu: Bool {
        #if DEBUG
        PaperPreview.enabled && PaperPreview.screen == "job-more"
        #else
        false
        #endif
    }

    /// Screenshot-only (`--paper-preview-status-menu`): the status popover opens on its chip.
    private static var previewOpensStatusMenu: Bool {
        #if DEBUG
        PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-status-menu")
        #else
        false
        #endif
    }

    /// The status chip (glyph and word) opens the status menu when there is a move to make.
    @ViewBuilder
    private func statusControl(_ job: JobRecord) -> some View {
        let transitions = availableTransitions(job)
        if transitions.isEmpty {
            statusChip(job, showsMenu: false)
        } else {
            // Glyph-led (phase 4): each move shows the status it leads to; the title says where the
            // job is now. Only the server's allowed moves are listed.
            // v2: a popover from the chip. The current status leads, checked; then the server's
            // allowed moves, each led by the mark of where it takes the job.
            // v2: every move the server allows, grouped by space: forward moves under the current
            // status, then the moves that stop or step back (Pause job, Move back to scheduled).
            // Paper 21T: the first card is the job's steps by name ("Driving", "Arrived", "Working"),
            // the current one with what is known about it and when it began, the next one marked
            // "Next". The second card holds Pause job, the step back and Cancel job.
            JobStatusMenu(groups: statusMenuGroups(job, transitions: transitions),
                          title: "Job status", accessibilityLabel: "Job status, \(shownStatus(job).statusLabel). Change status",
                          opensOnAppear: Self.previewOpensStatusMenu,
                          subtitle: "\(jobNumber(job)) \u{00B7} \(menuTitle(job))",
                          doneSteps: statusDoneSteps(job)) {
                statusChip(job, showsMenu: true)
            }
        }
    }

    /// Paper 21T's finished steps: each visit step before the current one, with the time the job's
    /// own record holds for it. A step with no time on record is left out, never guessed; a step
    /// still waiting to sync has no finished steps to show yet.
    private func statusDoneSteps(_ job: JobRecord) -> [JobStatusDoneStep] {
        guard outbox.pendingStatus(for: job.id) == nil else { return [] }
        let order = ["dispatched", "en_route", "arrived", "in_progress"]
        guard let at = order.firstIndex(of: job.status) else { return [] }
        var done: [JobStatusDoneStep] = []
        for status in order.prefix(at) {
            let stamp: String?
            switch status {
            case "dispatched": stamp = job.dispatchedAt
            case "en_route": stamp = job.enRouteAt
            case "arrived": stamp = job.arrivedAt
            default: stamp = nil
            }
            guard let date = JobFiltering.date(stamp) else { continue }
            done.append(JobStatusDoneStep(id: status, title: statusStepTitle(status),
                                          time: date.formatted(date: .omitted, time: .shortened)))
        }
        return done
    }

    /// Paper 21T's two cards: the steps (where the job is, then each move forward), and the moves
    /// that stop or step back (Pause job, Move back to scheduled, Cancel job).
    private func statusMenuGroups(_ job: JobRecord, transitions: [String]) -> [[ThorbisMenuItem]] {
        let current = shownStatus(job)
        let backward: Set<String> = ["paused", "scheduled"]
        let forward = transitions.filter { !backward.contains($0) }
        var steps: [ThorbisMenuItem] = [
            ThorbisMenuItem(statusStepTitle(current), subtitle: statusStepNote(job, status: current),
                            status: StatusTone(jobStatus: current, hasTime: job.scheduledFor != nil),
                            isSelected: true, detail: statusStepTime(job, status: current), action: {})
        ]
        for target in forward {
            let detail: String? = target == forward.first ? "Next" : nil
            steps.append(ThorbisMenuItem(statusStepTitle(target), status: StatusTone(jobStatus: target), detail: detail,
                                         action: { runTransition(target) }))
        }
        var stops: [ThorbisMenuItem] = []
        for target in transitions where backward.contains(target) {
            if target == "paused" {
                stops.append(ThorbisMenuItem("Pause job", icon: "pause", subtitle: "Waiting on a part or the customer",
                                             action: { runTransition(target) }))
            } else {
                stops.append(ThorbisMenuItem(transitionTitle(target), status: StatusTone(jobStatus: target),
                                             action: { runTransition(target) }))
            }
        }
        if let cancel = cancelMenuItem(job, icon: "nosign") { stops.append(cancel) }
        return [steps, stops]
    }

    /// Paper 21T names a step by where the job is, not by the tap that gets it there.
    private func statusStepTitle(_ status: String) -> String {
        switch status {
        case "en_route": return "Driving"
        case "arrived": return "Arrived"
        case "in_progress": return "Working"
        default: return status.statusLabel
        }
    }

    /// Paper 21T "Current · 0:42 on site": how long on site, once the arrival is on the server.
    private func statusStepNote(_ job: JobRecord, status: String) -> String? {
        guard outbox.pendingStatus(for: job.id) == nil, ["arrived", "in_progress"].contains(status),
              let arrived = JobFiltering.date(job.arrivedAt) else { return nil }
        return JobOnSiteClock.line(arrived: arrived, now: Date())
    }

    /// Paper 21T's trailing time: when the current step began, from the job's own record.
    private func statusStepTime(_ job: JobRecord, status: String) -> String? {
        guard outbox.pendingStatus(for: job.id) == nil else { return nil }
        let stamp: String?
        switch status {
        case "dispatched": stamp = job.dispatchedAt
        case "en_route": stamp = job.enRouteAt
        case "arrived": stamp = job.arrivedAt
        case "in_progress": stamp = job.startedAt
        case "paused": stamp = job.pausedAt
        default: stamp = nil
        }
        guard let date = JobFiltering.date(stamp) else { return nil }
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// "On site 42 min" while there, live each minute from the arrival tap; otherwise the status word.
    private func statusChip(_ job: JobRecord, showsMenu: Bool) -> some View {
        let queued = outbox.pendingStatus(for: job.id)
        return TimelineView(.everyMinute) { context in
            statusChipLabel(job, queued: queued, now: context.date, showsMenu: showsMenu)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Job status, \(statusWordText(job, queued: queued, now: .now))")
        .accessibilityIdentifier("job-status")
    }

    /// The chip itself, never a button: inside the status menu the menu is the button.
    private func statusChipLabel(_ job: JobRecord, queued: String?, now: Date, showsMenu: Bool) -> some View {
        let tone = StatusTone(jobStatus: queued ?? job.status, hasTime: JobFiltering.date(job.scheduledFor) != nil || job.status != "scheduled")
        // Paper 21: the status chip is tinted with its status (the word in the status's text colour)
        // and leads with the status mark; a chevron when it opens the status popover.
        return JobHeaderChip(text: statusWordText(job, queued: queued, now: now), fill: tone.surface,
                             textColor: tone.text, weight: .semibold, showsChevron: showsMenu,
                             leadingInset: 12, trailingInset: showsMenu ? 10 : 12) {
            StatusGlyph(tone: tone, label: "", pending: queued != nil, size: 14)
                .accessibilityHidden(true)
        }
    }

    private func statusWordText(_ job: JobRecord, queued: String?, now: Date) -> String {
        if let queued {
            return ["arrived", "in_progress"].contains(queued) ? "On site · waiting to sync" : "\(queued.statusLabel) · waiting to sync"
        }
        if let step = JobFieldSteps.step(for: job.status) { return JobFieldSteps.titles[step] }
        return job.status.statusLabel
    }

    private func assignedDisplayName(for job: JobRecord) -> String? {
        guard let assignedID = job.assignedToUserId else { return nil }
        guard assignedID == session.user?.id, let name = session.user?.name, !name.isEmpty else { return "Assigned" }
        return name
    }

    private func shortName(_ name: String) -> String {
        let parts = name.split(whereSeparator: \.isWhitespace)
        guard let first = parts.first else { return name }
        guard let last = parts.dropFirst().last else { return String(first) }
        return "\(first) \(last.prefix(1))."
    }

    private var invoiceBalanceCents: Int? {
        guard let job, let expectedScope = scope(for: job), let read = invoiceRead,
              read.scope == expectedScope, read.isComplete, read.unavailableIDs.isEmpty,
              documentGeneration == session.generation,
              overviewInvoicesAuthority?.isCurrent(api: api, session: session) == true,
              read.records.allSatisfy({ expectedScope.contains($0) && read.freshIDs.contains($0.id) }) else { return nil }
        let issued = read.records.filter { $0.status == "issued" }
        guard !issued.isEmpty, issued.allSatisfy({ $0.currency == "USD" && $0.amountPaid >= 0 }) else { return nil }
        var balanceTotal = 0
        for invoice in issued {
            var invoiceTotal = 0
            for line in invoice.lines {
                guard line.quantity >= 0, line.unitPrice.amount >= 0,
                      line.unitPrice.currency == invoice.currency else { return nil }
                let (lineTotal, lineOverflow) = line.quantity.multipliedReportingOverflow(by: line.unitPrice.amount)
                let (nextTotal, sumOverflow) = invoiceTotal.addingReportingOverflow(lineTotal)
                guard !lineOverflow, !sumOverflow else { return nil }
                invoiceTotal = nextTotal
            }
            let (due, dueOverflow) = invoiceTotal.subtractingReportingOverflow(invoice.amountPaid)
            guard !dueOverflow, due >= 0 else { return nil }
            let (nextBalance, balanceOverflow) = balanceTotal.addingReportingOverflow(due)
            guard !balanceOverflow else { return nil }
            balanceTotal = nextBalance
        }
        return balanceTotal
    }

    /// The words on each section: "On site" once arrived, what's owed on Money, how much on Activity.
    private func sectionLabel(_ tab: String, job: JobRecord) -> String {
        switch tab {
        // Paper 21, 23, 21B: the sections are their words alone (amounts and counts are spoken).
        case "Overview": return "Overview"
        case "Money": return "Money"
        case "Photos": return "Photos"
        default: return "Activity"
        }
    }

    private func spokenSectionLabel(_ tab: String, job: JobRecord) -> String {
        switch tab {
        case "Money":
            guard let balance = invoiceBalanceCents, balance > 0 else { return "Money" }
            return "Money, \(money(balance, currency: "USD"))\u{00A0}due"
        case "Activity":
            let count = activityCount(job)
            return count > 0 ? "Activity, \(count) \(count == 1 ? "entry" : "entries")" : "Activity"
        default: return sectionLabel(tab, job: job)
        }
    }

    /// Photos are Activity's own filter (Paper 21A), so the section shown is always the one chosen.
    private var shownJobSection: String { selectedTab }

    private func selectJobSection(_ section: String) {
        // Coming back to Activity from another section opens its timeline, not the photo grid the
        // camera left behind; the Photos chip is one tap away.
        if section == "Activity", selectedTab != "Activity", activityFilter == "Photos" {
            activityFilter = activityFilterBeforePhotos
        }
        withMotion(.snappy) { selectedTab = section }
    }

    /// Job sections as Linear text tabs; a menu at accessibility sizes.
    private func tabBar(_ job: JobRecord) -> some View {
        Group {
            if typeSize.isAccessibilitySize {
                ThorbisMenu(items: tabs.map { tab in
                    ThorbisMenuItem(sectionLabel(tab, job: job), isSelected: tab == shownJobSection) { selectJobSection(tab) }
                }, title: "Job sections", accessibilityLabel: "Job sections, \(spokenSectionLabel(shownJobSection, job: job))") {
                    HStack(spacing: 12) {
                        Text(sectionLabel(shownJobSection, job: job)).font(Theme.font(15, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Theme.foreground)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                }
                .padding(.horizontal, Theme.gutter)
                .accessibilityHint("Choose a job section")
                .accessibilityIdentifier("job-section-chooser")
            } else {
                JobSectionControl(options: tabs.map { ($0, sectionLabel($0, job: job), spokenSectionLabel($0, job: job)) },
                                  selection: Binding(get: { shownJobSection }, set: { selectJobSection($0) }))
                    // Paper: the segmented track runs 16 in from the screen's edges.
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    /// Paper 21, 21B: Overview and Activity share the job's bar (the next step, then the circles);
    /// Money's bar is the money's own next step.
    @ViewBuilder private var primaryAction: some View {
        overviewBar
    }

    /// On site with the work started, the bar is the wrap-up: a status step (Start work, Resume)
    /// still leads while there is one.
    private var onSiteWrapsUp: Bool {
        guard isOnSite, let step = nextStep else { return false }
        if case .transition = step { return false }
        return true
    }

    /// Paper 21's bar, floating on the canvas: the one brand commit for the next step, then the camera,
    /// Call, Text and Directions as card circles. At accessibility sizes the circles sit on their own
    /// row above the commit. The note circle sits with the header's chips.
    @ViewBuilder private var overviewBar: some View {
        if let job {
            let step = nextStep
            // Paper 21: the commit, then Call, Text and Directions. The camera is Activity's.
            let circles = reachCircles(job)
            // Paper F2 and F3 (driving, arrived): the bar is the moment's second action over one
            // full-width 60pt commit. Call, Text and Directions are the screen's own rows there
            // ("Call Danielle", "Open in Maps", the job menu), so the circles are left out.
            let fieldBar = inField(job) && ["dispatched", "en_route", "arrived"].contains(shownStatus(job)) && !typeSize.isAccessibilitySize
            // Paper F4 (working): the same bar, no circles. The camera is the Photo tile; Call and
            // Text are in the job menu, Directions on the Address row.
            let workingBar = inField(job) && shownStatus(job) == "in_progress" && !typeSize.isAccessibilitySize
            let paidBar = inField(job) && fieldStep(job) == 4
            VStack(spacing: 10) {
                // Paper F2 to F4: the moment's second action sits over the commit.
                if inField(job), !paidBar { fieldSecondary(job) }
                if paidBar {
                    fieldPaidCommit
                } else if workingBar {
                    if let step {
                        if onSiteWrapsUp { workingCommitButton } else { fieldCommitButton(step) }
                    }
                } else if fieldBar {
                    if let step { fieldCommitButton(step) }
                } else if typeSize.isAccessibilitySize {
                    circles.frame(maxWidth: .infinity, alignment: .leading)
                    if let step { commitButton(step) }
                } else {
                    // When the commit's words can't fit beside the circles, the circles take their own
                    // row above it rather than the pill breaking onto two lines.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            if let step { commitButton(step) } else { Spacer(minLength: 0) }
                            circles
                        }
                        VStack(spacing: 10) {
                            circles.frame(maxWidth: .infinity, alignment: .trailing)
                            if let step { commitButton(step) }
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
            // Paper: the bar floats on the canvas, which fades in behind it.
            .background(LinearGradient(stops: [.init(color: Theme.background.opacity(0), location: 0), .init(color: Theme.background, location: 0.34)],
                                       startPoint: .top, endPoint: .bottom).padding(.top, -18).ignoresSafeArea(edges: .bottom).allowsHitTesting(false))
        }
    }

    /// Paper F2 "Open in Maps" while driving and F3 "Can't start — tell dispatch" once arrived: a
    /// quiet pill over the commit. Each only where the app can do it (an address on file; a role
    /// that may edit the job).
    @ViewBuilder private func fieldSecondary(_ job: JobRecord) -> some View {
        let status = shownStatus(job)
        if status == "en_route" || status == "dispatched" {
            openInMaps
        } else if status == "arrived", session.can("job.edit", feature: "jobs") {
            Button { showCantStart = true } label: { secondaryPill("Can't start \u{2014} tell dispatch") }
                .buttonStyle(PressStyle())
                .accessibilityHint("Tells the office why the work can't start")
                .accessibilityIdentifier("job-cant-start")
        } else if status == "in_progress", fieldWrapsUp, session.can("invoice.view", feature: "invoicing") {
            // Paper F5 "Send invoice instead": the invoice itself, to review and send.
            Button {
                if let bill = WrapUpList.billingInvoice(invoices) { reviewInvoiceID = bill.id } else { run(.createInvoice) }
            } label: { secondaryPill("Send invoice instead") }
                .buttonStyle(PressStyle())
                .disabled(busy || creatingInvoice)
                .accessibilityHint("Opens the invoice to send instead of collecting now")
                .accessibilityIdentifier("job-send-invoice")
        } else if status == "in_progress", !fieldWrapsUp, session.can("job.complete", feature: "jobs") {
            // Paper F4 "Mark done without estimate": straight to Wrap up, which holds the checks
            // and Complete job.
            Button { withMotion(.snappy) { wrapUpStageOpen = true } } label: { secondaryPill("Mark done without estimate") }
                .buttonStyle(PressStyle())
                .accessibilityHint("Moves on to Wrap up without showing the estimate")
                .accessibilityIdentifier("job-mark-done")
        }
    }

    /// Paper F5 "Wrap up": working, with the estimate (when there is one) already answered, or the
    /// tech having chosen to wrap up without one. Until then the step is Working (F4).
    private var fieldWrapsUp: Bool {
        guard onSiteWrapsUp else { return false }
        if wrapUpStageOpen { return true }
        let rows = wrapUpRows
        guard let approval = rows.first(where: { $0.step == .approval }) else { return false }
        return approval.done
    }

    /// True while the working commit is the estimate to hand the customer (Paper F4).
    private var workingCommitShowsEstimate: Bool {
        guard onSiteWrapsUp, let next = wrapUpRows.first(where: { !$0.done }) else { return false }
        return next.step == .approval && estimateCommitTitle != nil
    }

    /// Paper F4 "Show estimate to Danielle · $340.00": the words for a next step that hands the
    /// customer the job's estimate. The amount shows for one estimate with one set of lines, never
    /// a sum of papers the customer chooses between. Nil when the next step is something else.
    private var estimateCommitTitle: String? {
        guard let job, let step = nextStep else { return nil }
        let name = customerCallName(job)
        switch step {
        case .showEstimate(let id):
            let amount = jobEstimates.first(where: { $0.id == id }).flatMap { estimateCommitAmount($0) }
            return amount.map { "Show estimate to \(name) \u{00B7} \($0)" } ?? "Show estimate to \(name)"
        case .presentEstimates:
            let sent = jobEstimates.filter { $0.status == "sent" }
            guard sent.count == 1, let only = sent.first else { return "Show estimates to \(name)" }
            return estimateCommitAmount(only).map { "Show estimate to \(name) \u{00B7} \($0)" } ?? "Show estimate to \(name)"
        default:
            return nil
        }
    }

    private func estimateCommitAmount(_ estimate: EstimateRecord) -> String? {
        guard (estimate.options ?? []).isEmpty, let total = paperLinesTotal(estimate.lines) else { return nil }
        return money(total, currency: estimate.lines.first?.unitPrice.currency ?? "USD")
    }

    /// The working commit's words. It names what its tap does when that is Paper's own step: the
    /// estimate to show (F4) or the balance to collect (F5 "Collect $340.00"). Any other open row
    /// keeps "Wrap up · 3 left".
    private func workingCommitTitle(_ rows: [WrapUpRow]) -> String {
        guard let next = rows.first(where: { !$0.done }) else { return commitTitle(rows) }
        if next.step == .approval, let title = estimateCommitTitle { return title }
        if next.step == .payment, let bill = WrapUpList.billingInvoice(invoices), bill.status == "issued",
           let due = TechJobFlow.due(bill), due > 0, session.can("invoice.payment.create", feature: "payments") {
            return "Collect \(money(due, currency: bill.currency))"
        }
        return commitTitle(rows)
    }

    /// Paper F4's commit: full width, 60 tall, its words at 17 Semibold with no glyph. It walks the
    /// wrap-up rows exactly as the bar's commit does (`commitButton`): the first open row, then
    /// Complete job, or the closeout screen when the server or this role can't complete yet.
    private var workingCommitButton: some View {
        let rows = wrapUpRows
        let next = rows.first { !$0.done }
        let title = workingCommitTitle(rows)
        return Button {
            if let next { openWrapUpRow(next) } else if canCompleteHere { confirmComplete = true } else { showWrapUp = true }
        } label: {
            HStack(spacing: 10) {
                if busy || creatingInvoice { ProgressView().tint(.white) }
                Text(title)
                    .font(Theme.font(17, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .inkCommit(height: PaperControl.Size.field.height)
        }
        .buttonStyle(PressStyle())
        .disabled(busy || creatingInvoice)
        .accessibilityLabel(title)
        .accessibilityHint(next.map { "Opens \($0.title.lowercased())" } ?? (canCompleteHere ? "Completes the job" : "Opens the closeout checklist"))
        .accessibilityIdentifier("job-commit")
    }

    /// Directions as the bar's circle gives them: straight to Maps with one address on file, a
    /// choice with several, nothing with none (no job site is inferred).
    @ViewBuilder private var openInMaps: some View {
        if customerLocations.count == 1, let only = customerLocations.first,
           let url = JobLocationPolicy.directions(for: only.id, in: customerLocations) {
            Button { openURL(url) } label: { secondaryPill("Open in Maps") }
                .buttonStyle(PressStyle())
                .accessibilityHint("Opens driving directions in Maps")
                .accessibilityIdentifier("job-open-in-maps")
        } else if customerLocations.count > 1 {
            ThorbisMenu(items: customerLocations.map { place in
                ThorbisMenuItem(place.label, icon: place.kind == "billing" ? "creditcard" : "mappin.and.ellipse",
                                subtitle: "\(place.kind == "billing" ? "Billing" : "Service") · \(place.address)") {
                    if let url = JobLocationPolicy.directions(for: place.id, in: customerLocations) { openURL(url) }
                }
            }, title: "Directions to", accessibilityLabel: "Open in Maps") {
                secondaryPill("Open in Maps")
            }
            .accessibilityHint("Choose a customer location")
            .accessibilityIdentifier("job-open-in-maps")
        }
    }

    /// Paper's field-mode second action: a 52pt pill on the field fill, 17 Semibold.
    private func secondaryPill(_ title: String) -> some View {
        Text(title).paperButton(.commit, tone: .quiet, fills: true)
    }

    /// One of the bar's card circles (camera, Call, Text, Directions). Paper draws three at 50pt;
    /// with the camera kept in the bar they are 44 so the commit keeps its words.
    private func barCircle(_ symbol: String, enabled: Bool = true) -> some View {
        let glyph: PaperGlyph = symbol == "phone" ? .phone : symbol == "message" ? .message : .navigate
        return PaperIcon(glyph, size: symbol == "location" ? 18 : 20, color: Theme.foreground.opacity(enabled ? 1 : 0.4))
            .frame(width: 48, height: 48)
            .background(Theme.card, in: Circle())
            .contentShape(Circle())
    }

    /// The note circle: opens Activity with the note field focused, ready to type or dictate.
    private var noteCircle: some View {
        Button { openNoteTool() } label: { PaperCircleLabel(symbol: "note.text", size: 40, fill: Theme.card) }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Add a note")
            .accessibilityHint("Opens the note composer in Activity")
            .accessibilityIdentifier("job-bar-note")
    }

    /// The bar's camera: the job's photos open straight into the camera.
    private var cameraCircle: some View {
        Button { openCapture(.camera(stage: nil)) } label: { barCircle("camera") }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Take photo")
            .accessibilityHint("Opens the camera and adds the photo to this job")
            .accessibilityIdentifier("job-bar-camera")
    }

    /// The ink commit. On site it walks the wrap-up rows: with rows left it goes to the first one;
    /// at 0 it completes the job (one confirm), or opens the closeout screen when the server or this
    /// role can't complete yet. Otherwise it runs the next step.
    @ViewBuilder private func commitButton(_ step: TechJobStep) -> some View {
        if onSiteWrapsUp {
            let rows = wrapUpRows
            let next = rows.first { !$0.done }
            Button {
                if let next { openWrapUpRow(next) } else if canCompleteHere { confirmComplete = true } else { showWrapUp = true }
            } label: {
                HStack(spacing: 7) {
                    if busy || creatingInvoice { ProgressView().tint(.white) }
                    else { PaperIcon(.jobShieldCheck, size: 18, color: .white) }
                    commitLabel(rows).font(Theme.font(16, weight: .semibold))
                }
                .inkCommit(height: PaperControl.Size.card.height)
            }
            .buttonStyle(PressStyle())
            .disabled(busy || creatingInvoice)
            .accessibilityLabel(commitTitle(rows))
            .accessibilityHint(next.map { "Opens \($0.title.lowercased())" } ?? (canCompleteHere ? "Completes the job" : "Opens the closeout checklist"))
            .accessibilityIdentifier("job-commit")
        } else {
            Button { run(step) } label: {
                HStack(spacing: 7) {
                    if busy || creatingInvoice { ProgressView().tint(.white) }
                    else if step == .wrapUp { PaperIcon(.jobShieldCheck, size: 18, color: .white) }
                    else { Image(systemName: step.symbol).font(.system(size: 15, weight: .semibold)).accessibilityHidden(true) }
                    Text(step.title(resuming: job?.status == "paused")).font(Theme.font(16, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .inkCommit(height: PaperControl.Size.card.height)
            }
            .buttonStyle(PressStyle())
            .disabled(busy || creatingInvoice)
            .accessibilityIdentifier("job-next-step")
        }
    }

    /// Paper F2 "I've arrived" and F3 "Start work": the field commit, full width, 60 tall, its words
    /// at 18 Semibold with no glyph. It runs the same next step as the bar's commit.
    private func fieldCommitButton(_ step: TechJobStep) -> some View {
        Button { run(step) } label: {
            HStack(spacing: 10) {
                if busy || creatingInvoice { ProgressView().tint(.white) }
                Text(step.title(resuming: job?.status == "paused"))
                    .font(Theme.font(18, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .inkCommit(height: PaperControl.Size.field.height)
        }
        .buttonStyle(PressStyle())
        .disabled(busy || creatingInvoice)
        .accessibilityIdentifier("job-next-step")
    }

    /// "Wrap up · 3 left" on one line; when large text can't fit it, "Wrap up" over "3 left" so the
    /// second line never starts with a dot.
    @ViewBuilder private func commitLabel(_ rows: [WrapUpRow]) -> some View {
        let left = WrapUpList.left(rows)
        if left > 0 {
            ViewThatFits(in: .horizontal) {
                Text(commitTitle(rows)).lineLimit(1)
                VStack(spacing: 0) {
                    Text("Wrap up")
                    Text("\(left) left")
                }
                .multilineTextAlignment(.center)
            }
        } else {
            Text(commitTitle(rows))
        }
    }

    /// "Wrap up · 3 left" while rows are open; "Complete job" once the server will take it.
    private func commitTitle(_ rows: [WrapUpRow]) -> String {
        let left = WrapUpList.left(rows)
        // Paper 21: the bar's commit is "Wrap up job"; what is left shows in field mode's Wrap up.
        if left > 0 { return inFieldNow ? "Wrap up · \(left) left" : "Wrap up job" }
        return canCompleteHere ? "Complete job" : "Wrap up job"
    }

    private var inFieldNow: Bool { job.map { inField($0) } ?? false }

    /// Completing straight from the bar: the server says it's completable, allows the move and
    /// this role may make it. Otherwise the closeout screen explains what's holding it.
    private var canCompleteHere: Bool {
        guard let job, let closeout, closeout.completable, session.can("job.complete", feature: "jobs"),
              outbox.pendingStatus(for: job.id) == nil else { return false }
        return job.allowedTransitions?.contains("completed") == true
    }

    private func completeHere() async {
        busy = true
        defer { busy = false }
        do {
            let updated = try await api.completeFieldJob(jobId, request: .init())
            job = updated
            committed += 1
            closeout = nil
            await store.refresh(api)
            await load()
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }

    /// Calls the office when the workspace has a business phone this role can read. The customer's
    /// Call is already in the header's circles, so it isn't repeated here (BYR-1599: no office phone, no circle).
    @ViewBuilder private var callCircle: some View {
        if let url = officeContact?.callURL {
            Button { openURL(url) } label: { PaperCircleLabel(symbol: "phone", size: 40, fill: Theme.card) }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Call the office")
            .accessibilityIdentifier("job-onsite-call")
        }
    }

    /// Money's one bar, in the order the paper needs it: a draft invoice to send, then what's owed,
    /// then the estimates to show the customer, then the first estimate to build.
    @ViewBuilder private var moneyAction: some View {
        if let invoice = selectedInvoice, invoice.status == "draft", session.can("invoice.view", feature: "invoicing") {
            PaperActionBar(title: "Review and send invoice", symbol: "paperplane") { reviewInvoiceID = invoice.id }
        } else if moneyBarCollects, let model = invoicePaymentModel {
            PaperInvoiceCollectionFooter(model: model,
                invoiceReference: invoices.count > 1 ? selectedInvoice.map { jobInvoiceReference($0.id) } : nil) {
                    if let id = selectedInvoice?.id { presentPayment(for: id) }
                }
        } else if !jobEstimates.isEmpty, session.can("estimate.view", feature: "estimates") {
            PaperActionBar(title: "Show customer", symbol: "iphone") { openCustomerView(.estimates) }
                .accessibilityIdentifier("job-customer-view-bar")
        } else if canBuildEstimate {
            PaperActionBar(title: "Build an estimate", symbol: "doc.badge.plus", action: buildEstimate)
        }
    }

    private var moneyBarCollects: Bool {
        guard session.can("invoice.payment.create", feature: "payments"), let invoice = selectedInvoice,
              invoice.status != "draft", invoicePaymentModel != nil else { return false }
        return loadedInvoiceModelID == invoice.id
    }

    /// Whether Money's bar is already Customer view, so the estimates list doesn't repeat it.
    private var moneyBarIsCustomerView: Bool {
        guard !jobEstimates.isEmpty, session.can("estimate.view", feature: "estimates") else { return false }
        if let invoice = selectedInvoice, invoice.status == "draft", session.can("invoice.view", feature: "invoicing") { return false }
        return !moneyBarCollects
    }

    /// Paper 21 Job details: one card per section, 20 apart, in the order a tech needs them at the
    /// door. On site the toolkit and what's left before wrapping up lead (Paper's field-mode card);
    /// then what to know at this address, the job's description and customer, the people on the
    /// account, the line items, the money and the latest activity. Every other section stays below,
    /// so nothing the Overview had is out of reach. Actions that aren't the bar's next step are in •••.
    @ViewBuilder private func overviewContent(_ job: JobRecord) -> some View {
        if inField(job) { fieldModeContent(job) } else { detailsOverview(job) }
    }

    /// Paper F2 to F5: field mode is the step's own cards and nothing else. Everything on Job
    /// details is one tap away in More › Full job details.
    private func fieldModeContent(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if fieldStep(job) == 4 {
                fieldPaidContent(job)
            } else if shownStatus(job) == "in_progress" {
                if fieldWrapsUp { fieldWrapUp(job) } else { workingLead(job) }
            } else {
                fieldLead(job)
            }
        }
    }

    /// Paper 21 Job details, Overview: the field-mode card while the visit is under way, how to get
    /// in and what to watch for, why the office sent the visit, the checklist, then Details,
    /// Contacts, Line items and Activity. Past visits, equipment and who was notified are "At this
    /// address" (Paper 21O, in More); follow-ups, the customer view and photos are in More and
    /// Activity.
    private func detailsOverview(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                fieldModeCard(job)
                accessCard(job)
                descriptionCard(job)
                checklistCard(job)
            }
            customerPanel(job).id("job-details")
            if session.can("customer.view", feature: "core_crm") {
                let current = customerContext(job) != nil && customerContext(job) == contactsContext
                let canAddContact = current && session.can("customer.edit", feature: "core_crm")
                let addContact: (() -> Void)? = canAddContact ? { showAddContact = true } : nil
                JobContactsSection(people: JobContacts.people(contacts: current ? contacts : [], customer: current ? customerRecord : nil),
                                   preference: JobContacts.preference(current ? customerRecord : nil),
                                   loaded: current && contactsLoaded, failed: current && contactsFailed,
                                   customerID: job.customerId, jobID: job.id,
                                   customerName: linkedCustomer(job)?.name,
                                   onAdd: addContact) { await loadContacts(job) }
            }
            partsPanel
            latestActivity(job).id("job-latest-activity")
        }
    }

    /// Paper F5 "Wrap up": what is still open before the job can close ("Finish checklist · 3
    /// left"), the visit in three numbers, and where the customer signs. Each open row goes to
    /// what completes it; the bar collects.
    @ViewBuilder private func fieldWrapUp(_ job: JobRecord) -> some View {
        let rows = wrapUpRows
        let open = rows.filter { !$0.done && $0.step != .signature && $0.step != .payment }
        let bill = invoices.first(where: { $0.status == "draft" }) ?? WrapUpList.billingInvoice(invoices)
        let since = JobFiltering.date(job.arrivedAt) ?? JobFiltering.date(job.startedAt)
        VStack(alignment: .leading, spacing: 16) {
            if !open.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Finish checklist").accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 8)
                        Text("\(open.count) left")
                    }
                    .font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 4)
                    VStack(spacing: 0) {
                        ForEach(Array(open.enumerated()), id: \.element.id) { index, row in
                            Button { openWrapUpRow(row) } label: {
                                HStack(spacing: 12) {
                                    Circle().strokeBorder(Theme.borderStrong, lineWidth: 1.6).frame(width: 32, height: 32)
                                    HStack(spacing: 8) {
                                        Text(row.title).font(Theme.font(17, weight: .medium)).foregroundStyle(Theme.foreground)
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        if row.step == .afterPhotos || row.step == .beforePhotos {
                                            Text("Add photo").paperButton(.card, tone: .tinted)
                                        }
                                    }
                                    .padding(.trailing, 12).padding(.vertical, 8)
                                    .frame(minHeight: 64)
                                    .overlay(alignment: .top) { if index > 0 { Rectangle().fill(Theme.border).frame(height: 1) } }
                                }
                                .padding(.leading, 16)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(RowPressStyle())
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(row.title)
                            .accessibilityValue("To do")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("job-wrap-up-\(row.id)")
                        }
                    }
                    .panelBackground(cornerRadius: Theme.cardRadius)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                PaperSectionLabel(title: "Summary", gap: 0)
                VStack(spacing: 0) {
                    if session.can("invoice.view", feature: "invoicing"), let bill, let total = paperLinesTotal(bill.lines) {
                        fieldSummaryRow("Parts and labor", value: money(total, currency: bill.currency), first: true)
                    }
                    if let since {
                        TimelineView(.everyMinute) { context in
                            fieldSummaryRow("Time on site", value: JobOnSiteClock.short(arrived: since, now: context.date))
                        }
                    }
                    if liveMediaCountContext != nil, liveMediaCountContext == mediaCountContext, mediaCount != nil {
                        let waiting = pendingMedia.items.filter { $0.jobID == jobId && $0.kind == "photo" }.count
                        fieldSummaryRow("Photos", value: "\(mediaPhotos.count + waiting)\(mediaHasMore ? "+" : "")")
                    }
                }
                .panelBackground(cornerRadius: Theme.cardRadius)
            }
            if let signature = rows.first(where: { $0.step == .signature }) {
                VStack(alignment: .leading, spacing: 8) {
                    PaperSectionLabel(title: "Customer sign-off", gap: 0)
                    Button { openWrapUpRow(signature) } label: {
                        VStack(spacing: 6) {
                            PaperIcon(.jobSignature, size: 28, color: signature.done ? Theme.statusDone : Theme.muted)
                            Text(signature.done ? "Signed" : "\(customerCallName(job)) signs here")
                                .font(Theme.font(17, weight: .medium)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                        .padding(12)
                        .panelBackground(cornerRadius: Theme.cardRadius)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel(signature.done ? "Customer signed" : "\(customerCallName(job)) signs here")
                    .accessibilityHint("Opens the invoice for the customer's signature")
                    .accessibilityIdentifier("job-wrap-up-signature")
                }
            }
        }
        // Paper F5: the first label sits 22 under the steps (the header leaves 14).
        .padding(.top, 8)
        .id("job-wrap-up")
    }

    private func fieldSummaryRow(_ label: String, value: String, first: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(label).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value).font(Theme.font(17, weight: .semibold)).foregroundStyle(Theme.foreground)
        }
        .padding(.trailing, 16).padding(.vertical, 8)
        .frame(minHeight: 60)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Theme.border).frame(height: 1) } }
        .padding(.leading, 16)
        .accessibilityElement(children: .combine)
    }

    /// Paper F6 "Paid": the amount on a green check, what closing the job left to do (the invoice,
    /// a follow-up to book), then this person's next stop today. Paper's card line and "Review
    /// request" row are left out: the job doesn't hold how it was paid or when a review is asked for.
    @ViewBuilder private func fieldPaidContent(_ job: JobRecord) -> some View {
        if let bill = WrapUpList.billingInvoice(invoices) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 4) {
                    PaperIcon(.jobPaidCheck, size: 34, color: Theme.success)
                        .frame(width: 72, height: 72)
                        .background(Theme.statusDone.opacity(0.22), in: Circle())
                    Text("Paid \(money(bill.amountPaid, currency: bill.currency))")
                        .font(Theme.font(28, weight: .bold)).tracking(-0.56)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                        .accessibilityAddTraits(.isHeader)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                VStack(alignment: .leading, spacing: 8) {
                    Text(shownStatus(job) == "completed" ? "Job closed" : "Paid in full")
                        .font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 4).accessibilityAddTraits(.isHeader)
                    VStack(spacing: 0) {
                        Button { reviewInvoiceID = bill.id } label: {
                            HStack(spacing: 12) {
                                Text("Invoice \(jobInvoiceReference(bill.id))").font(Theme.font(16, weight: .medium))
                                    .foregroundStyle(Theme.foreground)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("Paid").font(Theme.font(17, weight: .semibold)).foregroundStyle(Theme.success)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .frame(minHeight: 60)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityHint("Opens the invoice")
                        .accessibilityIdentifier("job-paid-invoice")
                        if let book = paidBookNextVisit {
                            Button(action: book) {
                                HStack(spacing: 12) {
                                    Text("Follow-up").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("Book").paperButton(.card, tone: .tinted)
                                }
                                .padding(.trailing, 12).padding(.vertical, 8)
                                .frame(minHeight: 64)
                                .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
                                .padding(.leading, 16)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(RowPressStyle())
                            .accessibilityLabel("Book a follow-up")
                            .accessibilityIdentifier("job-paid-follow-up")
                        }
                    }
                    .panelBackground(cornerRadius: Theme.cardRadius)
                }
                if let next = nextStopJob {
                    NavigationLink(value: next) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(["Next stop", JobFiltering.date(next.scheduledFor)?.tradeTime].compactMap { $0 }.joined(separator: " \u{00B7} "))
                                .font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.brandText)
                            Text(next.title).font(Theme.font(22, weight: .bold)).tracking(-0.44).foregroundStyle(Theme.foreground)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            if let customerID = next.customerId, store.customerName(customerID) != "Customer" {
                                Text(store.customerName(customerID)).font(Theme.font(15)).foregroundStyle(Theme.muted)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .panelBackground(cornerRadius: Theme.cardRadius)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityHint("Opens your next stop")
                    .accessibilityIdentifier("job-paid-next-stop")
                }
            }
            .padding(.top, 2)
        }
    }

    /// Paper F6's commit. It opens the next stop, where "On my way" starts the drive (Paper's "On
    /// my way to Larch Ave" would start it from here, and the job list has no street to name).
    /// With no stop left today it closes field mode onto Job details.
    @ViewBuilder private var fieldPaidCommit: some View {
        if let next = nextStopJob {
            NavigationLink(value: next) {
                HStack(spacing: 10) {
                    PaperIcon(.navigate, size: 18, color: .white)
                    Text("Go to next stop").font(Theme.font(18, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                }
                .inkCommit(height: PaperControl.Size.field.height)
            }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("job-paid-next")
        } else {
            Button { withMotion(.snappy) { fieldModeOpen = false } } label: {
                Text("Done").font(Theme.font(18, weight: .semibold)).inkCommit(height: PaperControl.Size.field.height)
            }
            .buttonStyle(PressStyle())
            .accessibilityHint("Closes field mode and shows the job's details")
            .accessibilityIdentifier("job-paid-done")
        }
    }

    /// Paper 21 "Field mode · Working": where the visit is on field mode's five steps, and the
    /// way back into it.
    @ViewBuilder private func fieldModeCard(_ job: JobRecord) -> some View {
        if let shown = fieldStep(job) {
            Button { withMotion(.snappy) { fieldModeOpen = true; selectedTab = "Overview" } } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Field mode \u{00B7} \(JobFieldSteps.titles[shown])")
                            .font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 4) {
                            ForEach(0..<JobFieldSteps.titles.count, id: \.self) { index in
                                Capsule().fill(index < shown || shown == 4 ? Theme.statusDone : index == shown ? Theme.brand : Theme.foreground.opacity(0.12))
                                    .frame(height: 4)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(shownStatus(job) == "dispatched" ? "Open" : "Resume").paperButton(.secondary, tone: .tinted)
                }
                .padding(.vertical, 12).padding(.leading, 16).padding(.trailing, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panelBackground(cornerRadius: Theme.cardRadius)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            // Paper: the next card sits 16 under this one (12 between the others).
            .padding(.bottom, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Field mode, \(JobFieldSteps.titles[shown]), step \(shown + 1) of \(JobFieldSteps.titles.count)")
            .accessibilityHint("Resumes field mode")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("job-field-mode-card")
        }
    }

    /// Paper 21: how to get in (the codes, under a key) and what to watch for (the site's notes,
    /// under a warning triangle in the warning tone), each on one 16 Medium line.
    @ViewBuilder private func accessCard(_ job: JobRecord) -> some View {
        if let banner = accessBanner(job) {
            let codes = banner.headline
            let notes = banner.facts.filter { $0.label == "Site notes" }.map(\.value)
            if !codes.isEmpty || !notes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    if !codes.isEmpty { accessRow(.jobKey, text: codes, color: Theme.foreground) }
                    ForEach(notes, id: \.self) { note in accessRow(.jobWarning, text: note, color: Theme.warning) }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panelBackground(cornerRadius: Theme.cardRadius)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("job-access-card")
            }
        }
    }

    private func accessRow(_ glyph: PaperGlyph, text: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            PaperIcon(glyph, size: 20, color: color).frame(width: 24, height: 24)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
            Text(text).font(Theme.font(16, weight: .medium)).foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Paper 21O "At this address": past visits, the equipment on file and who was notified, on a
    /// screen of their own (More › At this address). The job's other records with no place on
    /// Paper's Overview (service addresses, membership, the booking call, follow-ups and the
    /// record's own dates) follow them here.
    private func atAddressScreen(_ job: JobRecord) -> some View {
        JobAtAddressView(job: job, street: street(job), visits: visits, visitsLoaded: visitsLoaded, locations: customerLocations) {
            if let bookingCall { JobBookingCallSection(call: bookingCall) }
            if session.can("customer.view", feature: "core_crm") {
                let placesCurrent = customerContext(job) != nil && customerContext(job) == locationsContext
                JobServiceAddressesSection(customerID: job.customerId, places: customerLocations,
                                           loaded: placesCurrent, failed: locationsFailed,
                                           headerStreet: displayTitle(job),
                                           factsShownFor: JobPropertyHistory.accessPlace(job: job, locations: customerLocations)?.id) { await loadLocations(job) }
            }
            CustomerMembershipSection(customerID: job.customerId, editable: false, jobID: job.id)
            followUpsPanel
            detailsGroup(job)
        }
    }

    /// The drive to the job's place while it is still ahead, on a card (it was under the header).
    /// Paper F2: driving, it is the tall card that leads the screen, the drive ("18 min · 6.2 mi") on
    /// its own pill.
    private func mapStrip(_ job: JobRecord, driving: Bool = false) -> some View {
        let drive = MapStrip.drive(minutes: eta.minutes, miles: driving ? eta.miles : nil)
        return MapStrip(pill: driving ? nil : drive, aspect: driving ? 358 / 250 : 358 / 96, pillAtBottom: true,
                        hasPlace: jobCoordinates(job) != nil || !customerLocations.isEmpty)
            .overlay(alignment: .bottomLeading) {
                if driving, let drive { drivePill(drive) }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .task(id: "eta|\(job.id)|\(shownStatus(job))|\(jobCoordinates(job).map { "\($0.latitude),\($0.longitude)" } ?? "")|\(session.isOffline)") {
                let ahead = ["scheduled", "dispatched", "en_route"].contains(shownStatus(job))
                await eta.update(to: jobCoordinates(job), key: "\(job.id)|\(job.locationId ?? "")", enabled: ahead && !session.isOffline)
            }
    }

    /// Paper F2's drive pill: a clock in the brand tone and the drive at 17 Semibold, on the canvas tone.
    private func drivePill(_ line: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "clock").font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.brandText)
                .accessibilityHidden(true)
            Text(line).font(Theme.font(17, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.foreground)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
        .background(Theme.background, in: Capsule())
        .padding(12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("job-drive-pill")
    }

    /// Paper's field mode leads Overview with what the moment needs. Driving (F2): the map with the
    /// drive, when the visit is booked for with "Update time", and one tap to call. Arrived (F3):
    /// "You're here" and the before photos. Through the whole visit: what to know before going in.
    @ViewBuilder private func fieldLead(_ job: JobRecord) -> some View {
        let status = shownStatus(job)
        // A dispatched job about to be driven to shows the same cards as the drive (Paper F2).
        if status == "en_route" || status == "dispatched" {
            mapStrip(job, driving: true)
            arrivalCard(job)
            drivingCallCard(job)
        }
        if status == "arrived" {
            youAreHere(job)
        }
        // Paper F2 draws no banner while driving (the codes ride in the call card); F3 leads with it.
        if status == "arrived", let banner = fieldBanner(job, status: status) {
            banner
        }
        if status == "arrived" {
            beforePhotosPanel(job)
        }
    }

    /// What to know before going in, shaped for the moment. Driving (Paper F2) the codes ride in the
    /// call card, so only the site's warning shows here. Arrived (Paper F3) "Know before you knock"
    /// also says why the office sent the visit. Nil when there is nothing to say.
    private func fieldBanner(_ job: JobRecord, status: String) -> JobAccessBanner? {
        let note = job.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var banner = accessBanner(job) ?? JobAccessBanner(facts: [])
        banner.description = status == "arrived" && !note.isEmpty ? note : nil
        banner.equipment = status == "arrived" ? equipmentLine(job) : nil
        banner.showsCodes = status != "en_route"
        if !banner.showsCodes { return banner.notes == nil ? nil : banner }
        if banner.facts.isEmpty && banner.description == nil && banner.equipment == nil { return nil }
        return banner
    }

    /// Paper F2's arrival card. The app doesn't know whether the customer was texted, so it never
    /// says so: it shows the booked time, the arrival the drive works out to, and "Update time",
    /// which opens Running late (the text with a new time goes from the tech's own phone).
    @ViewBuilder private func arrivalCard(_ job: JobRecord) -> some View {
        if let scheduled = JobFiltering.date(job.scheduledFor) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(driveArrival == nil ? "Arrival" : "Booked for \(scheduled.tradeTime)")
                        .font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(driveArrival.map { "Arriving about \($0.tradeTime)" } ?? "Booked for \(scheduled.tradeTime)")
                        .font(Theme.font(17, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                Button { showRunningLate = true } label: {
                    Text("Update time").paperButton(.card, tone: .tinted)
                }
                .buttonStyle(PressStyle())
                .accessibilityHint("Text the customer a new arrival time")
                .accessibilityIdentifier("job-update-time")
            }
            .padding(.leading, 16).padding(.trailing, 10).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelBackground(cornerRadius: Theme.cardRadius)
            // The drive time is worked out once; the arrival is pinned then, not at every redraw.
            .onChange(of: eta.minutes, initial: true) { old, minutes in
                // Coming back to this tab re-runs the initial call with the same drive time:
                // keep the first estimate, or "arriving about" would creep later.
                guard old != minutes || driveArrival == nil else { return }
                driveArrival = minutes.map { Date.now.addingTimeInterval(Double($0) * 60) }
            }
        }
    }

    /// Paper F2: one card while driving. "Call Danielle", one tap, then the codes for the door
    /// behind a key ("Gate 4482# · key under mat"), split by a hairline that starts at the words.
    @ViewBuilder private func drivingCallCard(_ job: JobRecord) -> some View {
        let call = customerReach(job).call
        let access = accessBanner(job)
        let codes = access?.headline ?? ""
        if call != nil || !codes.isEmpty {
            VStack(spacing: 0) {
                if let call {
                    Button { openURL(call) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "phone").font(.system(size: 18, weight: .regular)).foregroundStyle(Theme.foreground)
                                .frame(width: 28)
                                .accessibilityHidden(true)
                            Text("Call \(customerCallName(job))").font(Theme.font(17, weight: .medium)).foregroundStyle(Theme.foreground)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            PaperChevron()
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityLabel("Call \(store.customerName(job.customerId))")
                    .accessibilityIdentifier("job-driving-call")
                }
                if !codes.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "key").font(.system(size: 18, weight: .regular)).foregroundStyle(Theme.foreground)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        Text(codes).font(Theme.font(17, weight: .medium)).monospacedDigit().foregroundStyle(Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                    .overlay(alignment: .top) {
                        if call != nil {
                            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 56)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                    .contextMenu {
                        ForEach((access?.facts ?? []).filter(\.isCode)) { fact in
                            Button("Copy \(fact.label.lowercased())", systemImage: "doc.on.doc") { UIPasteboard.general.string = fact.value }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityHint((access?.facts ?? []).contains(where: \.isCode) ? "Touch and hold to copy a code" : "")
                    .accessibilityIdentifier("job-driving-access")
                }
            }
            .panelBackground(cornerRadius: Theme.cardRadius)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
    }

    /// Paper F3 "Arrived": "You're here" over the street.
    private func youAreHere(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Paper F3: 28 Bold, tracked -2%.
            Text("You're here").font(Theme.heading()).tracking(-0.56).foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
            if let street = street(job) {
                Text(street).font(Theme.font(17)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 4).padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("job-you-are-here")
    }

    /// Paper F3 "Before photos": the visit's before photos as 96pt tiles and a dashed Add tile that
    /// opens the camera filing under Before. The count is what's added; how many a workspace
    /// requires isn't something this screen knows, so it isn't claimed.
    @ViewBuilder private func beforePhotosPanel(_ job: JobRecord) -> some View {
        let canAdd = session.can("job.edit", feature: "jobs")
        let current = liveMediaCountContext != nil && liveMediaCountContext == mediaCountContext
        let count = current ? stagedPhotoCount("Before") : nil
        let photos = current ? Array(mediaPhotos.filter { $0.tags.contains("Before") }.prefix(6)) : []
        if canAdd || !photos.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                JobPanelLabel(title: "Before photos", count: count.map { "\($0) added" })
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(photos) { photo in
                            Button { openPhotos() } label: {
                                Color.clear
                                    .frame(width: 96, height: 96)
                                    .overlay(MediaThumbnail(record: photo))
                                    // Paper F3: the photo's own caption sits on its tile ("Condenser").
                                    .overlay(alignment: .bottomLeading) {
                                        if let caption = photo.caption, !caption.isEmpty {
                                            Text(caption).font(Theme.font(12, weight: .semibold))
                                                .foregroundStyle(Theme.foreground)
                                                .lineLimit(1)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(Theme.card.opacity(0.9), in: Capsule())
                                                .padding(6)
                                                .accessibilityHidden(true)
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityLabel(photo.caption ?? "Before photo")
                        }
                        if canAdd {
                            Button { openCapture(.camera(stage: "Before")) } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "plus").font(.system(size: 20, weight: .regular))
                                        .accessibilityHidden(true)
                                    Text("Add").font(Theme.font(14, weight: .semibold))
                                }
                                .foregroundStyle(Theme.foreground)
                                .frame(width: 96, height: 96)
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Theme.muted, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityLabel("Add a before photo")
                            .accessibilityHint("Opens the camera and files the photo under Before")
                            .accessibilityIdentifier("job-before-photo-add")
                        }
                    }
                    .padding(16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .panelBackground(cornerRadius: Theme.cardRadius)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            }
            .accessibilityIdentifier("job-before-photos")
        }
    }

    /// Who the job is for (with membership and the account at a glance, opening their profile),
    /// then why the office sent the visit, and the pause reason when it's paused.
    private func customerPanel(_ job: JobRecord) -> some View {
        // Paper 21 "Details": one card of label-and-value rows (Customer, Address, Equipment),
        // 56 tall, the label in the marker grey and the value at 15 Medium on the right.
        return VStack(alignment: .leading, spacing: 8) {
        JobPanelLabel(title: "Details")
        JobPanel {
            if let customer = linkedCustomer(job) {
                NavigationLink(value: customer) { customerRow(job, name: customer.name, opens: true) }
                    .buttonStyle(RowPressStyle())
                    .accessibilityIdentifier("job-customer-link")
                    .accessibilityHint("Opens the customer's profile")
            } else {
                customerRow(job, name: store.customerName(job.customerId), opens: false)
            }
            if let address = detailsAddress(job) {
                if let url = jobDirectionsURL(job) {
                    Button { openURL(url) } label: {
                        detailValueRow("Address", value: address, valueColor: Theme.brandText, glyph: .jobArrowOut,
                                       symbolColor: Theme.brandText)
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityLabel("Address, \(address)")
                    .accessibilityHint("Opens driving directions in Maps")
                    .accessibilityIdentifier("job-details-address")
                } else {
                    detailValueRow("Address", value: address)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("job-details-address")
                }
            }
            if let equipmentLine = equipmentLine(job) {
                Button { showAtAddress = true } label: { detailValueRow("Equipment", value: equipmentLine, glyph: .jobUpDown) }
                    .buttonStyle(RowPressStyle())
                    .accessibilityLabel("Equipment, \(equipmentLine)")
                    .accessibilityHint("Opens the equipment at this address")
                    .accessibilityIdentifier("job-details-equipment")
            }
            if job.pauseReason != nil || job.pauseNextAction != nil {
                VStack(alignment: .leading, spacing: 3) {
                    JobStatusWord(word: "Paused", color: Theme.warning)
                    if let reason = job.pauseReason { Text(reason).font(Theme.font(15)).foregroundStyle(Theme.foreground) }
                    if let next = job.pauseNextAction { Text("Next: \(next)").font(Theme.font(15)).foregroundStyle(Theme.subtle) }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .accessibilityElement(children: .combine)
            }
        }
        // A container, so the link inside keeps its own `job-customer-link` identifier.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("job-customer-panel")
        }
    }

    /// Paper 21: why the office sent the visit, as its own card of 15pt words (22 leading) with no
    /// heading. Arrived, the same words are the last row of "Know before you knock" instead.
    @ViewBuilder private func descriptionCard(_ job: JobRecord) -> some View {
        let officeNote = job.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !officeNote.isEmpty, shownStatus(job) != "arrived" {
            Text(officeNote)
                .font(Theme.font(15)).foregroundStyle(Theme.foreground).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .panelBackground(cornerRadius: Theme.cardRadius)
                .accessibilityLabel("From the office: \(officeNote)")
                .accessibilityIdentifier("job-description")
        }
    }

    /// Paper 21 "Checklist · 5 of 8": the checklist this person has under way on this phone, as one
    /// card with its progress ring and the next item to do. It opens the checklist. Left out when
    /// no checklist has been started here (the Tools grid starts one).
    @ViewBuilder private func checklistCard(_ job: JobRecord) -> some View {
        if let run = JobChecklistStore.run(jobID: job.id, session: session),
           let template = ChecklistTemplates.template(run.templateID), !template.items.isEmpty {
            let done = run.doneCount(template)
            let total = template.items.count
            let next = template.items.first(where: { !run.done.contains($0.id) })
            Button { showChecklist = true } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().stroke(Theme.foreground.opacity(0.12), lineWidth: 3)
                        Circle().trim(from: 0, to: CGFloat(done) / CGFloat(total))
                            .stroke(Theme.brandText, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 22, height: 22)
                    .padding(3)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Checklist \u{00B7} \(done) of \(total)")
                            .font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(next.map { "Next: \($0.label)" } ?? "All done")
                            .font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    PaperIcon(.jobChevronRight, size: 16, color: Theme.muted).frame(width: 24, height: 24)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .panelBackground(cornerRadius: Theme.cardRadius)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens this visit's checklist")
            .accessibilityIdentifier("job-checklist-card")
        }
    }

    /// Paper 21's Details rows: the label on the left in the marker grey, the value right-aligned
    /// at 15 Medium, an optional mark after it. At accessibility sizes the value reads under its label.
    private func detailValueRow(_ label: String, value: String, valueColor: Color = Theme.foreground,
                                glyph: PaperGlyph? = nil, symbolColor: Color = Theme.borderStrong) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                             : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return HStack(spacing: 12) {
            layout {
                Text(label).font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: !stacked, vertical: true)
                Text(value).font(Theme.font(15, weight: .medium)).foregroundStyle(valueColor)
                    .multilineTextAlignment(stacked ? .leading : .trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: stacked ? .leading : .trailing)
            }
            if let glyph { PaperIcon(glyph, size: 16, color: symbolColor) }
        }
        .padding(.leading, 16).padding(.trailing, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func customerRow(_ job: JobRecord, name: String, opens: Bool) -> some View {
        detailValueRow("Customer", value: name, glyph: opens ? .jobUpDown : nil)
            // The name leads what is spoken, as it led the row before.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
    }

    /// The job's own address in full, when its place is on file; else the street the header shows.
    private func detailsAddress(_ job: JobRecord) -> String? {
        if let locationID = job.locationId, let place = customerLocations.first(where: { $0.id == locationID }) {
            let address = place.address.trimmingCharacters(in: .whitespacesAndNewlines)
            if !address.isEmpty { return address }
        }
        return street(job)
    }

    /// Directions to the job's own place. No site is inferred: only a place the job records.
    private func jobDirectionsURL(_ job: JobRecord) -> URL? {
        guard let locationID = job.locationId else { return nil }
        return JobLocationPolicy.directions(for: locationID, in: customerLocations)
    }

    /// Paper 21 "Trane XR14 · 2019": the equipment on file at the job's place (the customer's, when
    /// the job records no place), with how many more there are.
    private func equipmentLine(_ job: JobRecord) -> String? {
        let owned = equipment.filter { $0.customerId == job.customerId }
        let here = job.locationId == nil ? owned : owned.filter { $0.locationId == job.locationId }
        guard let first = here.first else { return nil }
        let model = [first.brand, first.model].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        var parts = [model.isEmpty ? first.name : model]
        if let installed = first.installedOn, installed.count >= 4 { parts.append(String(installed.prefix(4))) }
        let line = parts.joined(separator: " \u{00B7} ")
        return here.count > 1 ? "\(line) + \(here.count - 1) more" : line
    }

    /// "Residential · 2 jobs". Membership is said once, in the header's property chips.
    private func customerDetail(_ job: JobRecord) -> String? {
        let current = customerContext(job) != nil && customerContext(job) == contactsContext
        var parts: [String] = []
        if let account = JobCustomerSection.detail(accountType: current ? customerRecord?.accountType : nil,
                                                   jobCount: session.can("job.view", feature: "jobs")
                                                       ? store.jobs.filter { $0.customerId == job.customerId }.count : nil) {
            parts.append(account)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The first photos of the visit, "+N" for the rest; Add photo opens the camera.
    @ViewBuilder
    private func photosStrip(_ job: JobRecord) -> some View {
        let count = liveMediaCountContext != nil && liveMediaCountContext == mediaCountContext ? mediaCount : nil
        let photos = count == nil ? [] : mediaPhotos
        let canAdd = session.can("job.edit", feature: "jobs")
        let showsMore = photos.count > 4 || mediaHasMore
        let shown = Array(photos.prefix(showsMore ? 3 : 4))
        VStack(alignment: .leading, spacing: 8) {
            JobPanelLabel(title: "Photos", count: count,
                          actionTitle: canAdd ? "Add photo" : nil, actionIdentifier: "job-add-photo",
                          action: { openCapture(.camera(stage: nil)) })
            if photos.isEmpty {
                Button { openPhotos() } label: {
                    JobPanel {
                        JobPanelRow(title: count == nil ? "Photos and documents" : "No photos yet",
                                    subtitle: "Before and after photos, scans and measurements", titleSize: 15)
                    }
                }
                .buttonStyle(PressStyle())
                .accessibilityHint("Opens the job's photos")
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(shown) { photo in
                        Button { openPhotos() } label: { photoTile(photo) }
                            .buttonStyle(PressStyle())
                            .accessibilityLabel(photo.caption ?? "Photo")
                    }
                    if showsMore {
                        Button { openPhotos() } label: {
                            Theme.fill
                                .aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    Text(mediaHasMore ? "More" : "+\(photos.count - shown.count)")
                                        .font(Theme.monoFont(14, weight: .medium)).foregroundStyle(Theme.foreground)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("All photos")
                    }
                }
            }
        }
        .accessibilityIdentifier("job-photos-strip")
    }

    private func photoTile(_ photo: MediaAssetRecord) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(MediaThumbnail(record: photo))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if let stage = photo.tags.first(where: { $0 == "Before" || $0 == "After" }) {
                    Text(stage).font(Theme.font(11, weight: .medium)).foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.card.opacity(0.9), in: Capsule())
                        .padding(5)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border.opacity(0.6), lineWidth: 1))
    }

    /// The two newest things on the visit; "See all" opens Activity.
    private func latestActivity(_ job: JobRecord) -> some View {
        // Paper 21 "Activity": the newest entry, "Show 9 activity items" in the brand tone, then
        // the oldest, in one card with hairlines between. Two entries or fewer are all shown.
        let entries = timeline(job, filter: "All")
        let hidden = max(0, entries.count - 2)
        let shown: [TimelineEntry] = entries.count > 2 ? [entries[0], entries[entries.count - 1]] : entries
        return JobPanelSection(title: "Activity") {
            if entries.isEmpty {
                JobPanelRow(title: "Nothing yet", subtitle: "Notes, status changes and photos show up here.", titleSize: 15)
            }
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in
                latestActivityRow(entry)
                if index == 0, hidden > 0 { showAllActivityRow(hidden) }
            }
        }
    }

    /// Paper 21's Activity rows: an 8pt dot, then what happened and when on one 15pt line
    /// ("Ramon marked Driving · 24 min ago"), 56 tall. The row opens Activity.
    private func latestActivityRow(_ entry: TimelineEntry) -> some View {
        let when = Calendar.current.isDateInToday(entry.date) && Date().timeIntervalSince(entry.date) < 3600 && Date() >= entry.date
            ? "\(max(1, Int(Date().timeIntervalSince(entry.date) / 60))) min ago" : timeLabel(entry.date, showsDay: true)
        return Button { activityFilter = "All"; withMotion(.snappy) { selectedTab = "Activity" } } label: {
            HStack(spacing: 12) {
                Circle().fill(Theme.borderStrong).frame(width: 8, height: 8).frame(width: 20)
                Text("\(entry.title) \u{00B7} \(when)")
                    .font(Theme.font(15)).foregroundStyle(Theme.subtle)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel("\(entry.title), \(when)")
        .accessibilityHint("Opens Activity")
    }

    /// Paper 21 "Show 9 activity items": opens Activity with everything showing.
    private func showAllActivityRow(_ hidden: Int) -> some View {
        Button { activityFilter = "All"; withMotion(.snappy) { selectedTab = "Activity" } } label: {
            HStack(spacing: 12) {
                PaperIcon(.jobDotsVertical, size: 16, color: Theme.muted).frame(width: 20)
                Text("Show \(hidden) activity \(hidden == 1 ? "item" : "items")")
                    .font(Theme.font(15, weight: .medium))
                    .foregroundStyle(Theme.brandText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityHint("Opens Activity")
        .accessibilityIdentifier("job-latest-activity-all")
    }

    /// The job's estimates and invoices with their status words; Open goes to Money.
    @ViewBuilder
    private func moneyPanel(_ job: JobRecord) -> some View {
        let canEstimates = session.can("estimate.view", feature: "estimates")
        let canInvoices = session.can("invoice.view", feature: "invoicing")
        if canEstimates || canInvoices {
            let estimates = canEstimates ? jobEstimates : []
            let bills = canInvoices ? invoices : []
            let loading = (canEstimates && !estimatesLoaded) || (canInvoices && !invoicesLoaded)
            JobPanelSection(title: "Money", actionTitle: "Open", actionIdentifier: "job-money-open",
                            action: { withMotion(.snappy) { selectedTab = "Money" } }) {
                ForEach(estimates) { estimate in
                    let options = estimate.options ?? []
                    let (word, tint) = estimateWord(estimate.status)
                    Button { openOverviewEstimate(estimate, job: job) } label: {
                        moneyLine(options.isEmpty ? "Estimate EST-\(estimate.id.suffix(4).uppercased())" : "Estimate · \(options.count) \(options.count == 1 ? "option" : "options")",
                                  amount: options.isEmpty ? paperLinesTotal(estimate.lines).map { jobShortMoney($0, currency: estimate.lines.first?.unitPrice.currency ?? "USD") } : nil,
                                  word: word, tint: tint)
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityHint("Opens this estimate")
                    .accessibilityIdentifier("job-overview-estimate-\(estimate.id)")
                    .disabled(estimateRead?.freshIDs.contains(estimate.id) != true || overviewEstimatesAuthority?.isCurrent(api: api, session: session) != true)
                }
                ForEach(bills) { invoice in
                    let due = TechJobFlow.due(invoice)
                    let (word, tint) = invoiceWord(invoice, due: due)
                    let amount = invoice.status == "issued" ? due : paperLinesTotal(invoice.lines)
                    Button {
                        openOverviewInvoice(invoice, job: job)
                    } label: {
                        moneyLine("Invoice \(jobInvoiceReference(invoice.id))",
                                  amount: amount.map { jobShortMoney($0, currency: invoice.currency) }, word: word, tint: tint)
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityHint("Opens this invoice")
                    .accessibilityIdentifier("job-overview-invoice-\(invoice.id)")
                    .disabled(invoiceRead?.freshIDs.contains(invoice.id) != true || overviewInvoicesAuthority?.isCurrent(api: api, session: session) != true)
                }
                if estimates.isEmpty && bills.isEmpty {
                    if loading { SkeletonRows(count: 1, leading: false, inset: 16) }
                    else { JobPanelRow(title: "No estimates or invoices yet", titleSize: 15) }
                }
                if let balance = invoiceBalanceCents, balance > 0 {
                    // What is owed now, in the type colour; it opens Money.
                    Button { withMotion(.snappy) { selectedTab = "Money" } } label: {
                        let amount = Text(jobShortMoney(balance, currency: "USD")).font(Theme.monoFont(15, weight: .medium))
                            .foregroundStyle(Theme.foreground)
                        Group {
                            if typeSize.isAccessibilitySize {
                                // The amount reads under the label, as in `moneyLine`: side by side it
                                // broke mid-number ("$340.0" over "0").
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Due on site").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                                        .fixedSize(horizontal: false, vertical: true)
                                    amount
                                }
                            } else {
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text("Due on site").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                                    Spacer(minLength: 8)
                                    amount
                                }
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityLabel("\(money(balance, currency: "USD"))\u{00A0}due")
                    .accessibilityHint("Opens Money")
                    .accessibilityIdentifier("job-chip-amount")
                }
            }
        }
    }

    private func moneyLine(_ label: String, amount: String?, word: String, tint: StatusTone) -> some View {
        // At accessibility sizes the amount and word read under the label; side by side the fixed
        // amount ran past the panel's edge.
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                             : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            Text(label).font(Theme.font(15)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if !stacked { Spacer(minLength: 8) }
            // v2: the amount, then the status as a word with its small mark (colour beside the word).
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let amount { Text(amount).font(Theme.monoFont(15)).foregroundStyle(Theme.foreground) }
                StatusLabel(tone: tint, word: word, emphasis: .quiet)
            }
            .fixedSize(horizontal: !stacked, vertical: true)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .frame(maxWidth: stacked ? .infinity : nil, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// The estimate's word and mark as its own page and the lists show them (`DocumentStatus`).
    private func estimateWord(_ status: String) -> (String, StatusTone) {
        let document = DocumentStatus(estimateStatus: status)
        return (document.word, document.tone)
    }

    /// The invoice's word and mark as its own page and the lists show them; an issued invoice with
    /// nothing left to collect still reads "Issued".
    private func invoiceWord(_ invoice: InvoiceRecord, due: Int?) -> (String, StatusTone) {
        if invoice.status == "issued", invoice.amountPaid == 0, (due ?? 0) <= 0 { return ("Issued", .unscheduled) }
        let document = DocumentStatus(invoice: invoice)
        return (document.word, document.tone)
    }

    /// Open follow-ups, waiting on the office; Open goes to the follow-ups screen.
    private var followUpsPanel: some View {
        let open = (followUps ?? []).filter { $0.status == "open" }
        return JobPanelSection(title: "Follow-ups", count: open.isEmpty ? nil : "\(open.count)", actionTitle: "Open",
                               actionIdentifier: "job-follow-ups-open",
                               action: { followUpKind = .notifyOffice; showFollowUps = true }) {
            if open.isEmpty {
                JobPanelRow(title: followUps == nil ? "Follow-ups" : "None open",
                            subtitle: "Ask the office for a callback or a return visit.", titleSize: 15)
            }
            ForEach(open) { record in
                Button { followUpKind = .notifyOffice; showFollowUps = true } label: {
                    JobPanelRow(title: record.reason, subtitle: "Next: \(record.nextAction)", titleSize: 15) {
                        Text("Office").font(Theme.font(13)).foregroundStyle(Theme.muted)
                    }
                }
                .buttonStyle(RowPressStyle())
            }
        }
    }

    // MARK: On site (OnSite.dc.html)

    /// Everything a technician reaches for at the house, one tap each. Capture tools open the
    /// job's media screen straight into the camera, scanner or measure; the rest open their screens.
    private func toolkit(_ job: JobRecord, working: Bool = false) -> some View {
        let canCapture = session.can("job.edit", feature: "jobs")
        // Four across at standard sizes; three once words like "Return visit" stop fitting a quarter
        // of the row; two at accessibility sizes so every word stays whole.
        let columns = typeSize.isAccessibilitySize ? 2 : typeSize >= .xLarge ? 3 : 4
        return VStack(alignment: .leading, spacing: 8) {
        JobPanelLabel(title: "Tools")
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: columns), spacing: 8) {
            // Paper F4: with the work started, Photo, the note, parts and the checklist are the
            // capture tiles above (`captureTiles`), so they aren't repeated here.
            if !working {
                JobToolTile(title: "Photo", symbol: "camera", enabled: canCapture && UIImagePickerController.isSourceTypeAvailable(.camera),
                            hint: "Opens the camera and adds the photo to this job") { openCapture(.camera(stage: nil)) }
                JobToolTile(title: "Note", symbol: "square.and.pencil", enabled: session.can("job.note", feature: "jobs"),
                            hint: "Type or dictate a note") { openNoteTool() }
            }
            JobToolTile(title: "Measure", symbol: "ruler", enabled: canCapture && SiteMeasure.isSupported,
                        hint: "Measure with the camera and add it as a photo") { openCapture(.measure) }
            // The equipment data plate; the document scanner stays in Photos' add-a-document menu.
            JobToolTile(title: "Scan tag", symbol: "barcode.viewfinder", enabled: canCapture,
                        hint: "Reads the equipment's data plate into the customer's equipment") { showScan = true }
            if !working {
                JobToolTile(title: "Checklist", symbol: "checklist", hint: "Opens this visit's checklist") { showChecklist = true }
                JobToolTile(title: "Add part", symbol: "shippingbox", enabled: canAddPart,
                            hint: "Adds price book items to the job's draft invoice") { Task { await addPart() } }
            }
            JobToolTile(title: "Estimate", symbol: "doc.text",
                        enabled: canBuildEstimate || session.can("estimate.view", feature: "estimates"),
                        hint: jobEstimates.isEmpty ? "Builds an estimate" : "Opens the job's estimates") { openEstimateTool() }
            JobToolTile(title: "Return visit", symbol: "calendar.badge.plus", enabled: session.can("job.edit", feature: "jobs"),
                        hint: "Asks the office to book a return visit") { followUpKind = .officeScheduling; showFollowUps = true }
        }
        .accessibilityIdentifier("job-toolkit")
        }
    }

    // MARK: Working (Paper F4)

    /// Paper F4 "Working (capture)": the on-site timer with Pause, the four capture tiles, then
    /// what the tech wrote down last. 16 apart, as Paper spaces them.
    private func workingLead(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            onSiteTimerCard(job)
            captureTiles(job)
            whatYouFound(job)
        }
    }

    /// Paper F4's timer card: "On site" over the time since the arrival tap at 34 Bold, counting
    /// by the second, and Pause as a brand-surface pill. Pause opens the same pause sheet as the
    /// menu, and shows only when the server allows the move. The count runs from the arrival tap,
    /// never from the schedule; a missing tap is named.
    private func onSiteTimerCard(_ job: JobRecord) -> some View {
        let since = JobFiltering.date(job.arrivedAt) ?? JobFiltering.date(job.startedAt)
        let queued = outbox.pendingStatus(for: job.id) != nil
        let canPause = availableTransitions(job).contains("paused")
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                                                  : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            VStack(alignment: .leading, spacing: 0) {
                Text("On site").font(Theme.font(14)).foregroundStyle(Theme.muted)
                if let since {
                    TimelineView(.periodic(from: since, by: 1)) { context in
                        Text(JobOnSiteClock.timer(arrived: since, now: context.date))
                            .font(Theme.font(34, weight: .bold)).tracking(-0.68).monospacedDigit()
                            .foregroundStyle(Theme.foreground)
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .accessibilityLabel(JobHours.duration(context.date.timeIntervalSince(since)))
                    }
                } else {
                    Text(queued ? "Waiting to sync" : "Arrival not recorded")
                        .font(Theme.font(17, weight: .semibold)).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("job-on-site-timer")
            if canPause {
                Button { runTransition("paused") } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "pause").font(.system(size: 15, weight: .bold))
                            .accessibilityHidden(true)
                        Text("Pause").lineLimit(1)
                    }
                    .paperButton(.card, tone: .tinted)
                }
                .buttonStyle(PressStyle())
                .disabled(busy)
                .accessibilityLabel("Pause job")
                .accessibilityHint("Asks why, and when to come back")
                .accessibilityIdentifier("job-pause")
            }
        }
        .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelBackground(cornerRadius: Theme.cardRadius)
    }

    /// Paper F4's capture tiles, two by two: Photo, Voice note, Part or labor, Checklist. Each
    /// opens what the Tools grid opened for it; the line under the word is what the job already
    /// has. At accessibility sizes they stack so every word stays whole.
    private func captureTiles(_ job: JobRecord) -> some View {
        let canCapture = session.can("job.edit", feature: "jobs")
        let row = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                                               : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return VStack(alignment: .leading, spacing: 12) {
            row {
                JobCaptureTile(title: "Photo", symbol: "camera", detail: photoTileDetail,
                               enabled: canCapture && UIImagePickerController.isSourceTypeAvailable(.camera),
                               hint: "Opens the camera and adds the photo to this job",
                               identifier: "job-tool-photo") { openCapture(.camera(stage: nil)) }
                JobCaptureTile(title: "Voice note", symbol: "mic", detail: "Say what you found",
                               enabled: session.can("job.note", feature: "jobs"),
                               hint: "Opens the note and starts listening",
                               identifier: "job-tool-note") { openVoiceNote() }
            }
            .fixedSize(horizontal: false, vertical: true)
            row {
                JobCaptureTile(title: "Part or labor", symbol: "plus.square", detail: partsTileDetail,
                               enabled: canAddPart,
                               hint: "Adds price book items to the job's draft invoice",
                               identifier: "job-tool-add-part") { Task { await addPart() } }
                JobCaptureTile(title: "Checklist", symbol: "checkmark.circle", detail: checklistTileDetail(job),
                               hint: "Opens this visit's checklist",
                               identifier: "job-tool-checklist") { showChecklist = true }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "4 added": the visit's photos on the first page read, plus any still on this phone.
    private var photoTileDetail: String {
        guard liveMediaCountContext != nil, liveMediaCountContext == mediaCountContext, mediaCount != nil else {
            return "Add to this job"
        }
        let waiting = pendingMedia.items.filter { $0.jobID == jobId && $0.kind == "photo" }.count
        let total = mediaPhotos.count + waiting
        if total == 0 { return "None yet" }
        return "\(total)\(mediaHasMore ? "+" : "") added"
    }

    /// "2 items · $340.00": what is on the job's bill so far (the draft, else the completion invoice).
    private var partsTileDetail: String {
        guard session.can("invoice.view", feature: "invoicing"),
              let bill = invoices.first(where: { $0.status == "draft" }) ?? WrapUpList.billingInvoice(invoices),
              !bill.lines.isEmpty else { return "From the price book" }
        let count = bill.lines.count
        let items = "\(count) \(count == 1 ? "item" : "items")"
        guard let total = paperLinesTotal(bill.lines) else { return items }
        return "\(items) \u{00B7} \(money(total, currency: bill.currency))"
    }

    /// "5 of 8 done" for the checklist under way on this phone.
    private func checklistTileDetail(_ job: JobRecord) -> String {
        guard let run = JobChecklistStore.run(jobID: job.id, session: session),
              let template = ChecklistTemplates.template(run.templateID), !template.items.isEmpty else {
            return "Start one for this visit"
        }
        return "\(run.doneCount(template)) of \(template.items.count) done"
    }

    /// Paper F4 "What you found": this person's latest note on the job at 17 Medium. It opens the
    /// notes. Paper's "Drafted from your voice note" line is left out: a note doesn't record how
    /// it was written. Nothing shows until there is a note.
    @ViewBuilder private func whatYouFound(_ job: JobRecord) -> some View {
        let mine = notes.filter { $0.jobId == job.id && $0.authorUserId == session.user?.id }
        if let latest = mine.max(by: { $0.createdAt < $1.createdAt }) {
            VStack(alignment: .leading, spacing: 8) {
                JobPanelLabel(title: "What you found")
                Button { openNoteTool() } label: {
                    Text(latest.body)
                        .font(Theme.font(17, weight: .medium)).lineSpacing(2)
                        .foregroundStyle(Theme.foreground)
                        .multilineTextAlignment(.leading)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 6)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
                        .panelBackground(cornerRadius: Theme.cardRadius)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityHint("Opens the job's notes")
                .accessibilityIdentifier("job-what-you-found")
            }
        }
    }

    /// The Voice note tile: Activity's note field, already listening. What is heard only fills the
    /// draft; saving still goes through the note's own Save.
    private func openVoiceNote() {
        activityFilter = "All"
        withMotion(.snappy) { selectedTab = "Activity" }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard selectedTab == "Activity", !dictation.isListening else { return }
            // Paper F4A: the recording shows on its own sheet; the words still fill the note draft.
            voiceNoteBefore = note
            voiceNoteDiscarded = false
            voiceNoteStarted = Date()
            await dictation.start(draft: note, isOffline: session.isOffline) { note = $0 }
            // No microphone or speech access: the note field says so and offers Settings.
            if dictation.isListening { showVoiceNote = true }
        }
    }

    /// Photos filed under a stage: the visit's first page from the server plus any still on this
    /// phone. Nil while unknown (not read yet, or none on the first page of a longer list).
    private func stagedPhotoCount(_ tag: String) -> Int? {
        guard mediaCount != nil else { return nil }
        let stored = mediaPhotos.filter { $0.tags.contains(tag) }.count
        let waiting = pendingMedia.items.filter { $0.jobID == jobId && $0.kind == "photo" && $0.tags.contains(tag) }.count
        if stored + waiting == 0, mediaHasMore { return nil }
        return stored + waiting
    }

    /// OnSite.dc.html "Before you wrap up": one list for the panel and the bar's count.
    private var wrapUpRows: [WrapUpRow] {
        let canViewInvoices = session.can("invoice.view", feature: "invoicing")
        return WrapUpList.rows(.init(
            beforePhotos: stagedPhotoCount("Before"),
            afterPhotos: stagedPhotoCount("After"),
            estimates: estimatesLoaded && !estimatesFailed ? jobEstimates : nil,
            invoices: canViewInvoices && invoicesLoaded && !invoicesFailed ? invoices : nil,
            closeout: closeout))
    }

    /// "Before you wrap up · 3 of 6", each open row one tap from what completes it. Wrap up itself
    /// is the bar below, and the closeout screen stays in •••.
    @ViewBuilder
    private func wrapUpPanel(_ job: JobRecord) -> some View {
        let rows = wrapUpRows
        if !rows.isEmpty {
            JobPanelSection(title: "Before you wrap up", count: "\(rows.count - WrapUpList.left(rows)) of \(rows.count)") {
                ForEach(rows) { row in
                    Button { openWrapUpRow(row) } label: {
                        // v2: the row's state is a word with its mark ("Done" / "To do"), not a tick's colour.
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            (Text(row.title).font(Theme.font(15)).foregroundStyle(row.done ? Theme.subtle : Theme.foreground)
                             + Text(row.detail.map { "  \($0)" } ?? "").font(Theme.monoFont(14)).foregroundStyle(Theme.muted))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            StatusLabel(tone: row.done ? .done : .unscheduled, word: row.done ? "Done" : "To do",
                                        emphasis: row.done ? .quiet : .strong)
                                .fixedSize()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel([row.title, row.detail].compactMap { $0 }.joined(separator: ", "))
                    .accessibilityValue(row.done ? "Done" : "To do")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("job-wrap-up-\(row.id)")
                }
            }
            .accessibilityIdentifier("job-wrap-up-panel")
        }
    }

    /// What's on the job's bill so far (the draft, else the completion invoice); Add opens the
    /// price book on a draft. Lines don't say which are parts or where they came from (BYR-1599).
    @ViewBuilder private var partsPanel: some View {
        if session.can("invoice.view", feature: "invoicing"),
           let bill = invoices.first(where: { $0.status == "draft" }) ?? WrapUpList.billingInvoice(invoices), !bill.lines.isEmpty {
            let editable = bill.status == "draft" && session.can("invoice.edit", feature: "invoicing")
            let count = bill.lines.count
            // Paper 21 "Line items": the count at the label's trailing edge, "Add from price book or
            // custom" as its own 48pt row, the lines in one card (the line at 16 Medium over its
            // quantity and price), then the total in a card of its own at 22 Bold. Quantities are
            // changed in the invoice's editor, which the add row opens.
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Line items")
                        .font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Text("\(count) \(count == 1 ? "item" : "items")")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 4)
                if editable {
                    Button { partsInvoice = bill } label: {
                        HStack(spacing: 8) {
                            PaperIcon(.plusLight, size: 18, color: Theme.brandText)
                            Text("Add from price book or custom")
                                .font(Theme.font(16)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityIdentifier("job-parts-add")
                }
                JobPanel {
                    ForEach(bill.lines) { line in
                        lineItemRow(line, edit: editable ? { partsInvoice = bill } : nil)
                    }
                }
                if let total = paperLinesTotal(bill.lines) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Total").font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                        Spacer(minLength: 8)
                        Text(money(total, currency: bill.currency))
                            .font(Theme.font(22, weight: .bold)).monospacedDigit().tracking(-0.44)
                            .foregroundStyle(Theme.foreground)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panelBackground(cornerRadius: Theme.cardRadius)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("job-parts-total")
                }
            }
        }
    }

    /// Paper 21: one line of the job's bill. The line at 16 Medium over "2 × $185.00" at 14, its
    /// amount on the right. One VoiceOver stop per line.
    private func lineItemRow(_ line: FieldLine, edit: (() -> Void)? = nil) -> some View {
        // Paper 21: the line at 16 Medium over where it came from and its price each ("Price book ·
        // $185.00"), then the quantity on a 44pt capsule between Remove and Add. Quantities are
        // changed in the invoice's line editor, so the capsule opens it.
        let each = money(line.unitPrice.amount, currency: line.unitPrice.currency)
        let amount = JobInvoiceLineRows.amount(line).map { money($0, currency: line.unitPrice.currency) }
        let source = line.source?.priceBookItemId != nil ? "Price book" : "Custom"
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(line.description).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(source) \u{00B7} \(each)").font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(line.description), quantity \(line.quantity)\(amount.map { ", \($0)" } ?? "")")
            if let edit {
                Button(action: edit) {
                    HStack(spacing: 0) {
                        PaperIcon(.jobTrash, size: 16, color: Theme.destructive).frame(width: 44, height: 44)
                        Text("\(line.quantity)").font(Theme.font(15, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(Theme.foreground).frame(minWidth: 18)
                        PaperIcon(.jobStepPlus, size: 14, color: Theme.foreground).frame(width: 44, height: 44)
                    }
                    .background(Theme.quietFill, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Quantity \(line.quantity)")
                .accessibilityHint("Opens the line editor to change or remove this line")
            } else {
                Text("\(line.quantity)").font(Theme.font(15, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.foreground)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Theme.quietFill, in: Capsule())
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Each wrap-up row goes where its fact is made; a done row opens it to look again.
    private func openWrapUpRow(_ row: WrapUpRow) {
        if !row.done { wrapUpTapArmed = true }
        let bill = WrapUpList.billingInvoice(invoices)
        switch row.step {
        case .beforePhotos: row.done ? openPhotos() : openCapture(.camera(stage: "Before"))
        case .afterPhotos: row.done ? openPhotos() : openCapture(.camera(stage: "After"))
        case .diagnosisNote: openNoteTool()
        case .approval:
            if !row.done, let step = nextStep {
                switch step {
                case .showEstimate, .presentEstimates: run(step); return
                default: break
                }
            }
            withMotion(.snappy) { selectedTab = "Money" }
        case .signature:
            // The signature is taken on the invoice, which holds its lines revision.
            if let bill { documentInvoiceID = bill.id } else { Task { if let created = await createInvoice() { documentInvoiceID = created.id } } }
        case .payment:
            guard let bill else { run(.createInvoice); return }
            if bill.status == "draft" { reviewInvoiceID = bill.id; return }
            if !row.done, let due = TechJobFlow.due(bill), due > 0, session.can("invoice.payment.create", feature: "payments") {
                run(.collect(invoiceID: bill.id, due: due, currency: bill.currency))
            } else {
                reviewInvoiceID = bill.id
            }
        case .server(let item):
            if item.done || item.kind == "acknowledgement" { showWrapUp = true } else { openCloseoutItem(item) }
        }
    }

    /// Routes a server closeout rule to what satisfies it, by its next action, then its kind.
    private func openCloseoutItem(_ item: CloseoutChecklistItem) {
        switch item.nextAction {
        case "add_job_note": openNoteTool()
        case "add_job_photo": openCapture(.camera(stage: nil))
        default:
            switch item.kind {
            case "notes": openNoteTool()
            case "photos": openCapture(.camera(stage: nil))
            default: showWrapUp = true
            }
        }
    }

    /// Add part works on the job's draft invoice; an issued one can't change, so it opens instead.
    private var canAddPart: Bool {
        guard invoicesLoaded, !invoicesFailed, session.can("invoice.view", feature: "invoicing") else { return false }
        let live = invoices.filter { $0.status != "void" }
        if live.contains(where: { $0.status == "draft" }) { return session.can("invoice.edit", feature: "invoicing") }
        if !live.isEmpty { return true }
        return session.can("invoice.create", feature: "invoicing") && session.can("invoice.edit", feature: "invoicing")
    }

    private func addPart() async {
        let live = invoices.filter { $0.status != "void" }
        if let draft = live.first(where: { $0.status == "draft" }) { partsInvoice = draft; return }
        if let existing = live.first(where: { $0.origin == "job_completion" }) ?? live.first { documentInvoiceID = existing.id; return }
        // No invoice yet: the job's completion draft, through the same idempotent command as Create invoice.
        guard let created = await createInvoice() else { return }
        if created.status == "draft" { partsInvoice = created } else { documentInvoiceID = created.id }
    }

    private func openEstimateTool() {
        if jobEstimates.isEmpty && canBuildEstimate { buildEstimate() }
        else { withMotion(.snappy) { selectedTab = "Money" } }
    }

    private func detailsGroup(_ job: JobRecord) -> some View {
        JobPanel(dividers: false) {
        VStack(alignment: .leading, spacing: 0) {
            // The visit's time and the job number are said once, in the header (chip and eyebrow).
            DisclosureGroup {
                if let created = JobFiltering.date(job.createdAt) {
                    PaperDetailRow("Booked", value: created.formatted(.dateTime.month(.abbreviated).day().year()))
                }
                // JH-02: drive and on-site time from the visit steps, live each minute while open (JH-04).
                TimelineView(.everyMinute) { context in
                    if let hours = JobHours.make(job, now: context.date) {
                        PaperDetailRow(label: "Time") {
                            Text(hours.line).font(hours.hasDuration ? Theme.monoFont(15, weight: .medium) : Theme.font(15, weight: .medium))
                        }
                    }
                }
            } label: {
                // The whole row toggles, 44pt tall; the bare title was a 25pt target.
                Text("More job details")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .font(Theme.font(15, weight: .medium))
            .tint(Theme.foreground)
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        }
    }

    /// Money: the job's estimates, then its invoices. Each paper shows its own amount once; what's
    /// owed across them is on Overview and in the bar, never repeated in a header.
    private func moneyContent(_ job: JobRecord) -> some View {
        // Paper 23 and 24: what the estimates add up to, the estimates in one card, then the
        // invoices; 22 between the sections.
        VStack(alignment: .leading, spacing: 22) {
            estimatesContent(job)
            invoiceContent(job)
        }
    }

    /// Paper 23 "Estimates": the totals card (waiting on the customer, approved, "Build an
    /// estimate"), then every estimate as a row of one card, "Add an estimate" as its last row.
    private func estimatesContent(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !session.can("estimate.view", feature: "estimates") {
                PaperEmptyState(symbol: "lock", title: "Estimates are off for your role", message: "Ask your office for access to estimates.")
            } else {
                let unavailable = estimateRead?.unavailableIDs ?? []
                let count = jobEstimates.count + unavailable.count
                // Paper: the totals card sits 22 over the "Estimates" label.
                estimateSummaryCard.padding(.bottom, 14)
                // Paper 23: "Estimates · 3" with a brand plus at its trailing edge (said "Add estimate").
                JobPanelLabel(title: "Estimates", count: count > 1 ? "\(count)\(documents.canLoadMoreEstimates ? " loaded" : "")" : nil,
                              actionTitle: session.can("estimate.create", feature: "estimates") ? (preparingEstimate ? "Preparing…" : "Add estimate") : nil, actionSymbol: "plus",
                              actionIdentifier: "job-add-estimate", action: buildEstimate)
                if !estimatesLoaded && documents.estimatePageError == nil {
                    SkeletonRows(count: 2, leading: false, inset: 0)
                } else if estimateRead?.isComplete == true && count == 0 {
                    PaperEmptyState(symbol: "doc.text", title: "No estimates on this job",
                                    message: "Build one from the price book.")
                }
                if count > 0 { estimateRowsCard(unavailable) }
                if let error = documents.estimatePageError {
                    // The shared banner, in place of a loose line and a bare text button.
                    ErrorBanner(message: error,
                                action: !documents.canLoadMoreEstimates || documents.estimatePageNeedsRefresh
                                    ? ErrorBanner.Action(title: String(localized: "Try again")) { await loadJobEstimates(job) } : nil,
                                actionIdentifier: "job-retry-estimates", outer: 0)
                }
                if documents.canLoadMoreEstimates && !documents.estimatePageNeedsRefresh {
                    Button(documents.estimatePageError == nil ? "Load more estimates" : "Try loading estimates again") {
                        Task { await loadNextJobEstimates(job) }
                    }
                    .disabled(documents.loadingEstimatePage)
                    .accessibilityIdentifier("job-load-more-estimates")
                }
            }
        }
        .task(id: "\(job.id)|\(job.organizationId)|\(job.customerId)|\(job.estimateId ?? "")") {
            let target = scope(for: job)
            if !documents.isLoadingEstimates(for: target) &&
                (estimateRead?.scope != target || (!estimatesLoaded && documents.estimatePageError == nil)) {
                await loadJobEstimates(job)
            }
        }
    }

    /// Paper 23's totals card; nothing when no estimate has an amount to add up yet.
    @ViewBuilder private var estimateSummaryCard: some View {
        if let summary = JobEstimateSummary(records: jobEstimates, complete: estimateRead?.isComplete == true) {
            if canBuildEstimate {
                JobEstimateSummaryCard(summary: summary, onBuild: { buildEstimate() })
            } else {
                JobEstimateSummaryCard(summary: summary)
            }
        }
    }

    /// Paper 23: the job's estimates as rows of one card (status mark, title, "Sent · Waiting on
    /// customer", amount), then "Add an estimate" in brand text as the card's last row.
    private func estimateRowsCard(_ unavailable: [String]) -> some View {
        JobPanel {
            ForEach(jobEstimates) { estimate in
                NavigationLink { EstimateDetailView(id: estimate.id, jobID: jobId).thorbisBackButton() } label: {
                    JobDocumentRow(estimate: estimate, fresh: estimateRead?.freshIDs.contains(estimate.id) == true)
                        .asJobEstimateCard().onWell()
                }
                .buttonStyle(RowPressStyle())
                .accessibilityIdentifier("job-estimate-\(estimate.id)")
                .disabled(estimateRead?.freshIDs.contains(estimate.id) != true)
            }
            ForEach(unavailable, id: \.self) { id in
                JobDocumentRow(reference: "EST-\(id.suffix(4).uppercased())", title: "Estimate unavailable",
                               status: "unavailable", amount: nil, fresh: false).asJobEstimateCard().onWell()
                    // A container keeps the id on the row itself; without one it lands on each text.
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("job-estimate-unavailable-\(id)")
            }
            // The estimates' customer door (it was More › Show estimates): after the estimates it
            // hands over, before "Add an estimate".
            if !jobEstimates.isEmpty { showEstimatesRow }
            if canBuildEstimate { addEstimateRow }
        }
    }

    /// Paper 23: "Add an estimate", 56 tall, a brand plus in the status mark's column.
    private var addEstimateRow: some View {
        Button(action: buildEstimate) {
            HStack(spacing: 12) {
                PaperIcon(.jobPlus, size: 18, color: Theme.brandText).frame(width: 20)
                Text("Add an estimate").font(Theme.font(16, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.brandText)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityIdentifier("job-add-estimate-row")
    }

    /// "Show estimates": the job's estimates in the locked Customer view, as a row of Paper 23's
    /// estimates card (56 tall, its mark in the status column, the hint under the words).
    private var showEstimatesRow: some View {
        Button { openCustomerView(.estimates) } label: {
            HStack(spacing: 12) {
                Image(systemName: "iphone").font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Theme.foreground).frame(width: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Show estimates").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    Text("Hand the estimates to the customer").font(Theme.font(14)).foregroundStyle(Theme.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .disabled(!canOpenCustomerView)
        .opacity(canOpenCustomerView ? 1 : 0.4)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows this job's estimates to the customer")
        .accessibilityIdentifier("job-money-customer-view")
    }

    private func scope(for job: JobRecord) -> JobDocumentScope? {
        guard job.id == jobId, job.organizationId == session.activeOrganization?.id else { return nil }
        return JobDocumentScope(jobID: job.id, organizationID: job.organizationId,
                                customerID: job.customerId, originEstimateID: job.estimateId)
    }

    private func overviewDirectPaymentStep(_ job: JobRecord) -> TechJobStep? {
        guard session.can("job.view", feature: "jobs"), session.can("invoice.view", feature: "invoicing"),
              session.can("invoice.payment.create", feature: "payments"),
              overviewInvoicesAuthority?.isCurrent(api: api, session: session) == true,
              documentGeneration == session.generation, let scope = scope(for: job),
              let read = invoiceRead, read.scope == scope, read.unavailableIDs.isEmpty else { return nil }
        return JobInvoiceDirectPayment.singleStep(invoices: read.records, scope: scope, freshIDs: read.freshIDs,
                                                  isComplete: read.isComplete, canCollect: true)
    }

    private func collectOverviewInvoice(_ displayedStep: TechJobStep) async {
        guard case .collect = displayedStep, !overviewPaymentRefreshing, let job, overviewDirectPaymentStep(job) == displayedStep,
              let expectedScope = scope(for: job),
              let authority = CustomerHandoffExitAuthority.capture(api: api, session: session) else { return }
        overviewPaymentRefreshing = true
        var handedOff = false
        defer { if !handedOff { overviewPaymentRefreshing = false } }
        let generation = session.generation
        let navigationRevision = overviewNavigationRevision
        let current: @MainActor () -> Bool = {
            !Task.isCancelled && selectedTab == "Overview" && overviewNavigationRevision == navigationRevision &&
            authority.isCurrent(api: api, session: session) && session.generation == generation &&
            self.job.flatMap { scope(for: $0) } == expectedScope
        }
        let published = await documents.loadInvoices(scope: expectedScope, api: api, isCurrent: current)
        guard current() else { return }
        guard published else { withMotion(.snappy) { selectedTab = "Money" }; return }
        overviewInvoicesAuthority = authority
        guard let job = self.job, overviewDirectPaymentStep(job) == displayedStep else {
            withMotion(.snappy) { selectedTab = "Money" }
            return
        }
        handedOff = true
        run(displayedStep, current: current) { overviewPaymentRefreshing = false }
    }

    private func overviewDocumentIsCurrent(_ route: OverviewJobDocumentRoute) -> Bool {
        guard route.authority.isCurrent(api: api, session: session),
              documentGeneration == session.generation,
              session.can("job.view", feature: "jobs"), let job,
              scope(for: job) == route.scope else { return false }
        switch route.kind {
        case .estimate: return session.can("estimate.view", feature: "estimates")
        case .invoice: return session.can("invoice.view", feature: "invoicing")
        }
    }

    private func openOverviewEstimate(_ estimate: EstimateRecord, job: JobRecord) {
        guard session.can("job.view", feature: "jobs"), session.can("estimate.view", feature: "estimates"),
              overviewEstimatesAuthority?.isCurrent(api: api, session: session) == true,
              documentGeneration == session.generation, let scope = scope(for: job),
              let read = estimateRead, read.scope == scope, read.freshIDs.contains(estimate.id),
              scope.contains(estimate, requestedID: estimate.id),
              let authority = CustomerHandoffExitAuthority.capture(api: api, session: session) else { return }
        overviewDocument = OverviewJobDocumentRoute(documentID: estimate.id, kind: .estimate, scope: scope, authority: authority)
    }

    private func openOverviewInvoice(_ invoice: InvoiceRecord, job: JobRecord) {
        guard session.can("job.view", feature: "jobs"), session.can("invoice.view", feature: "invoicing"),
              overviewInvoicesAuthority?.isCurrent(api: api, session: session) == true,
              documentGeneration == session.generation, let scope = scope(for: job),
              let read = invoiceRead, read.scope == scope, read.freshIDs.contains(invoice.id),
              scope.contains(invoice),
              let authority = CustomerHandoffExitAuthority.capture(api: api, session: session) else { return }
        selectedInvoiceID = invoice.id
        overviewDocument = OverviewJobDocumentRoute(documentID: invoice.id, kind: .invoice, scope: scope, authority: authority)
    }

    private var documentReadIssue: String? {
        if estimateRead?.issue != nil && invoicesFailed { return "Couldn't load all estimates and invoices for this job." }
        return estimateRead?.issue ?? invoiceRead?.issue
    }

    private func loadJobEstimates(_ job: JobRecord) async {
        guard session.can("estimate.view", feature: "estimates"), let scope = scope(for: job),
              let authority = CustomerHandoffExitAuthority.capture(api: api, session: session) else {
            overviewEstimatesAuthority = nil
            documents.clearEstimates()
            return
        }
        let generation = session.generation
        let retain = overviewEstimatesAuthority?.isCurrent(api: api, session: session) == true && documentGeneration == session.generation
        let published = await documents.loadFirstEstimatePage(scope: scope, api: api, retainExisting: retain) {
            authority.isCurrent(api: api, session: session) && session.generation == generation && session.activeOrganization?.id == scope.organizationID &&
                self.job.flatMap { self.scope(for: $0) } == scope
        }
        guard session.generation == generation, authority.isCurrent(api: api, session: session), published else { return }
        overviewEstimatesAuthority = authority
    }

    private func loadNextJobEstimates(_ job: JobRecord) async {
        guard session.can("estimate.view", feature: "estimates"), let scope = scope(for: job),
              let authority = CustomerHandoffExitAuthority.capture(api: api, session: session) else { return }
        let generation = session.generation
        let published = await documents.loadNextEstimatePage(scope: scope, api: api) {
            authority.isCurrent(api: api, session: session) && session.generation == generation && session.activeOrganization?.id == scope.organizationID &&
                self.job.flatMap { self.scope(for: $0) } == scope
        }
        guard session.generation == generation, authority.isCurrent(api: api, session: session), published else { return }
        overviewEstimatesAuthority = authority
    }

    private func invoiceContent(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            #if DEBUG
            if PaperPreview.isJobDocumentsPreview, ProcessInfo.processInfo.arguments.contains("--paper-preview-create-invoice") {
                Text("Create requests: \(PaperPreviewProtocol.sampleCompletionCreates)")
                    .accessibilityIdentifier("preview-create-invoice-count")
                Text(creatingInvoice ? "Pending" : "Finished")
                    .accessibilityIdentifier("preview-create-invoice-state")
            }
            if previewOverviewPaymentHold {
                Text("Preview payment loading").accessibilityIdentifier("job-overview-payment-hold")
            }
            if PaperPreview.isJobDocumentsPreview,
               ProcessInfo.processInfo.arguments.contains("--paper-preview-overview-hold-reload") {
                Button("Preview revalidate") { Task { await session.revalidate() } }
                    .accessibilityIdentifier("job-overview-revalidate")
            }
            #endif
            if !session.can("invoice.view", feature: "invoicing") {
                emptyCard("Invoice access is unavailable.")
            } else if !invoicesLoaded {
                SkeletonRows(count: 3, leading: false, inset: 0)
            } else if invoices.isEmpty && !invoicesFailed {
                VStack(alignment: .leading, spacing: 8) {
                    JobPanelLabel(title: "Invoices")
                    if session.can("invoice.create", feature: "invoicing") || (job.estimateId != nil && session.can("invoice.create", feature: "progress_billing")) {
                        JobPanel {
                            if session.can("invoice.create", feature: "invoicing") {
                                Button { run(.createInvoice) } label: {
                                    PaperMenuRow(creatingInvoice ? "Creating…" : "Create invoice", symbol: "doc.plaintext",
                                                 subtitle: "Lines come from the approved estimate; edit them before sending")
                                        .padding(.horizontal, 16)
                                }
                                .buttonStyle(RowPressStyle())
                                .accessibilityIdentifier("job-create-invoice")
                                .disabled(creatingInvoice)
                            }
                            if job.estimateId != nil, session.can("invoice.create", feature: "progress_billing") {
                                Button { showDeposit = true } label: {
                                    PaperMenuRow("Request a deposit", symbol: "banknote", subtitle: "Bill part up front from the approved estimate")
                                        .padding(.horizontal, 16)
                                }
                                .buttonStyle(RowPressStyle())
                            }
                        }
                    }
                    if !session.can("invoice.create", feature: "invoicing") {
                        Text("No invoice yet").font(Theme.font(15)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    JobPanelLabel(title: "Invoices", count: invoices.count > 1 ? "\(invoices.count)" : nil)
                    // Paper 23 and 24: each invoice is a card of its own.
                    ForEach(invoices) { invoice in
                        invoiceCard(invoice, job: job)
                    }
                }
                // Paper 24 "Line items": the one invoice's lines, 22 under its card.
                if invoices.count == 1 { partsPanel.padding(.top, 7) }
                // Paper 24 "Payments": what has been paid on the invoice.
                invoicePaymentsSection.padding(.top, 7)
                // Paper 24 "Activity": the invoice's own trail (created, sent), when the job has one
                // invoice and this person may read it. The section stays out when the read is refused.
                if invoices.count == 1, let invoice = invoices.first, invoiceRead?.freshIDs.contains(invoice.id) == true {
                    RecordActivitySection(recordType: "invoice", recordID: invoice.id)
                }
            }
        }
    }

    /// The step that collects this invoice here, when it has a balance this person may take.
    private func directPaymentStep(_ invoice: InvoiceRecord, job: JobRecord) -> TechJobStep? {
        guard let scope = scope(for: job) else { return nil }
        return JobInvoiceDirectPayment.step(invoice: invoice, scope: scope, freshIDs: invoiceRead?.freshIDs ?? [],
                                            canCollect: session.can("invoice.payment.create", feature: "payments"))
    }

    /// Money's Collect payment pill. The payment details load first; the sheet opens only if the
    /// person is still on Money on this screen when they arrive, and the pills stay busy until then.
    private func collectFromMoney(_ step: TechJobStep) {
        guard case .collect = step else { run(step); return }
        guard !overviewPaymentRefreshing else { return }
        overviewPaymentRefreshing = true
        let navigationRevision = overviewNavigationRevision
        run(step, current: { selectedTab == "Money" && overviewNavigationRevision == navigationRevision }) {
            overviewPaymentRefreshing = false
        }
    }

    /// Paper 24: an invoice with a balance to collect is the balance card ("INV-2209 · Balance due",
    /// its status pill, the balance at 34 Bold, then Collect payment). Any other invoice is Paper
    /// 23's row (the reference over "Paid · $524.88", a chevron). Either opens the invoice; its
    /// lines and totals fold out under it.
    private func invoiceCard(_ invoice: InvoiceRecord, job: JobRecord) -> some View {
        let fresh = invoiceRead?.freshIDs.contains(invoice.id) == true
        let reference = jobInvoiceReference(invoice.id)
        let step = directPaymentStep(invoice, job: job)
        let due = step == nil ? nil : TechJobFlow.due(invoice)
        // The card opens the invoice only from a read made under the authority still in force, and
        // the opened invoice retires when the session or authority changes (as Overview's money rows did).
        let current = overviewInvoicesAuthority?.isCurrent(api: api, session: session) == true
        return JobPanel {
            Button {
                openOverviewInvoice(invoice, job: job)
            } label: {
                if let due {
                    JobInvoiceBalanceHeader(reference: reference,
                                            kind: invoice.origin == "estimate_deposit" ? "Deposit" : nil,
                                            status: invoice.status, amount: money(due, currency: invoice.currency))
                        .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 16)
                } else {
                    JobDocumentRow(invoice: invoice, fresh: fresh, invoiceReference: reference).onWell()
                }
            }
            .buttonStyle(RowPressStyle())
            .accessibilityIdentifier("job-invoice-\(invoice.id)")
            .disabled(!fresh || !current)
            .jobPanelJoinsNext(step != nil)
            if let step {
                // Paper 24: Collect payment is a brand-surface pill in the invoice's card.
                Button { collectFromMoney(step) } label: {
                    HStack(spacing: 8) {
                        PaperIcon(.jobCard, size: 18, color: Theme.brandText)
                        Text("Collect payment")
                    }
                    .paperButton(.card, tone: .tinted, fills: true)
                        .padding(.horizontal, 18).padding(.bottom, 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                // One invoice: "Collect payment", as Money's bar named it (which invoice is the hint).
                // Several: each pill names its invoice.
                .accessibilityLabel(invoices.count == 1 ? "Collect payment" : "Collect payment for invoice \(reference)")
                .accessibilityHint(invoices.count == 1 ? "For invoice \(reference)" : "")
                .accessibilityIdentifier("job-invoice-collect-\(invoice.id)")
                .disabled(overviewPaymentRefreshing)
            }
            if !invoice.lines.isEmpty, fresh, invoices.count > 1 {
                JobInvoiceItemsDisclosure(invoice: invoice, reference: reference, startsExpanded: false)
            }
        }
    }

    /// Paper 24 "Payments · 0" with its brand plus: the payments on the job's invoice, once its
    /// history is loaded. The plus collects, like the bar. A job with several invoices keeps each
    /// one's payments on its own screen, where the section can say which invoice it is about.
    @ViewBuilder private var invoicePaymentsSection: some View {
        if invoices.count == 1, let invoice = selectedInvoice, invoice.status != "draft",
           loadedInvoiceModelID == invoice.id, let model = invoicePaymentModel,
           invoiceRead?.freshIDs.contains(invoice.id) == true {
            InvoicePaymentsSection(model: model, invoice: invoice,
                                   onCollectPayment: { _ = presentPayment(for: invoice.id) },
                                   onInvoiceUpdated: { updateInvoice($0) },
                                   invoiceReference: jobInvoiceReference(invoice.id))
        }
    }

    private func jobInvoiceReference(_ id: String) -> String {
        JobInvoiceReferences.reference(for: id, among: invoices.map(\.id))
    }

    private var selectedInvoice: InvoiceRecord? {
        invoiceRead?.preferredInvoice(id: selectedInvoiceID)
    }

    private func updateInvoice(_ updated: InvoiceRecord) {
        documents.replaceInvoice(updated)
    }

    /// Paper 21B: the filters as one row of 40pt pills under the composer ("All", "Notes",
    /// "Photos", "Status", "Money"). The chosen one sits on the brand surface in brand text at 14
    /// Semibold; the rest on the card at 14 Medium. The row scrolls sideways when it can't fit.
    private var activityFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(activityFilters, id: \.self) { filter in
                    activityFilterChip(filter)
                }
            }
        }
        .scrollClipDisabled()
    }

    private func activityFilterChip(_ filter: String) -> some View {
        let isOn = filter == activityFilter
        return Button { withMotion(.snappy) { activityFilter = filter } } label: {
            PaperChoiceChipLabel(title: filter, isOn: isOn)
                // Paper's pill is 40 tall; the tap target stays 44.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        // Spoken as "Show notes": never the bare word a job section also carries ("Money").
        .accessibilityLabel("Show \(filter.lowercased())")
        .accessibilityHint("Filters this job's activity")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("activity-filter-\(filter.lowercased())")
    }

    /// Paper 21B Activity: the composer leads, the filter chips under it, then each day as a 13
    /// Semibold label over one card of its entries (photos inline as thumbnails).
    private func activityContent(_ job: JobRecord) -> some View {
        let days = activityDays(job)
        return LazyVStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                if session.can("job.note", feature: "jobs") { composer }
                activityFilterChips
            }
            if days.isEmpty {
                PaperEmptyState(symbol: "clock", title: "No activity yet",
                                message: "Status changes, notes and photos on this job show up here.")
            }
            ForEach(Array(days.enumerated()), id: \.element.day) { _, group in
                VStack(alignment: .leading, spacing: 8) {
                    JobPanelLabel(title: dayTitle(group.day))
                    JobPanel {
                        ForEach(Array(group.entries.enumerated()), id: \.element.id) { position, entry in
                            timelineRow(entry, showsDay: false, isFirst: position == 0, isLast: position == group.entries.count - 1)
                        }
                    }
                }
            }
        }
    }

    private func activityDays(_ job: JobRecord) -> [(day: Date, entries: [TimelineEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: timeline(job, filter: activityFilter)) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in (day, grouped[day] ?? []) }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func timeLabel(_ date: Date, showsDay: Bool) -> String {
        let calendar = Calendar.current
        guard showsDay, !calendar.isDateInToday(date) else { return date.tradeTime }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// A note, a status change or the day's photos; notes and status open what they're about,
    /// photos open the visit's photos.
    @ViewBuilder
    private func timelineRow(_ entry: TimelineEntry, showsDay: Bool, isFirst: Bool = true, isLast: Bool = true,
                             inset: CGFloat = 16) -> some View {
        let content = timelineRowContent(entry, showsDay: showsDay, isFirst: isFirst, isLast: isLast, inset: inset)
        if !entry.photos.isEmpty {
            Button { openPhotos() } label: { content }
                .buttonStyle(RowPressStyle())
                .accessibilityHint("Opens the job's photos")
        } else if entry.opensOverview {
            Button { withMotion(.snappy) { selectedTab = "Overview" } } label: { content }
                .buttonStyle(RowPressStyle())
                .accessibilityHint("Opens the recording and transcript on Overview")
        } else {
            // Opens what the entry is about; the row style rule leaves out a chevron on every row.
            if let destination = ActivityDestinationMapping.destination(for: entry.subject) {
                NavigationLink(value: destination.route) { content }
                    .buttonStyle(RowPressStyle())
            } else {
                content
            }
        }
    }

    private func timelineRowContent(_ entry: TimelineEntry, showsDay: Bool, isFirst: Bool, isLast: Bool, inset: CGFloat) -> some View {
        // At accessibility sizes the time goes under the entry; beside it, it ran off the screen.
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                                  : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        // Paper 21B: the mark in a 32pt disc, what happened at 15 with its time at 13 on the same
        // line, then a note's words in a quiet bubble (radius 14) or the photos as 60pt tiles.
        let isNote = entry.subject.kind == "note"
        return JobTimelineItem(kind: entry.subject.kind, title: entry.title, pending: entry.id.hasPrefix("queued-"),
                               isFirst: isFirst, isLast: isLast, verticalPadding: 12, disc: true) {
            VStack(alignment: .leading, spacing: 8) {
                layout {
                    Text(entry.title).font(Theme.font(15)).foregroundStyle(Theme.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(-1)
                    Text(timeLabel(entry.date, showsDay: showsDay))
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize()
                }
                .frame(minHeight: 32)
                if let body = entry.body, !body.isEmpty {
                    // Long notes fold to four lines with "More"; nothing is cut off for good.
                    if isNote {
                        ExpandableNoteText(text: body, lines: 4)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        ExpandableNoteText(text: body, lines: 4)
                    }
                }
                if !entry.photos.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(entry.photos.prefix(3)) { photo in
                            Color.clear.frame(width: 60, height: 60)
                                .overlay(MediaThumbnail(record: photo))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, inset)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        // One spoken item: when, what happened (and who), then the whole note, never the folded part.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([timeLabel(entry.date, showsDay: showsDay), entry.title, entry.body]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
    }

    /// Paper 21B's composer, at the top of Activity: the note field in one card with the mic, the
    /// camera and the send circle. The camera steps aside once there is something to save.
    private var composer: some View {
        // At accessibility sizes the field stops growing at the second accessibility size, starting
        // at one line and growing to three, with less air; the quick phrases stop at the first.
        let roomy = !typeSize.isAccessibilitySize
        let placeholder = dictation.isListening ? "Listening…" : "Add a note or update…"
        // Paper 21B: one card (radius 14, 50 tall): who is writing as initials on the brand
        // surface, the field, a camera glyph, then the brand send circle. The mic keeps dictation
        // one tap away; the one-tap phrases show once the field is in use.
        return VStack(alignment: .leading, spacing: roomy ? 8 : 4) {
            HStack(alignment: .bottom, spacing: 4) {
                Text(initials(session.user?.name ?? session.user?.email ?? "You"))
                    .font(Theme.font(11, weight: .semibold))
                    .foregroundStyle(Theme.brandText)
                    .frame(width: 30, height: 30)
                    .background(Theme.brandSurface, in: Circle())
                    .dynamicTypeSize(...DynamicTypeSize.large)
                    .padding(.bottom, 7).padding(.trailing, 6)
                    .accessibilityHidden(true)
                TextField(placeholder, text: $note, prompt: .placeholder(placeholder), axis: .vertical)
                    .font(Theme.font(16))
                    .lineLimit(roomy ? 1...6 : 1...3)
                    .focused($noteFocused)
                    .padding(.vertical, roomy ? 11 : 6)
                    .frame(minHeight: 44)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .accessibilityIdentifier("job-note-field")
                if noteFocused || dictation.isListening || !note.isEmpty { composerDictateButton }
                if !canSaveNote, !busy, session.can("job.edit", feature: "jobs") {
                    Button { openCapture(.camera(stage: nil)) } label: {
                        PaperIcon(.jobCamera, size: 22, color: Theme.subtle)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Add photo")
                    .accessibilityIdentifier("job-composer-camera")
                }
                Button { dictation.stop(); Task { await saveNote() } } label: {
                    Group {
                        if busy { ProgressView().tint(.white) }
                        else { PaperIcon(.jobSend, size: 16, color: .white) }
                    }
                    .foregroundStyle(Color.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.brand.opacity(canSaveNote || busy ? 1 : 0.35), in: Circle())
                    // Paper's circle is 40; the tap target stays 44.
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .disabled(!canSaveNote || busy)
                .accessibilityLabel("Save note")
                .accessibilityIdentifier("job-note-save")
            }
            .padding(.leading, 10).padding(.trailing, 4).padding(.vertical, 3)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if noteFocused || dictation.isListening || !note.isEmpty {
                QuickNotesRow { phrase in note = NoteDraftText.joined(note, phrase) }
                    .disabled(dictation.isListening)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }
            if let problem = dictation.problem, problem == .denied {
                PermissionNotice(permission: .microphone, purpose: "dictate notes", message: problem.message)
            } else if let problem = dictation.problem {
                VStack(alignment: .leading, spacing: 4) {
                    Text(problem.message).font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if problem == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
                        Button("Open Settings") { openURL(url) }
                            .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.foreground)
                            .buttonStyle(PressStyle()).frame(minHeight: 44)
                    }
                }
                .accessibilityElement(children: .combine)
                .padding(.horizontal, 4)
            }
        }
    }

    /// The composer's mic: a bare glyph in a 44pt target (brand while listening), so the card stays
    /// Paper's one row.
    private var composerDictateButton: some View {
        Button {
            if dictation.isListening { dictation.stop(); return }
            Task { await dictation.start(draft: note, isOffline: session.isOffline) { note = $0 } }
        } label: {
            Image(systemName: dictation.isListening ? "stop.fill" : "mic")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(dictation.isListening ? Theme.brandText : Theme.subtle)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .symbolEffect(.pulse, isActive: dictation.isListening)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(dictation.isListening ? "Stop dictation" : "Dictate note")
        .accessibilityIdentifier("dictate-note")
    }

    private var canSaveNote: Bool {
        !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && note.utf16.count <= 10_000
    }

    private struct TimelineEntry: Identifiable {
        let id: String
        let title: String
        let body: String?
        let date: Date
        let subject: ActivityFeedSubject
        /// The day's photos, shown inline as thumbnails.
        var photos: [MediaAssetRecord] = []
        /// The booking call: its recording and transcript live on Overview.
        var opensOverview = false
    }

    /// Everything that happened on the visit, newest first. `filter` is one of `activityFilters`;
    /// counts always use "All" so the section's number doesn't move with the filter.
    private func timeline(_ job: JobRecord, filter: String) -> [TimelineEntry] {
        var entries: [TimelineEntry] = []
        if filter == "All" || filter == "Notes" {
            entries += outbox.pendingNotes(for: job.id).compactMap { entry in
                guard case .note(let payload) = entry.action else { return nil }
                let waiting = entry.state == .pending ? "Note · waiting to sync" : "Note · couldn't sync"
                return TimelineEntry(id: "queued-\(entry.id)", title: waiting, body: payload.body, date: entry.createdAt, subject: ActivityFeedSubject(kind: "note", jobID: job.id))
            }
            entries += notes.compactMap { record -> TimelineEntry? in
                // Only the signed-in person can be named; other authors need the roster (BYR-1599).
                let title = record.authorUserId == session.user?.id ? "Note · You" : "Note"
                return JobFiltering.date(record.createdAt).map { TimelineEntry(id: "note-\(record.id)", title: title, body: record.body, date: $0, subject: ActivityFeedSubject(kind: "note", subjectID: record.id, jobID: job.id)) }
            }
        }
        if filter == "All" || filter == "Status" {
            entries += statusEvents(job).map { TimelineEntry(id: "status-\($0.0)", title: $0.0, body: nil, date: $0.1, subject: ActivityFeedSubject(kind: "status", jobID: job.id)) }
        }
        // Paper 21B's "Money" chip: what happened to the job's estimates.
        if filter == "All" || filter == "Money", session.can("estimate.view", feature: "estimates") {
            entries += jobEstimates.flatMap { estimateEvents($0, job: job) }
        }
        if filter == "All", let call = bookingCall, let started = JobFiltering.date(call.startedAt) {
            let minutes = call.durationSeconds.map { max(1, Int((Double($0) / 60).rounded())) }
            entries.append(TimelineEntry(id: "call-\(call.id)", title: "Booking call" + (minutes.map { " · \($0) min" } ?? ""),
                                         body: call.summary?.text ?? call.callerName, date: started,
                                         subject: ActivityFeedSubject(kind: "call", jobID: job.id), opensOverview: true))
        }
        if filter == "All", liveMediaCountContext != nil, liveMediaCountContext == mediaCountContext {
            let calendar = Calendar.current
            let byDay = Dictionary(grouping: mediaPhotos) { photo in
                calendar.startOfDay(for: JobFiltering.date(photo.capturedAt) ?? JobFiltering.date(photo.createdAt) ?? .distantPast)
            }
            for (day, photos) in byDay where day != calendar.startOfDay(for: .distantPast) {
                let newest = photos.compactMap { JobFiltering.date($0.capturedAt) ?? JobFiltering.date($0.createdAt) }.max() ?? day
                let stages = Set(photos.map { $0.tags.contains("Before") ? "Before" : ($0.tags.contains("After") ? "After" : "") })
                let stage = stages.count == 1 ? stages.first.flatMap { $0.isEmpty ? nil : $0 } : nil
                let title = "\(photos.count) \(photos.count == 1 ? "photo" : "photos")" + (stage.map { " · \($0)" } ?? "")
                entries.append(TimelineEntry(id: "photos-\(day.timeIntervalSince1970)", title: title, body: nil, date: newest,
                                             subject: ActivityFeedSubject(kind: "media", jobID: job.id), photos: photos))
            }
        }
        return entries.sorted { $0.date > $1.date }
    }

    private func activityCount(_ job: JobRecord) -> Int { timeline(job, filter: "All").count }

    /// One row for each step the estimate took: created, sent (with its amount), approved, declined.
    private func estimateEvents(_ estimate: EstimateRecord, job: JobRecord) -> [TimelineEntry] {
        let options = estimate.options ?? []
        let amount = options.isEmpty
            ? paperLinesTotal(estimate.lines).map { " · " + jobShortMoney($0, currency: estimate.lines.first?.unitPrice.currency ?? "USD") } ?? ""
            : ""
        let body = estimate.title + (options.isEmpty ? "" : ", \(options.count) \(options.count == 1 ? "option" : "options")")
        let steps: [(String, String, String?)] = [
            ("created", "Estimate created", estimate.createdAt),
            ("sent", "Estimate sent" + amount, estimate.sentAt),
            ("approved", "Estimate approved", estimate.approvedAt),
            ("declined", "Estimate declined", estimate.declinedAt)
        ]
        return steps.compactMap { key, title, raw in
            raw.flatMap(JobFiltering.date).map {
                TimelineEntry(id: "estimate-\(estimate.id)-\(key)", title: title, body: body, date: $0,
                              subject: ActivityFeedSubject(kind: "estimate", subjectID: estimate.id, jobID: job.id))
            }
        }
    }

    private func statusEvents(_ job: JobRecord) -> [(String, Date)] {
        let raw: [(String, String?)] = [
            ("Job created", job.createdAt),
            ("Dispatched", job.dispatchedAt),
            ("En route", job.enRouteAt),
            ("Arrived", job.arrivedAt),
            ("Work started", job.startedAt),
            ("Paused", job.pausedAt),
            ("Completed", job.completedAt),
            ("Canceled", job.canceledAt)
        ]
        return raw.compactMap { label, value in
            value.flatMap(JobFiltering.date).map { (label, $0) }
        }
        .sorted { $0.1 > $1.1 }
    }

    /// Photos, with their capture tools, in Activity.
    private func openPhotos() {
        dictation.stop()
        activityFilter = "Photos"
        withMotion(.snappy) { selectedTab = "Activity" }
    }

    /// The toolkit's Photo, Measure and Scan: the media screen opens the capture itself.
    private func openCapture(_ launch: JobMediaLaunch) {
        openPhotos()
        mediaLaunch = launch
    }

    /// The toolkit's Note: Activity with the field focused, ready to type or dictate.
    private func openNoteTool() {
        activityFilter = "All"
        withMotion(.snappy) { selectedTab = "Activity" }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            noteFocused = true
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(Theme.font(17, weight: .medium))
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(label).foregroundStyle(Theme.muted).frame(width: 95, alignment: .leading)
            Text(value).foregroundStyle(Theme.foreground).frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .font(Theme.font(13))
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Theme.brandText).frame(width: 20)
            Text(title).font(Theme.font(15, weight: .medium))
            Spacer()
            PaperDisclosure()
        }
        .foregroundStyle(Theme.foreground)
        .padding(15)
        .contentShape(Rectangle())
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { actionLabel(title, icon: icon) }
            .buttonStyle(PressStyle())
            .disabled(busy)
    }

    private func emptyCard(_ message: String) -> some View {
        PaperInlineEmpty(message)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PaperCardMetrics.inset)
            .panelBackground(cornerRadius: Theme.cardRadius)
    }

    /// TF-01: the one next step for this job, from its status, its estimates and its invoices.
    private var nextStep: TechJobStep? {
        guard let job else { return nil }
        let can = TechJobAbilities(
            createEstimate: session.can("estimate.create", feature: "estimates"),
            sendEstimate: session.can("estimate.send", feature: "estimates"),
            approveEstimate: session.can("estimate.approve", feature: "estimates"),
            createInvoice: session.can("invoice.create", feature: "invoicing"),
            viewInvoice: session.can("invoice.view", feature: "invoicing"),
            collectPayment: session.can("invoice.payment.create", feature: "payments"),
            completeJob: session.can("job.complete", feature: "jobs"))
        return TechJobFlow.nextStep(status: outbox.pendingStatus(for: job.id) ?? job.status, transitions: availableTransitions(job),
                                    estimates: (estimatesLoaded && !estimatesFailed) || !session.can("estimate.view", feature: "estimates") ? jobEstimates : nil,
                                    invoices: invoicesLoaded && !invoicesFailed ? invoices : nil, can: can)
    }

    private var canBuildEstimate: Bool {
        let current = JobEstimateCreation.currentComplete(scope: job.flatMap { scope(for: $0) }, readScope: estimateRead?.scope,
            complete: estimateRead?.isComplete == true,
            authorityCurrent: documentGeneration == session.generation && overviewEstimatesAuthority?.isCurrent(api: api, session: session) == true)
        return JobEstimateCreation.canOpen(canCreate: session.can("estimate.create", feature: "estimates"),
                                    canView: session.can("estimate.view", feature: "estimates"),
                                    estimatesComplete: current)
    }

    private var canOpenCustomerView: Bool {
        session.can("estimate.view", feature: "estimates") || session.can("invoice.view", feature: "invoicing")
            || session.can("customer.edit", feature: "core_crm")
    }

    /// Customer view: the job's one protected customer handoff (estimates, invoices, the customer's
    /// own details) with one staff hand-back. Every customer-facing door on the job opens it.
    private func openCustomerView(_ start: CustomerViewStart) {
        guard let job, scope(for: job) != nil, canOpenCustomerView,
              let source = customerWindowAnchor.window, customerWindowAnchor.isAttached(to: source),
              let authority = CustomerHandoffExitAuthority.capture(api: api, session: session) else {
            error = "Customer view isn't ready. Refresh this job and try again."
            return
        }
        let model = JobEstimateHandoffModel(job: job, customerName: store.customerName(job.customerId), documents: documents, api: api, session: session)
        let details = session.can("customer.edit", feature: "core_crm") ? CustomerSelfEditModel(customerID: job.customerId) : nil
        let opened = estimateHandoffPresenter.present(model, start: start, details: details, sourceGeneration: documentGeneration,
                                         invoiceUpdated: updateInvoice, sourceWindow: source) { exit in
            guard let exitRevision = estimateHandoffPresenter.idleRevision else { return }
            let current: @MainActor () -> Bool = {
                estimateHandoffPresenter.isIdleRevision(exitRevision) && customerWindowAnchor.isAttached(to: source) &&
                authority.isCurrent(api: api, session: session) && session.can("job.view", feature: "jobs") && self.job?.id == job.id
            }
            guard current() else { return }
            // The customer may have changed a phone, an email or a contact in their own hands.
            await loadContacts(job, currentAuthority: current)
            guard current() else { return }
            if case .collect(let invoiceID) = exit { customerPaymentInvoiceID = invoiceID }
            await finishCustomerDocuments(currentAuthority: current)
        }
        if !opened { error = "Customer view couldn't open. Try again." }
    }

    private func buildEstimate() {
        guard !preparingEstimate, session.can("estimate.create", feature: "estimates"),
              let job, let scope = scope(for: job) else { return }
        if canBuildEstimate { showNewEstimate = true; return }
        guard session.can("estimate.view", feature: "estimates"),
              let authority = CustomerHandoffExitAuthority.capture(api: api, session: session) else { return }
        preparingEstimate = true
        let generation = session.generation
        Task {
            defer { preparingEstimate = false }
            let current: @MainActor () -> Bool = {
                authority.isCurrent(api: api, session: session) && session.generation == generation &&
                    self.job.flatMap { self.scope(for: $0) } == scope &&
                    session.can("estimate.view", feature: "estimates") && session.can("estimate.create", feature: "estimates")
            }
            let read = await JobDocumentsLoader.estimates(scope: scope, api: api, retaining: nil, isCurrent: current)
            guard current(), JobEstimateCreation.canOpen(canCreate: true, canView: true, estimatesComplete: read?.isComplete == true) else {
                error = "Couldn't prepare this estimate. Check your connection and try again."
                return
            }
            showNewEstimate = true
        }
    }

    private func run(_ step: TechJobStep, current: @escaping @MainActor () -> Bool = { true },
                     onCompletion: (@MainActor () -> Void)? = nil) {
        switch step {
        case .transition(let target): runTransition(target)
        case .buildEstimate: buildEstimate()
        case .presentEstimates: openCustomerView(.estimates)
        case .showEstimate(let id): openEstimate = OpenedEstimate(id: id, present: true)
        case .createInvoice:
            Task {
                // TF-08: one tap makes the invoice from the approved work and opens it for review.
                if let invoice = await createInvoice(), session.can("invoice.view", feature: "invoicing"),
                   let job, let scope = scope(for: job), scope.contains(invoice) {
                    reviewInvoiceID = invoice.id
                }
            }
        case .reviewInvoice(let id): reviewInvoiceID = id
        case .collect(let invoiceID, _, _):
            Task {
                defer { onCompletion?() }
                let generation = session.generation
                let authority = session.authorityRevision
                let apiGeneration = api.requestGeneration
                let copyRevision = api.savedCopyScopeRevision
                let origin = api.normalizedOrigin
                guard let job, let expectedScope = scope(for: job) else { return }
                selectedInvoiceID = invoiceID
                if let invoice = invoices.first(where: { $0.id == invoiceID && expectedScope.contains($0) }) {
                    await loadInvoicePayments(for: invoice)
                }
                #if DEBUG
                if PaperPreview.isJobDocumentsPreview && ProcessInfo.processInfo.arguments.contains("--paper-preview-overview-payment-hold") {
                    previewOverviewPaymentHold = true
                    try? await Task.sleep(for: .seconds(6))
                    previewOverviewPaymentHold = false
                }
                #endif
                guard !Task.isCancelled, current(), session.generation == generation, session.authorityRevision == authority,
                      api.requestGeneration == apiGeneration, api.normalizedOrigin == origin,
                      api.savedCopyScopeRevision == copyRevision,
                      let currentJob = self.job, scope(for: currentJob) == expectedScope else { return }
                if !presentPayment(for: invoiceID) { withMotion(.snappy) { selectedTab = "Money" } }
            }
        case .wrapUp: showWrapUp = true
        }
    }

    /// The status popover's moves; the same source as Today's Now panel and the rows' swipe.
    private func availableTransitions(_ job: JobRecord) -> [String] {
        JobMoves.available(served: job.allowedTransitions, queued: outbox.pendingStatus(for: job.id),
                           learned: outbox.offlineSteps(from:), canEdit: session.can("job.edit", feature: "jobs"),
                           canAssign: session.can("job.assign", feature: "jobs"))
    }

    private func transitionTitle(_ target: String) -> String {
        switch target {
        // The More menu's moves (Paper 21K: "Pause job", "Cancel job"); a forward move reads as the
        // main button does (Paper F2 "I've arrived"). The status sheet names steps instead
        // (`statusStepTitle`, Paper 21T).
        case "paused": "Pause job"
        case "canceled", "cancelled": "Cancel job"
        case "en_route": "On my way"
        case "arrived": "I've arrived"
        case "in_progress": job?.status == "paused" ? "Resume work" : "Start work"
        case "dispatched": "Dispatch"
        case "scheduled": "Move back to scheduled"
        default: "Mark \(target.statusLabel.lowercased())"
        }
    }

    private func transitionSymbol(_ target: String) -> String {
        switch target {
        case "paused": "pause.circle"
        case "en_route": "location.fill"
        case "arrived": "mappin.and.ellipse"
        case "in_progress": "wrench.and.screwdriver"
        case "dispatched": "paperplane"
        case "canceled", "cancelled": "xmark.circle"
        default: "arrow.uturn.backward"
        }
    }

    private func runTransition(_ target: String) {
        if target == "paused" { showPause = true }
        else { Task { await advance(target) } }
    }

    /// Try again re-runs every load this page has attempted, so a failed invoice or estimate
    /// fetch is retried too, not just the job.
    private func retry() async {
        await load()
        if invoicesLoaded { await loadInvoices() }
        if estimatesLoaded, let job { await loadJobEstimates(job) }
    }

    private func loadInvoices() async {
        guard session.can("invoice.view", feature: "invoicing"), let job, let scope = scope(for: job),
              let authority = CustomerHandoffExitAuthority.capture(api: api, session: session) else {
            overviewInvoicesAuthority = nil
            documents.clearInvoices()
            return
        }
        let generation = session.generation
        let published = await documents.loadInvoices(scope: scope, api: api) {
            authority.isCurrent(api: api, session: session) && session.generation == generation && session.activeOrganization?.id == scope.organizationID &&
                self.job?.id == scope.jobID && self.job?.customerId == scope.customerID
        }
        guard session.generation == generation, authority.isCurrent(api: api, session: session), published else { return }
        overviewInvoicesAuthority = authority
        if let selectedInvoice {
            selectedInvoiceID = selectedInvoice.id
            await loadInvoicePayments(for: selectedInvoice)
        } else {
            selectedInvoiceID = nil
            invoicePaymentModel = nil
            loadedInvoiceModelID = nil
        }
    }

    /// The job's canonical completion draft (POST /v1/jobs/{id}/completion-invoice); idempotent per job.
    @discardableResult private func createInvoice() async -> InvoiceRecord? {
        guard !creatingInvoice,
              !session.can("invoice.view", feature: "invoicing") || (invoicesLoaded && !invoicesFailed),
              let job, let scope = scope(for: job),
              session.can("invoice.create", feature: "invoicing") else { return nil }
        creatingInvoice = true
        defer { creatingInvoice = false }
        let generation = session.generation
        let authority = session.authorityRevision
        let actorID = session.user?.id
        let apiGeneration = api.requestGeneration
        let copyRevision = api.savedCopyScopeRevision
        let origin = api.normalizedOrigin
        let current: @MainActor () -> Bool = {
            !Task.isCancelled && session.user?.id == actorID && session.generation == generation &&
                session.authorityRevision == authority && api.requestGeneration == apiGeneration &&
                api.savedCopyScopeRevision == copyRevision && api.normalizedOrigin == origin &&
                session.activeOrganization?.id == scope.organizationID &&
                session.can("job.view", feature: "jobs") && session.can("invoice.create", feature: "invoicing") &&
                self.job.map { self.scope(for: $0) == scope } == true
        }
        let reportUncertain: @MainActor () -> Void = {
            guard !Task.isCancelled, let actorID, session.user?.id == actorID,
                  session.activeOrganization?.id == scope.organizationID,
                  JobInvoiceRecoveryContext.matches(origin: origin, savedCopyRevision: copyRevision,
                      currentOrigin: api.normalizedOrigin, currentSavedCopyRevision: api.savedCopyScopeRevision),
                  session.can("job.view", feature: "jobs"),
                  self.job.map({ self.scope(for: $0) == scope }) == true else { return }
            self.error = "Invoice may have been created. Refresh this job to check."
        }
        do {
            #if DEBUG
            if PaperPreview.isJobDocumentsPreview, ProcessInfo.processInfo.arguments.contains("--paper-preview-create-invalidate-post") {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    api.invalidateRequests()
                }
            }
            #endif
            let invoice = try await api.ensureFieldCompletionInvoice(jobId)
            guard current() else { reportUncertain(); return nil }
            guard scope.contains(invoice) else {
                throw Problem(title: "Invoice could not be verified for this job", status: nil, detail: nil)
            }
            JobInvoiceMemory.remember(invoice.id, jobID: jobId)
            selectedInvoiceID = invoice.id
            #if DEBUG
            if PaperPreview.isJobDocumentsPreview, ProcessInfo.processInfo.arguments.contains("--paper-preview-create-invalidate-refresh") {
                api.invalidateRequests()
            }
            if PaperPreview.isJobDocumentsPreview, ProcessInfo.processInfo.arguments.contains("--paper-preview-create-revoke-view") {
                PaperPreviewProtocol.revokeInvoiceViewForCreate()
                await session.revalidate()
            }
            #endif
            await loadInvoices()
            guard current() else { reportUncertain(); return nil }
            committed += 1
            return invoice
        } catch is CancellationError { reportUncertain(); return nil } catch {
            if current() { self.error = error.localizedDescription } else { reportUncertain() }
            return nil
        }
    }

    private func finishCustomerDocuments(currentAuthority: @escaping @MainActor () -> Bool = { true }) async {
        guard currentAuthority() else { return }
        let requestedID = customerPaymentInvoiceID
        customerPaymentInvoiceID = nil
        let generation = session.generation
        let authority = session.authorityRevision
        let apiGeneration = api.requestGeneration
        let copyRevision = api.savedCopyScopeRevision
        let origin = api.normalizedOrigin
        if let job { await loadJobEstimates(job) }
        guard currentAuthority() else { return }
        await loadInvoices()
        guard currentAuthority(), session.generation == generation, let requestedID,
              session.can("invoice.payment.create", feature: "payments"),
              invoiceRead?.freshIDs.contains(requestedID) == true,
              let invoice = invoices.first(where: { $0.id == requestedID }) else { return }
        selectedInvoiceID = requestedID
        await loadInvoicePayments(for: invoice)
        guard currentAuthority(), !Task.isCancelled, session.generation == generation, session.authorityRevision == authority,
              api.requestGeneration == apiGeneration, api.savedCopyScopeRevision == copyRevision,
              api.normalizedOrigin == origin else { return }
        presentPayment(for: requestedID)
    }

    /// Revalidates the current selection at the transition, then fixes the
    /// invoice and model together for the lifetime of the payment sheet.
    @discardableResult private func presentPayment(for requestedID: String) -> Bool {
        guard session.can("job.view", feature: "jobs"),
              session.can("invoice.view", feature: "invoicing"),
              session.can("invoice.payment.create", feature: "payments"),
              let job, let scope = scope(for: job), invoiceRead?.scope == scope,
              invoiceRead?.freshIDs.contains(requestedID) == true,
              let route = JobInvoicePaymentRoute.make(requestedID: requestedID, selectedID: selectedInvoiceID,
                                                       selected: selectedInvoice, loadedID: loadedInvoiceModelID,
                                                       model: invoicePaymentModel, scope: scope,
                                                       authorityToken: paymentAuthorityToken,
                                                       reference: jobInvoiceReference(requestedID)) else { return false }
        paymentRoute = route
        return true
    }

    private func loadInvoicePayments(for invoice: InvoiceRecord) async {
        guard session.can("invoice.view", feature: "invoicing"), let job,
              let scope = scope(for: job), scope.contains(invoice) else { return }
        if loadedInvoiceModelID != invoice.id {
            loadedInvoiceModelID = invoice.id
            invoicePaymentModel = InvoicePaymentCollectionModel(api: api, invoiceID: invoice.id, expectedJobScope: scope)
            invoicePaymentModel?.outbox = outbox
            invoicePaymentModel?.policyVersion = session.policyVersion ?? 0
        }
        if let model = invoicePaymentModel { await invoicePaymentLoads.load(model) }
    }
    private func load() async {
        let generation = session.generation
        let authorityRevision = session.authorityRevision
        let policyVersion = session.policyVersion
        do {
            let loadedJob = try await api.fieldJob(jobId)
            guard session.generation == generation, session.authorityRevision == authorityRevision,
                  session.policyVersion == policyVersion else { return }
            guard loadedJob.id == jobId, loadedJob.organizationId == session.activeOrganization?.id else {
                throw Problem(title: "Job could not be verified", status: nil, detail: nil)
            }
            job = loadedJob
            // Record before the follow-up requests below, while the identity is known to match.
            RecentItems.shared.record(.job, id: loadedJob.id, title: loadedJob.title,
                                      subtitle: "JOB-\(loadedJob.id.suffix(4).uppercased()) · \(store.customerName(loadedJob.customerId))")
            let locationContext = customerContext(loadedJob)
            if locationContext == nil || locationsContext != locationContext {
                locations = []
                locationsContext = nil
                locationsFailed = false
            }
            if locationContext != nil { await loadLocations(loadedJob) }
            if let locationContext, contactsContext != locationContext || !contactsLoaded { await loadContacts(loadedJob) }
            outbox.learn(loadedJob)
            JobDetailCache.save(loadedJob)
            let loadedNotes = try await api.fieldNotes(jobId)
            guard session.generation == generation else { return }
            notes = loadedNotes
            JobDetailCache.save(notes: loadedNotes, jobID: jobId)
            error = nil
            await loadBrief()
        } catch is CancellationError {} catch {
            guard session.generation == generation else { return }
            if error.isConnectivityFailure {
                // No signal: the last copy of this job, or what the schedule already knows.
                if job == nil { job = JobDetailCache.job(jobId) ?? listRecord() }
                if notes.isEmpty { notes = JobDetailCache.notes(jobId) }
                if job != nil { self.error = nil; return }
            }
            self.error = error.localizedDescription
        }
    }

    /// The customer's addresses. A failed read is said beside the section with Try again,
    /// never shown as "no addresses".
    private func loadLocations(_ job: JobRecord) async {
        guard let context = customerContext(job) else { return }
        let generation = session.generation
        let authorityRevision = session.authorityRevision
        let policyVersion = session.policyVersion
        func stillCurrent() -> Bool {
            session.generation == generation && session.authorityRevision == authorityRevision &&
                session.policyVersion == policyVersion && self.job?.id == job.id &&
                self.job?.customerId == job.customerId && customerContext(job) == context
        }
        if locationsContext != context {
            locations = []
            locationsContext = nil
        }
        do {
            let places = try await api.fieldLocations(job.customerId)
            guard stillCurrent() else { return }
            locations = places
            locationsContext = context
            locationsFailed = false
        } catch is CancellationError {} catch {
            guard stillCurrent() else { return }
            locationsFailed = true
        }
    }

    /// JS-06: every contact and the account; the header's Call and Text reach the primary one.
    private func loadContacts(_ job: JobRecord, currentAuthority: @escaping @MainActor () -> Bool = { true }) async {
        guard currentAuthority(), let context = customerContext(job) else { return }
        let generation = session.generation
        if contactsContext != context {
            contacts = []
            customerRecord = nil
            customerPhone = nil
            contactsLoaded = false
            contactsFailed = false
            contactsContext = nil
        }
        func stillCurrent() -> Bool {
            session.generation == generation && self.job?.id == job.id &&
                self.job?.customerId == job.customerId && customerContext(job) == context
        }
        do {
            let people = try await api.fieldContacts(job.customerId)
            guard currentAuthority() else { return }
            let account = try? await api.fieldCustomer(job.customerId)
            guard currentAuthority(), stillCurrent() else { return }
            let verified = people.filter { $0.organizationId == job.organizationId && $0.customerId == job.customerId }
            let verifiedAccount = account.flatMap { $0.organizationId == job.organizationId && $0.id == job.customerId ? $0 : nil }
            contacts = verified
            customerRecord = verifiedAccount
            contactsFailed = false
            customerPhone = verified.first(where: \.primary)?.phone ?? verified.first(where: { $0.phone != nil })?.phone ?? verifiedAccount?.phone
        } catch is CancellationError { return } catch {
            guard stillCurrent() else { return }
            contactsFailed = true
            if customerPhone == nil {
                let fallback = try? await api.fieldCustomer(job.customerId)
                guard stillCurrent() else { return }
                if let fallback, fallback.organizationId == job.organizationId, fallback.id == job.customerId {
                    customerPhone = fallback.phone
                }
            }
        }
        guard stillCurrent() else { return }
        contactsContext = context
        contactsLoaded = true
    }

    /// JS-09/JS-10: follow-ups, photo count and past visits. Each is optional: a section whose
    /// read fails or that an older server doesn't offer simply stays out.
    private func loadBrief() async {
        let generation = session.generation
        await loadFollowUps()
        await loadMediaCount()
        let loadedVisits = try? await api.fieldVisitHistory(jobId)
        let loadedCall = try? await api.fieldBookingCall(jobId)
        guard session.generation == generation else { return }
        if let loadedVisits { visits = loadedVisits; visitsLoaded = true }
        if let loadedCall { bookingCall = loadedCall }
        if let job, let pricing = try? await api.memberPricing(job.customerId), session.generation == generation,
           self.job?.customerId == job.customerId { memberPricing = pricing }
        // Quiet: a refused read (technicians on some servers) or an older server leaves the rows out.
        if let job, session.can("customer.view", feature: "core_crm"),
           let loaded = try? await api.customerEquipment(job.customerId), session.generation == generation,
           self.job?.customerId == job.customerId {
            equipment = loaded.filter { $0.customerId == job.customerId }
        }
        await loadCloseout()
        // The office's phone feeds the on-site circle and, through the whole visit, the menu's rows.
        if let job, inField(job), officeContact == nil {
            let contact = await OfficeContact.load(api: api, session: session)
            if session.generation == generation { officeContact = contact }
        }
    }

    /// "Before you wrap up" reads the server's closeout while on site. Quiet: a failed read hides
    /// the panel (the bar then says plain "Wrap up job"); it never shows as a job error.
    private func loadCloseout() async {
        guard isOnSite, let job else { closeout = nil; return }
        let generation = session.generation
        let loaded = try? await api.fieldCloseout(job.id)
        guard session.generation == generation, self.job?.id == job.id else { return }
        closeout = loaded
    }

    private func loadMediaCount() async {
        let request = UUID(); mediaCountRequest = request
        mediaCount = nil; mediaCountContext = nil
        guard let context = liveMediaCountContext, let organization = session.activeOrganization?.id else { return }
        do {
            let loaded = try await api.fieldMediaPage(jobId, kind: "photo")
            guard !Task.isCancelled, mediaCountRequest == request, liveMediaCountContext == context,
                  loaded.items.allSatisfy({ $0.kind == "photo" }) else { return }
            try JobMediaPageIntegrity.validate(loaded, jobID: jobId, organizationID: organization, seen: [])
            mediaCount = loaded.nextCursor == nil ? "\(loaded.items.count)" : "\(loaded.items.count) loaded"
            mediaPhotos = loaded.items.filter { !$0.archived }
            mediaHasMore = loaded.nextCursor != nil
            mediaCountContext = context
        } catch { }
    }

    private func loadFollowUps() async {
        if let loaded = try? await api.fieldFollowUps(jobId) { followUps = loaded }
    }

    /// A minimal record from the cached job list, so an unopened job still shows offline.
    private func listRecord() -> JobRecord? {
        guard let item = store.jobs.first(where: { $0.id == jobId }), let customerID = item.customerId,
              let organizationID = session.activeOrganization?.id else { return nil }
        return JobRecord(id: item.id, organizationId: organizationID, customerId: customerID, estimateId: nil, estimateRevisionNumber: nil,
                         locationId: item.locationId, teamId: nil, title: item.title, notes: nil, status: item.status,
                         assignedToUserId: item.assignedToUserId, scheduledFor: item.scheduledFor,
                         createdAt: item.createdAt ?? "", updatedAt: item.updatedAt ?? "", dispatchedAt: nil, enRouteAt: nil,
                         arrivedAt: nil, arrivalMethod: nil, startedAt: nil, pausedAt: nil, pauseReason: nil, pauseNextAction: nil,
                         pauseOwnerUserId: nil, pauseCycleAuditId: nil, lastResumeAuditId: nil, scheduleCycleAuditId: nil,
                         completedAt: nil, canceledAt: nil, allowedTransitions: nil)
    }
    private func advance(_ target: String) async {
        let request: FieldProgressRequest
        switch target {
        case "scheduled": request = .scheduled
        case "dispatched": request = .dispatched
        case "en_route": request = .enRoute()
        case "arrived": request = .arrived()
        case "in_progress":
            if job?.status == "paused", let auditID = job?.pauseCycleAuditId, session.can("job.edit", feature: "job_pause_cycle_resume") {
                request = .resume(expectedPauseAuditId: auditID)
            } else { request = .start }
        default: return
        }
        await progress(request)
    }
    /// Press first, then show what is missing under each field (design.thorbis.com Forms).
    private func attemptPause() {
        let why = pauseReasonText
        let next = nextAction.trimmingCharacters(in: .whitespacesAndNewlines)
        if why.isEmpty {
            // Nothing picked and nothing typed, or Other with no note to say why.
            pauseReasonProblem = pauseChoice == nil ? "Choose a reason." : "Say why the job is paused."
        } else {
            pauseReasonProblem = why.utf16.count > 2000 ? "Keep it under 2,000 characters." : nil
        }
        pauseNextProblem = next.isEmpty ? "Say what needs to happen next." : (nextAction.utf16.count > 2000 ? "Keep it under 2,000 characters." : nil)
        guard pauseReasonProblem == nil, pauseNextProblem == nil, !busy else { return }
        Task { await pause() }
    }

    private func pause() async {
        if await progress(.pause(reason: pauseReasonText, nextAction: nextAction.trimmingCharacters(in: .whitespacesAndNewlines))) {
            showPause = false
            pauseChoice = nil
            reason = ""
            nextAction = ""
        }
    }
    @discardableResult private func progress(_ request: FieldProgressRequest) async -> Bool {
        if session.isOffline || outbox.pendingStatus(for: jobId) != nil {
            return queue(request)
        }
        busy = true
        defer { busy = false }
        do {
            job = try await api.progressFieldJob(jobId, request: request)
            committed += 1
            // The progress response carries no allowedTransitions; re-read the job so the
            // next step (Mark arrived, Start work, ...) appears without a manual refresh.
            await load()
            await store.refresh(api)
            error = nil
            return true
        } catch is CancellationError { return false } catch {
            if error.isConnectivityFailure { return queue(request) }
            self.error = error.localizedDescription
            return false
        }
    }

    /// No signal: the step is saved on the phone and sent in order later; the header says so.
    private func queue(_ request: FieldProgressRequest) -> Bool {
        guard let payload = OutboxEntry.ProgressPayload(jobID: jobId, request: request) else {
            error = "Pausing a job needs a connection."
            return false
        }
        outbox.enqueue(.progress(payload), policyVersion: session.policyVersion ?? 0)
        committed += 1
        error = nil
        if !session.isOffline { Task { await syncQueued() } }
        return true
    }

    private func syncQueued() async {
        await outbox.drain(api: api, useCommandEndpoint: session.isFeatureOn("offline_sync"))
        await load()
        await store.refresh(api)
    }
    private func saveNote() async {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if session.isOffline {
            outbox.enqueue(.note(.init(jobId: jobId, body: trimmed)), policyVersion: session.policyVersion ?? 0)
            note = ""
            return
        }
        busy = true
        defer { busy = false }
        do {
            let saved = try await api.addFieldNote(jobId, body: note.trimmingCharacters(in: .whitespacesAndNewlines))
            notes.append(saved)
            note = ""
            error = nil
            await loadCloseout()
        } catch is CancellationError {} catch {
            if error.isConnectivityFailure {
                outbox.enqueue(.note(.init(jobId: jobId, body: trimmed)), policyVersion: session.policyVersion ?? 0)
                note = ""
            } else {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Keep each invoice scannable while leaving its line quantities and amounts a tap away.
private struct JobInvoiceItemsDisclosure: View {
    let invoice: InvoiceRecord
    let reference: String
    @State private var expanded: Bool

    /// Paper 24 draws the job's one invoice with its lines open; with several invoices each starts
    /// folded so the list stays scannable.
    init(invoice: InvoiceRecord, reference: String, startsExpanded: Bool = false) {
        self.invoice = invoice
        self.reference = reference
        _expanded = State(initialValue: startsExpanded)
    }

    private var itemCount: String {
        "\(invoice.lines.count) \(invoice.lines.count == 1 ? "item" : "items")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                // Paper 24: "Line items" as a 13 Semibold label, its count at the trailing edge.
                HStack(spacing: 8) {
                    Text("Line items").font(Theme.font(13, weight: .semibold))
                    Spacer(minLength: 8)
                    Text(itemCount).font(Theme.font(13)).monospacedDigit()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityLabel("\(expanded ? "Hide" : "Show") \(itemCount) for invoice \(reference)")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("job-invoice-items-\(invoice.id)")
            if expanded {
                JobInvoiceLineRows(lines: invoice.lines, currency: invoice.currency, invoiceID: invoice.id)
                JobInvoiceTotals(invoice: invoice)
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
            }
        }
    }
}

/// Where the visit is, in five steps: booked, on the way, on site, working, done.
/// An estimate opened from the job; `present` hands it to the customer as soon as it loads.
struct OpenedEstimate: Identifiable, Hashable {
    let id: String
    let present: Bool
}

private struct OverviewJobDocumentRoute: Identifiable, Hashable {
    enum Kind { case estimate, invoice }
    let id = UUID()
    let documentID: String
    let kind: Kind
    let scope: JobDocumentScope
    let authority: CustomerHandoffExitAuthority
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Invoice ids this phone has seen per job, so a technician (whose invoice list is empty by
/// design) can reopen a job's invoice by id. Ids only; cleared on sign-out with the defaults.
enum JobInvoiceMemory {
    private static let key = "thorbis.jobInvoiceIDs.v1"

    static func ids(_ jobID: String) -> [String] {
        (UserDefaults.standard.dictionary(forKey: key)?[jobID] as? [String]) ?? []
    }

    static func remember(_ invoiceID: String, jobID: String) {
        var all = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        var list = (all[jobID] as? [String]) ?? []
        guard !list.contains(invoiceID) else { return }
        list.append(invoiceID)
        all[jobID] = list
        UserDefaults.standard.set(all, forKey: key)
    }

    static func replace(_ ids: [String], jobID: String) {
        var all = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        all[jobID] = Array(Set(ids)).sorted()
        UserDefaults.standard.set(all, forKey: key)
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

/// Customer account locations do not establish a job site. A destination is chosen explicitly.
enum JobLocationPolicy {
    static func context(generation: UUID, authorityRevision: UUID, policyVersion: Int, canView: Bool, organizationID: String, customerID: String) -> String {
        [generation.uuidString, authorityRevision.uuidString, String(policyVersion), String(canView), organizationID, customerID].map { "\($0.utf8.count):\($0)" }.joined()
    }

    static func accountLocations(_ locations: [ServiceLocationRecord], customerID: String, organizationID: String) -> [ServiceLocationRecord] {
        locations.filter { $0.customerId == customerID && $0.organizationId == organizationID }
    }

    static func directions(for locationID: String?, in locations: [ServiceLocationRecord]) -> URL? {
        guard let locationID, let place = locations.first(where: { $0.id == locationID }),
              !place.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Directions.url(address: place.address, coordinates: place.coordinates)
    }
}

/// Paper 21 Job details' header chip: a 40pt pill (the card, or a status's tint) with a small mark
/// and 14 Medium words. Its words wrap at accessibility sizes instead of being cut.
private struct JobHeaderChip<Leading: View>: View {
    let text: String
    var fill: Color = Theme.card
    var textColor: Color = Theme.subtle
    /// A chevron after the words, for a chip that opens a menu.
    var weight: Font.Weight = .medium
    var showsChevron = false
    var leadingInset: CGFloat = 12
    var trailingInset: CGFloat = 12
    @ViewBuilder var leading: Leading
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 6) {
            leading
            Text(text)
                .font(Theme.font(14, weight: weight))
                .foregroundStyle(textColor)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if showsChevron {
                PaperIcon(.chevronDown, size: 12, color: textColor)
            }
        }
        .padding(.leading, leadingInset).padding(.trailing, trailingInset).padding(.vertical, 6)
        .frame(minHeight: 40)
        .background(fill, in: Capsule())
        .contentShape(Capsule())
    }
}
