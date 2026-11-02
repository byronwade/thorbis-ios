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
    @State private var customerPaymentInvoiceID: String?
    @State private var documentInvoiceID: String?
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
    private var invoiceRead: JobDocumentRead<InvoiceRecord>? { documents.invoices }
    private var invoices: [InvoiceRecord] { invoiceRead?.records ?? [] }
    private var invoicesLoaded: Bool { invoiceRead != nil }
    private var invoicesFailed: Bool { invoiceRead?.isComplete == false }
    @State private var selectedInvoiceID: String?
    @State private var invoicePaymentModel: InvoicePaymentCollectionModel?
    @State private var loadedInvoiceModelID: String?
    @State private var showCollectPayment = false
    @State private var activityFilter = "All"
    @State private var showSchedule = false
    private var estimateRead: JobDocumentRead<EstimateRecord>? { documents.estimates }
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
    @State private var showFollowUps = false
    @State private var handoff: DeviceHandoff?
    /// The first page of the visit's photos (the strip on Overview, thumbnails in Activity).
    @State private var mediaPhotos: [MediaAssetRecord] = []
    @State private var mediaHasMore = false
    /// The server's closeout checklist, read while on site for "Before you wrap up". Nil hides it.
    @State private var closeout: FieldCloseout?
    /// The workspace's business phone, when this role can read it, for the on-site call circle.
    @State private var officeContact: OfficeContact?
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
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Overview for the visit, Money for its estimates and invoices, Activity for notes, status and photos.
    private let tabs = ["Overview", "Money", "Activity"]
    private let activityFilters = ["All", "Notes", "Status", "Estimates", "Photos"]
    private var showsPhotos: Bool { selectedTab == "Activity" && activityFilter == "Photos" }

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
                    activityFilterLabel(title: "Photos").padding(.horizontal, Theme.gutter)
                    JobMediaView(jobID: jobId, launch: $mediaLaunch)
                } else {
                    // At accessibility sizes, the full job header can be taller than the
                    // screen. Keep the section chooser reachable above the scrolling content.
                    if typeSize.isAccessibilitySize { tabBar(job) }
                    ScrollViewReader { proxy in
                    ScrollView {
                    // The tabs pin under the nav bar, so switching Overview, Invoice or Activity
                    // never means scrolling back to the top first.
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    header(job, compact: selectedTab != "Overview")
                    // At accessibility sizes a fixed action can cover most of a small screen.
                    // Keep the same action early in the scrollable content instead.
                    if typeSize.isAccessibilitySize { primaryAction }
                    // Where the sections start; it reports when the tabs are pinned (scrolled past).
                    Color.clear.frame(height: 0).id("job-sections")
                        .onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).minY < -1 } action: { tabsPinned = $0 }
                    Section {
                        VStack(alignment: .leading, spacing: 16) {
                            switch selectedTab {
                            case "Money": moneyContent(job)
                            case "Activity": activityContent(job)
                            default: overviewContent(job)
                            }
                        }
                        .padding(.horizontal, Theme.gutter)
                        // On site the tool grid sits 18pt under the selector, as in OnSite.dc.html.
                        .padding(.top, selectedTab == "Overview" ? (isOnSite ? 12 : 14) : 8)
                        .padding(.bottom, 28)
                    } header: {
                        // Inset 1pt so the pinned tabs never cut the sheet's rim.
                        if !typeSize.isAccessibilitySize { tabBar(job).background(Theme.card.padding(.horizontal, 1)) }
                    }
                    }
                    }
                    // A section opened while the tabs are pinned (the pinned tabs, or Due on site, Open
                    // and See all far down the page) starts at its top. Left at the old offset, the
                    // shorter section had the scroll view re-adjusting its offset every frame (a hang).
                    .onChange(of: selectedTab) {
                        guard tabsPinned else { return }
                        proxy.scrollTo("job-sections", anchor: .top)
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
                    // C-Job: the job lives in a panel sheet (radius 14) under the canvas bar.
                    .background { jobSheet }
                    .padding(.top, 6)
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
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        // v2 Record room: sections are space and a 13 Medium label, no panels ("the page is one pour").
        .environment(\.paperRecordRoom, true)
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
            JobDepositSheet(jobID: jobId) { invoice in
                selectedInvoiceID = invoice.id
                Task { await loadInvoices() }
            }
        } }
        .thorbisDestination(item: $documentInvoiceID) { id in
            InvoiceDetailView(id: id, expectedJobScope: job.flatMap { scope(for: $0) })
                .onDisappear { Task { await loadInvoices(); await loadCloseout() } }
        }
        .thorbisDestination(item: $reviewInvoiceID) { id in
            InvoiceDetailView(id: id, returnsWhenPaid: true, expectedJobScope: job.flatMap { scope(for: $0) })
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
            JobCloseoutView(jobID: jobId, place: job.flatMap { street($0) }).onDisappear { Task { await loadCloseout() } }
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
            guard opensAssign || opensPause else { return }
            try? await Task.sleep(for: .seconds(1.5))
            if opensAssign { showAssign = true } else { showPause = true }
            #endif
        }
        .thorbisDestination(isPresented: $showFollowUps) {
            JobFollowUpsView(jobID: jobId, initialKind: followUpKind).onDisappear { Task { await loadFollowUps() } }
        }
        .sheet(isPresented: $showNewEstimate, onDismiss: {
            // A saved estimate opens next, so the tech reviews it and hands it over (TF-06).
            if let id = createdEstimateID { createdEstimateID = nil; openEstimate = OpenedEstimate(id: id, present: false) }
        }) { SheetSurface {
            if let job {
                NewEstimateView(customerID: job.customerId, jobID: job.id, title: job.title) { estimate in
                    createdEstimateID = estimate.id
                    Task { await loadJobEstimates(job) }
                }
            }
        } }
        .task(id: customerAuthorityToken) {
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
        .onAppear { if job != nil { Task { await load() } } }
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
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { dictation.stop() }
        }
        .onDisappear { dictation.stop() }
        .onChange(of: selectedTab) { previous, tab in
            if tab != "Activity" { dictation.stop(); noteFocused = false }
            if tab == "Money" { Task { await loadInvoices() } }
            // Photos added under Activity show in the Overview count straight away (JS-09).
            // Back on site from a note or the camera, the wrap-up rows read the job again.
            if previous == "Activity", activityFilter == "Photos" || (tab == "Overview" && isOnSite) {
                Task { await loadMediaCount(); await loadCloseout() }
            }
        }
        .onChange(of: activityFilter) { previous, _ in
            if previous == "Photos" { Task { await loadMediaCount() } }
        }
        .onChange(of: selectedInvoiceID) { _, selectedID in
            guard let selectedID, let invoice = invoices.first(where: { $0.id == selectedID }) else { return }
            Task { await loadInvoicePayments(for: invoice) }
        }
        .safeAreaInset(edge: .bottom) {
            Group {
            if job != nil, selectedTab == "Activity", !showsPhotos, session.can("job.note", feature: "jobs") {
                // JobActivity.dc.html: the composer stays at the bottom, quick notes above it.
                // Its ground runs past the home indicator to the screen's edge, so no timeline
                // scrolls visibly beneath it (the destination's bottom inset isn't always ignorable).
                composer.frame(maxWidth: .infinity)
                    .background(alignment: .top) {
                        Theme.card.padding(.bottom, -120).ignoresSafeArea()
                    }
            } else if !typeSize.isAccessibilitySize { primaryAction.environment(\.thorbisSheetCanvas, true) }
            }
            // 1pt in from each side, so every bar (Overview, Money, Activity's composer) sits inside
            // the job's sheet and the sheet's rim runs on to the bottom edge.
            .padding(.horizontal, 1)
        }
        .sheet(isPresented: $showPause) { SheetSurface {
            // v2 modal: two sunk fields, one ink commit in the sheet's pad. The commit is never
            // pre-disabled: pressing it says what is missing under the field. The form keeps what was typed.
            ThorbisModalSheet(title: "Pause job", closeLabel: "Cancel", onClose: { showPause = false },
                              detents: [.medium, .large], commitTitle: "Pause job", busy: busy,
                              commitIdentifier: "pause-commit", commit: { attemptPause() }) {
                ThorbisSheetField(label: "Why are you pausing?", error: pauseReasonProblem) {
                    TextField("Waiting on a part from the supplier", text: $reason, prompt: .placeholder("Waiting on a part from the supplier"), axis: .vertical)
                        .font(Theme.font(16)).lineLimit(2...5).fieldWell()
                }
                ThorbisSheetField(label: "What needs to happen next?", help: "The office sees both on the job.",
                                  error: pauseNextProblem ?? error) {
                    TextField("Order the 40/5 capacitor and book a return", text: $nextAction, prompt: .placeholder("Order the 40/5 capacitor and book a return"), axis: .vertical)
                        .font(Theme.font(16)).lineLimit(2...5).fieldWell()
                }
            }
            .interactiveDismissDisabled(busy || !reason.isEmpty || !nextAction.isEmpty)
        } }
        .sheet(isPresented: $showSchedule, onDismiss: { Task { await load() } }) { SheetSurface {
            if let job {
                JobScheduleView(job: job) { updatedJob in
                    self.job = updatedJob
                }
            }
        } }
        // A payment changes the balance the next step reads, wherever it was collected from.
        .sheet(isPresented: $showCollectPayment, onDismiss: { Task { await loadInvoices(); await loadCloseout() } }) {
            if let invoice = selectedInvoice, let model = invoicePaymentModel {
                InvoicePaymentCollectionSheet(model: model, invoice: model.invoice ?? invoice)
                    .thorbisSheetSurface()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    /// Native bar with Thorbis circles: our back on the left (`thorbisDestination`), share and
    /// the job's one menu on the right (HIG-005, JS-02).
    @ToolbarContentBuilder private var toolbarActions: some ToolbarContent {
        if let job, let context = contextLine(job) {
            // C-Job: where this job sits in the day, beside Back ("Today · Stop 3 of 6").
            ThorbisToolbarItem(placement: .principal) {
                Text(context)
                    .font(Theme.font(13, weight: .medium)).monospacedDigit()
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .accessibilityIdentifier("job-context")
            }
        }
        if let job {
            ThorbisToolbarItem(placement: .topBarTrailing) {
                // One quiet circle (Job.dc.html): Share job sits in the menu with the rest, so it is always there.
                ThorbisMenu(items: menuGroups(job).flatMap { $0 }.map { menuActionItem($0, job: job) } + [
                                ThorbisMenuItem("Share job", icon: "square.and.arrow.up") {
                                    shareJob = SharedText(JobShareText.text(title: job.title, customer: store.customerName(job.customerId),
                                                                            scheduledFor: job.scheduledFor))
                                }],
                            title: "Job actions", accessibilityLabel: "Job actions") {
                    PaperCircleLabel(symbol: "ellipsis", fill: Theme.card, bordered: true)
                }
            }
        }
    }

    /// The panel sheet the job sits in: radius 14 at the top, a 1px rim, down past the home indicator.
    private var jobSheet: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: Theme.cardRadius, topTrailingRadius: Theme.cardRadius, style: .continuous)
        return shape.fill(Theme.card)
            .overlay(shape.stroke(Theme.border.opacity(0.6), lineWidth: 1))
            .ignoresSafeArea(edges: .bottom)
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
            // The bar shows only on Overview; on the other tabs Wrap up stays in the menu.
            // On site the bar walks the wrap-up rows, so the closeout screen (checks, unpaid
            // follow-up, cancel) stays in the menu.
            barIsWrapUp: selectedTab == "Overview" && nextStep == .wrapUp && !onSiteWrapsUp,
            canShowToCustomer: session.can("estimate.view", feature: "estimates") || session.can("invoice.view", feature: "invoicing"),
            canEditCustomer: session.can("customer.edit", feature: "core_crm"),
            canAddToCalendar: JobFiltering.date(job.scheduledFor) != nil,
            canEmail: customerEmail(job) != nil))
    }

    /// The primary contact's email, else the account's, only while this customer's contacts are current.
    private func customerEmail(_ job: JobRecord) -> MailDraft? {
        guard customerContext(job) == contactsContext, contactsContext != nil else { return nil }
        let email = contacts.first(where: \.primary)?.email ?? contacts.first(where: { $0.email != nil })?.email ?? customerRecord?.email
        return MailDraft(recipient: email, subject: job.title)
    }

    private func menuActionItem(_ action: JobMenuAction, job: JobRecord) -> ThorbisMenuItem {
        switch action {
        case .transition(let target):
            return ThorbisMenuItem(transitionTitle(target), icon: transitionSymbol(target), isDisabled: busy) { runTransition(target) }
        case .schedule:
            return ThorbisMenuItem(job.scheduledFor == nil ? "Schedule" : "Reschedule", icon: "calendar") { showSchedule = true }
        case .addToCalendar:
            return ThorbisMenuItem("Add to Calendar", icon: "calendar.badge.plus") {
                handoff = JobCalendarDraft.make(job: job, customerName: store.customers.first { $0.id == job.customerId }?.name, locations: customerLocations).map(DeviceHandoff.calendar)
            }
        case .email:
            return ThorbisMenuItem("Email customer", icon: "envelope") { handoff = customerEmail(job).map(DeviceHandoff.mail) }
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
            return ThorbisMenuItem("Customer view", icon: "person.crop.rectangle") { openCustomerView(.home) }
        case .copyID:
            return ThorbisMenuItem("Copy job ID", icon: "doc.on.doc") { UIPasteboard.general.string = job.id }
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

    /// Cream sheet (C-Job.dc.html): the status pill (it opens the status popover), the street as the
    /// title, the problem and who, one meta line (when · who · job number · membership), the map
    /// strip, then Call, Text and Directions as labelled rimmed buttons. On site, what to know before
    /// going in sits right under the meta line. Rescheduling and assigning live in the ••• menu.
    private func fullHeader(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            statusControl(job)
            Text(displayTitle(job))
                .font(Theme.font(28, weight: .medium))
                .tracking(-0.6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("job-title")
            if let subtitle = headerSubtitle(job) {
                Text(subtitle)
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            Text(metaLine(job))
                .font(Theme.font(13)).monospacedDigit()
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
                .accessibilityIdentifier("job-number")
                // A long press copies the full ID (also in •••).
                .contextMenu { Button("Copy job ID", systemImage: "doc.on.doc") { UIPasteboard.general.string = job.id } }
            // On site, what to know before touching anything comes before every action.
            if isOnSite, let banner = accessBanner(job) {
                banner.padding(.top, 16)
            }
            MapStrip(pill: MapStrip.drive(minutes: eta.minutes, miles: nil), aspect: 350 / 96, pillAtBottom: true,
                     hasPlace: jobCoordinates(job) != nil || !customerLocations.isEmpty)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border.opacity(0.7), lineWidth: 1))
                .padding(.top, 16)
                .task(id: "eta|\(job.id)|\(shownStatus(job))|\(jobCoordinates(job).map { "\($0.latitude),\($0.longitude)" } ?? "")|\(session.isOffline)") {
                    let ahead = ["scheduled", "dispatched", "en_route"].contains(shownStatus(job))
                    await eta.update(to: jobCoordinates(job), key: "\(job.id)|\(job.locationId ?? "")", enabled: ahead && !session.isOffline)
                }
            reachCircles(job).padding(.top, 12)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    /// The job's own place, when its service location is on file with a position.
    private func jobCoordinates(_ job: JobRecord) -> FieldCoordinates? {
        guard let locationID = job.locationId else { return nil }
        return customerLocations.first { $0.id == locationID }?.coordinates
    }

    /// "10:30 a.m. · Ramon M. · JOB-2214 · Member 15% off": when, who, the job number, membership.
    private func metaLine(_ job: JobRecord) -> String {
        let arrived = isOnSite && outbox.pendingStatus(for: job.id) == nil ? JobFiltering.date(job.arrivedAt) : nil
        var parts: [String] = []
        if let arrived {
            parts.append("Arrived \(arrived.tradeTime)")
        } else if let scheduled = JobFiltering.date(job.scheduledFor) {
            parts.append(Calendar.current.isDateInToday(scheduled) ? scheduled.tradeTime : scheduled.visitLabel())
        } else if job.status != "completed", job.status != "canceled" {
            parts.append("Not scheduled")
        }
        if let assignee = assignedDisplayName(for: job) {
            parts.append(assignee == "Assigned" ? "Assigned" : shortName(assignee))
        } else {
            parts.append("Unassigned")
        }
        parts.append("JOB-\(job.id.suffix(4).uppercased())")
        if let memberPricing, memberPricing.isMember {
            parts.append(memberPricing.discountPercent > 0 ? "Member \(memberPricing.discountPercent)% off" : "Member")
        }
        return parts.joined(separator: " · ")
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

    /// The problem and who it is for, under the street.
    private func headerSubtitle(_ job: JobRecord) -> String? {
        let problem = street(job) == nil ? nil : job.title
        let customer = store.customerName(job.customerId)
        let parts = [problem, customer == "Customer" ? nil : customer].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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

    /// C-Job: Call, Text and Directions as labelled rimmed buttons, 12pt apart (stacked at accessibility
    /// sizes). Directions always require choosing an account location; no job site is inferred.
    private func reachCircles(_ job: JobRecord) -> some View {
        let phone = customerContext(job) == contactsContext ? customerPhone : nil
        let reach = JobReach(phone: phone, email: nil)
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Button { if let call = reach.call { openURL(call) } } label: {
                RimmedButtonLabel(title: "Call", symbol: "phone", enabled: reach.call != nil)
            }
            .buttonStyle(PressStyle())
            .disabled(reach.call == nil)
            .accessibilityLabel("Call \(store.customerName(job.customerId))")
            .accessibilityIdentifier("job-call")
            Button { if let text = reach.text { openURL(text) } } label: {
                RimmedButtonLabel(title: "Text", symbol: "message", enabled: reach.text != nil)
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
            Button { openURL(url) } label: { RimmedButtonLabel(title: "Directions", symbol: "arrow.triangle.turn.up.right.diamond") }
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
                RimmedButtonLabel(title: "Directions", symbol: "arrow.triangle.turn.up.right.diamond")
            }
            .accessibilityLabel("Directions")
            .accessibilityHint("Choose a customer location")
            .accessibilityIdentifier("job-directions")
        } else {
            RimmedButtonLabel(title: "Directions", symbol: "arrow.triangle.turn.up.right.diamond", enabled: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Directions, no address on file")
                .accessibilityIdentifier("job-directions")
        }
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
            // status, then the moves that stop or step back (Pause job…, Move back to scheduled).
            let current = shownStatus(job)
            let backward: Set<String> = ["paused", "scheduled"]
            let item = { (target: String) in
                ThorbisMenuItem(transitionTitle(target), status: StatusTone(jobStatus: target)) { runTransition(target) }
            }
            JobStatusMenu(groups: [[ThorbisMenuItem(current.statusLabel, status: StatusTone(jobStatus: current, hasTime: job.scheduledFor != nil),
                                                    isSelected: true) {}]
                                   + transitions.filter { !backward.contains($0) }.map(item),
                                   transitions.filter { backward.contains($0) }.map(item)],
                          title: "Status", accessibilityLabel: "Job status, \(current.statusLabel). Change status",
                          opensOnAppear: Self.previewOpensStatusMenu) {
                statusChip(job, showsMenu: true)
            }
        }
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
        // v2: a neutral pill; colour sits with the word as its small mark.
        return WrappingPropertyChip(text: statusWordText(job, queued: queued, now: now), tint: Theme.fill,
                                    textColor: Theme.foreground, showsChevron: showsMenu) {
            StatusDot(tone: tone, pending: queued != nil)
        }
    }

    private func statusWordText(_ job: JobRecord, queued: String?, now: Date) -> String {
        if let queued {
            return ["arrived", "in_progress"].contains(queued) ? "On site · waiting to sync" : "\(queued.statusLabel) · waiting to sync"
        }
        if ["arrived", "in_progress"].contains(job.status), let arrived = JobFiltering.date(job.arrivedAt) {
            return JobOnSiteClock.line(arrived: arrived, now: now)
        }
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
        let issued = invoices.filter { $0.status == "issued" && $0.currency == "USD" }
        guard !issued.isEmpty else { return nil }
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
        case "Overview": return isOnSite ? "On site" : "Overview"
        case "Money":
            guard let balance = invoiceBalanceCents, balance > 0 else { return "Money" }
            return "Money · \(jobShortMoney(balance, currency: "USD"))"
        default:
            let count = activityCount(job)
            return count > 0 ? "Activity · \(count)" : "Activity"
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

    /// The job's three sections as Linear text tabs; a menu at accessibility sizes.
    private func tabBar(_ job: JobRecord) -> some View {
        Group {
            if typeSize.isAccessibilitySize {
                ThorbisMenu(items: tabs.map { tab in
                    ThorbisMenuItem(sectionLabel(tab, job: job), isSelected: tab == selectedTab) { selectedTab = tab }
                }, title: "Job sections", accessibilityLabel: "Job sections, \(spokenSectionLabel(selectedTab, job: job))") {
                    HStack(spacing: 12) {
                        Text(sectionLabel(selectedTab, job: job)).font(Theme.font(15, weight: .medium))
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
                                  selection: $selectedTab)
                    .padding(.horizontal, Theme.gutter - 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    @ViewBuilder private var primaryAction: some View {
        if selectedTab == "Overview" {
            overviewBar
        } else if selectedTab == "Money" {
            moneyAction
        }
    }

    /// On site with the work started, the bar is the wrap-up: a status step (Start work, Resume)
    /// still leads while there is one.
    private var onSiteWrapsUp: Bool {
        guard isOnSite, let step = nextStep else { return false }
        if case .transition = step { return false }
        return true
    }

    /// C-Job's bar, in the sheet's pad: a note circle, a photo circle (the office's call circle on
    /// site), then the one ink commit for the next step. At accessibility sizes the circles sit on
    /// their own row above the commit.
    @ViewBuilder private var overviewBar: some View {
        let step = nextStep
        let canNote = session.can("job.note", feature: "jobs")
        let canPhoto = session.can("job.edit", feature: "jobs")
        if step != nil || canNote || canPhoto {
            let circles = HStack(spacing: 12) {
                if canNote { noteCircle }
                if canPhoto { cameraCircle }
                if onSiteWrapsUp { callCircle }
            }
            VStack(spacing: 10) {
                if typeSize.isAccessibilitySize {
                    circles.frame(maxWidth: .infinity, alignment: .leading)
                    if let step { commitButton(step) }
                } else {
                    HStack(spacing: 12) {
                        circles
                        if let step { commitButton(step) } else { Spacer(minLength: 0) }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
            .background(Theme.canvas)
        }
    }

    /// The note circle: opens Activity with the note field focused, ready to type or dictate.
    private var noteCircle: some View {
        Button { openNoteTool() } label: { CreamCircleLabel(symbol: "note.text", size: 44) }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Add a note")
            .accessibilityHint("Opens the note composer in Activity")
            .accessibilityIdentifier("job-bar-note")
    }

    /// The bar's camera: the job's photos open straight into the camera.
    private var cameraCircle: some View {
        Button { openCapture(.camera(stage: nil)) } label: { CreamCircleLabel(symbol: "camera", size: 44) }
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
                    if busy || creatingInvoice { ProgressView().tint(Theme.onInk) }
                    else { Image(systemName: canCompleteHere && next == nil ? "checkmark" : "checkmark.seal").font(.subheadline.weight(.medium)).accessibilityHidden(true) }
                    commitLabel(rows)
                }
                .inkCommit(height: 44)
            }
            .buttonStyle(PressStyle())
            .disabled(busy || creatingInvoice)
            .accessibilityLabel(commitTitle(rows))
            .accessibilityHint(next.map { "Opens \($0.title.lowercased())" } ?? (canCompleteHere ? "Completes the job" : "Opens the closeout checklist"))
            .accessibilityIdentifier("job-commit")
        } else {
            Button { run(step) } label: {
                HStack(spacing: 7) {
                    if busy || creatingInvoice { ProgressView().tint(Theme.onInk) }
                    else { Image(systemName: step.symbol).font(.subheadline.weight(.medium)).accessibilityHidden(true) }
                    Text(step.title(resuming: job?.status == "paused"))
                }
                .inkCommit(height: 44)
            }
            .buttonStyle(PressStyle())
            .disabled(busy || creatingInvoice)
            .accessibilityIdentifier("job-next-step")
        }
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
        if left > 0 { return "Wrap up · \(left) left" }
        return canCompleteHere ? "Complete job" : "Wrap up job"
    }

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
            Button { openURL(url) } label: { CreamCircleLabel(symbol: "phone", size: 44) }
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
            PaperInvoiceCollectionFooter(model: model) { showCollectPayment = true }
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

    /// Job.dc.html: the visit in the order a tech needs it at the door, each section one panel.
    /// On site (OnSite.dc.html) the toolkit and what's left before wrapping up come first; every
    /// other section stays below, so nothing the Overview had is out of reach. Every action that
    /// isn't the bar's next step is in the ••• menu at the top right.
    private func overviewContent(_ job: JobRecord) -> some View {
        // OnSite.dc.html sets its blocks 18pt apart; Job.dc.html 22.
        VStack(alignment: .leading, spacing: isOnSite ? 18 : 22) {
            if isOnSite {
                toolkit(job).id("job-toolkit")
                wrapUpPanel(job).id("job-wrap-up")
                partsPanel
            }
            // C-Job: what to know at this address, then the money, then who it is for.
            JobPropertyHistorySection(job: job, part: .place, locations: customerLocations,
                                      locationsLoaded: customerContext(job) != nil && customerContext(job) == locationsContext,
                                      visits: visits, visitsLoaded: visitsLoaded,
                                      showsFacts: !(isOnSite && accessBanner(job) != nil))
                .id("job-property-history")
            moneyPanel(job)
            customerPanel(job)
            photosStrip(job)
            latestActivity(job).id("job-latest-activity")
            // Left out once the visits answer with none here, so an empty section adds no gap above Money.
            if !visitsLoaded || !JobPropertyHistory.make(job: job, locations: [], equipment: [], visits: visits, listedJobs: store.jobs,
                                                         currentUserID: session.user?.id).visits.isEmpty {
                JobPropertyHistorySection(job: job, part: .visits, locations: customerLocations,
                                          locationsLoaded: customerContext(job) != nil && customerContext(job) == locationsContext,
                                          visits: visits, visitsLoaded: visitsLoaded)
            }
            followUpsPanel
            // JS-05: only when the platform recorded the call that booked this job.
            if let bookingCall { JobBookingCallSection(call: bookingCall) }
            if session.can("customer.view", feature: "core_crm") {
                let current = customerContext(job) != nil && customerContext(job) == contactsContext
                JobContactsSection(people: JobContacts.people(contacts: current ? contacts : [], customer: current ? customerRecord : nil),
                                   preference: JobContacts.preference(current ? customerRecord : nil),
                                   loaded: current && contactsLoaded, failed: current && contactsFailed,
                                   customerID: job.customerId,
                                   customerName: linkedCustomer(job)?.name) { await loadContacts(job) }
                let placesCurrent = customerContext(job) != nil && customerContext(job) == locationsContext
                JobServiceAddressesSection(customerID: job.customerId, places: customerLocations,
                                           loaded: placesCurrent, failed: locationsFailed,
                                           headerStreet: displayTitle(job),
                                           factsShownFor: JobPropertyHistory.accessPlace(job: job, locations: customerLocations)?.id) { await loadLocations(job) }
            }
            CustomerMembershipSection(customerID: job.customerId, editable: false, jobID: job.id)
            detailsGroup(job).id("job-details")
        }
    }

    /// Who the job is for (with membership and the account at a glance, opening their profile),
    /// then why the office sent the visit, and the pause reason when it's paused.
    private func customerPanel(_ job: JobRecord) -> some View {
        let officeNote = job.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // v2: no "Customer" label; the name and avatar already say whose job it is.
        return VStack(alignment: .leading, spacing: 6) {
        JobPanel {
            if let customer = linkedCustomer(job) {
                NavigationLink(value: customer) { customerRow(job, name: customer.name, opens: true) }
                    .buttonStyle(RowPressStyle())
                    .accessibilityIdentifier("job-customer-link")
                    .accessibilityHint("Opens the customer's profile")
            } else {
                customerRow(job, name: store.customerName(job.customerId), opens: false)
            }
            // Hands the phone to the customer for their estimates, invoices and details.
            Button { openCustomerView(.home) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "iphone").font(.system(size: 16, weight: .medium)).frame(width: 36)
                        .accessibilityHidden(true)
                    Text("Show customer").font(Theme.font(15, weight: .medium))
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Theme.foreground.opacity(canOpenCustomerView ? 1 : 0.4))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .disabled(!canOpenCustomerView)
            .accessibilityLabel("Show customer")
            .accessibilityHint("Hands the device to the customer for their estimates, invoices and details")
            .accessibilityIdentifier("job-customer-view")
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
            if !officeNote.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("From the office").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                        .accessibilityHidden(true)
                    Text(officeNote)
                        .font(Theme.font(15)).foregroundStyle(Theme.foreground).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityLabel("From the office: \(officeNote)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
        // A container, so the link inside keeps its own `job-customer-link` identifier.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("job-customer-panel")
        }
    }

    private func customerRow(_ job: JobRecord, name: String, opens: Bool) -> some View {
        HStack(spacing: 12) {
            InitialsAvatar(name: name, size: 36).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = customerDetail(job) {
                    Text(detail).font(Theme.font(14)).foregroundStyle(Theme.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if opens {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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
        VStack(alignment: .leading, spacing: 6) {
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
        let entries = timeline(job, filter: "All")
        let latest = Array(entries.prefix(2))
        return JobPanelSection(title: "Latest activity", actionTitle: entries.isEmpty ? nil : "See all \(entries.count)",
                               actionIdentifier: "job-latest-activity-all",
                               action: { activityFilter = "All"; withMotion(.snappy) { selectedTab = "Activity" } },
                               dividers: false) {
            if entries.isEmpty {
                JobPanelRow(title: "Nothing yet", subtitle: "Notes, status changes and photos show up here.", titleSize: 15)
            }
            ForEach(Array(latest.enumerated()), id: \.element.id) { index, entry in
                timelineRow(entry, showsDay: true, isFirst: index == 0, isLast: index == latest.count - 1)
            }
        }
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
                    moneyLine(options.isEmpty ? "Estimate EST-\(estimate.id.suffix(4).uppercased())" : "Estimate · \(options.count) \(options.count == 1 ? "option" : "options")",
                              amount: options.isEmpty ? paperLinesTotal(estimate.lines).map { jobShortMoney($0, currency: estimate.lines.first?.unitPrice.currency ?? "USD") } : nil,
                              word: word, tint: tint)
                }
                ForEach(bills) { invoice in
                    let due = TechJobFlow.due(invoice)
                    let (word, tint) = invoiceWord(invoice, due: due)
                    let amount = invoice.status == "issued" ? due : paperLinesTotal(invoice.lines)
                    moneyLine("Invoice INV-\(invoice.id.suffix(4).uppercased())",
                              amount: amount.map { jobShortMoney($0, currency: invoice.currency) }, word: word, tint: tint)
                }
                if estimates.isEmpty && bills.isEmpty {
                    if loading { SkeletonRows(count: 1, leading: false, inset: 16) }
                    else { JobPanelRow(title: "No estimates or invoices yet", titleSize: 15) }
                }
                if let balance = invoiceBalanceCents, balance > 0 {
                    // What is owed now, in the type colour; it opens Money.
                    Button { withMotion(.snappy) { selectedTab = "Money" } } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("Due on site").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                            Spacer(minLength: 8)
                            Text(jobShortMoney(balance, currency: "USD")).font(Theme.monoFont(15, weight: .medium))
                                .foregroundStyle(Theme.foreground)
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
        .accessibilityElement(children: .combine)
    }

    private func estimateWord(_ status: String) -> (String, StatusTone) {
        switch status {
        case "approved": ("Approved", .done)
        case "sent": ("Sent", .dispatched)
        case "declined": ("Declined", .attention)
        default: (status.statusLabel, .unscheduled)
        }
    }

    private func invoiceWord(_ invoice: InvoiceRecord, due: Int?) -> (String, StatusTone) {
        switch invoice.status {
        case "issued": (due ?? 0) > 0 ? ("Unpaid", .inProgress) : ("Issued", .unscheduled)
        case "paid": ("Paid", .done)
        default: (invoice.status.statusLabel, .unscheduled)
        }
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
    private func toolkit(_ job: JobRecord) -> some View {
        let canCapture = session.can("job.edit", feature: "jobs")
        // Four across at standard sizes; three once words like "Return visit" stop fitting a quarter
        // of the row; two at accessibility sizes so every word stays whole.
        let columns = typeSize.isAccessibilitySize ? 2 : typeSize >= .xLarge ? 3 : 4
        return VStack(alignment: .leading, spacing: 6) {
        JobPanelLabel(title: "Tools")
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: columns), spacing: 8) {
            JobToolTile(title: "Photo", symbol: "camera", enabled: canCapture && UIImagePickerController.isSourceTypeAvailable(.camera),
                        hint: "Opens the camera and adds the photo to this job") { openCapture(.camera(stage: nil)) }
            JobToolTile(title: "Note", symbol: "square.and.pencil", enabled: session.can("job.note", feature: "jobs"),
                        hint: "Type or dictate a note") { openNoteTool() }
            JobToolTile(title: "Measure", symbol: "ruler", enabled: canCapture && SiteMeasure.isSupported,
                        hint: "Measure with the camera and add it as a photo") { openCapture(.measure) }
            // The equipment data plate; the document scanner stays in Photos' add-a-document menu.
            JobToolTile(title: "Scan tag", symbol: "barcode.viewfinder", enabled: canCapture,
                        hint: "Reads the equipment's data plate into the customer's equipment") { showScan = true }
            JobToolTile(title: "Checklist", symbol: "checklist", hint: "Opens this visit's checklist") { showChecklist = true }
            JobToolTile(title: "Add part", symbol: "shippingbox", enabled: canAddPart,
                        hint: "Adds price book items to the job's draft invoice") { Task { await addPart() } }
            JobToolTile(title: "Estimate", symbol: "doc.text",
                        enabled: canBuildEstimate || session.can("estimate.view", feature: "estimates"),
                        hint: jobEstimates.isEmpty ? "Builds an estimate" : "Opens the job's estimates") { openEstimateTool() }
            JobToolTile(title: "Return visit", symbol: "calendar.badge.plus", enabled: session.can("job.edit", feature: "jobs"),
                        hint: "Asks the office to book a return visit") { followUpKind = .officeScheduling; showFollowUps = true }
        }
        .accessibilityIdentifier("job-toolkit")
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
            JobPanelSection(title: "On the invoice", count: "\(bill.lines.count)", actionTitle: editable ? "Add" : nil,
                            actionIdentifier: "job-parts-add", action: { partsInvoice = bill }) {
                // Each line with its quantity and amount, two decimals, tabular (one VoiceOver stop per line).
                JobInvoiceLineRows(lines: bill.lines, currency: bill.currency)
                    .padding(.vertical, 4)
            }
        }
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
            DisclosureGroup("More job details") {
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
            }
            .font(Theme.font(15, weight: .medium))
            .tint(Theme.foreground)
            .frame(minHeight: 44)
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        }
    }

    /// Money: the job's estimates, then its invoices. Each paper shows its own amount once; what's
    /// owed across them is on Overview and in the bar, never repeated in a header.
    private func moneyContent(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            estimatesContent(job)
            invoiceContent(job)
        }
    }

    /// Every estimate has its own paper and price; the footer builds another on this job.
    private func estimatesContent(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !session.can("estimate.view", feature: "estimates") {
                PaperEmptyState(symbol: "lock", title: "Estimates are off for your role", message: "Ask your office for access to estimates.")
            } else {
                let unavailable = estimateRead?.unavailableIDs ?? []
                // At accessibility sizes "Add estimate" goes under the label so neither breaks mid-word.
                JobPanelLabel(title: "Estimates", count: jobEstimates.count + unavailable.count > 0 ? "\(jobEstimates.count + unavailable.count)" : nil,
                              actionTitle: canBuildEstimate ? "Add estimate" : nil, actionIdentifier: "job-add-estimate",
                              action: buildEstimate)
                if !estimatesLoaded {
                    SkeletonRows(count: 2, leading: false, inset: 0)
                } else if jobEstimates.isEmpty && !estimatesFailed && unavailable.isEmpty {
                    PaperEmptyState(symbol: "doc.text", title: "No estimates on this job",
                                    message: "Build one from the price book.")
                }
                if !jobEstimates.isEmpty || !unavailable.isEmpty {
                    JobPanel {
                        ForEach(jobEstimates) { estimate in
                            NavigationLink { EstimateDetailView(id: estimate.id, jobID: jobId).thorbisBackButton() } label: {
                                JobDocumentRow(estimate: estimate, fresh: estimateRead?.freshIDs.contains(estimate.id) == true).onWell()
                            }
                            .buttonStyle(RowPressStyle())
                            .accessibilityIdentifier("job-estimate-\(estimate.id)")
                            .disabled(estimateRead?.freshIDs.contains(estimate.id) != true)
                        }
                        ForEach(unavailable, id: \.self) { id in
                            JobDocumentRow(reference: "EST-\(id.suffix(4).uppercased())", title: "Estimate unavailable",
                                           status: "unavailable", amount: nil, fresh: false).onWell()
                                // A container keeps the id on the card itself; without one it lands on each text.
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("job-estimate-unavailable-\(id)")
                        }
                    }
                }
                // When the bar is busy with the invoice, the estimates' customer door stays here, quieter.
                if !jobEstimates.isEmpty, !moneyBarIsCustomerView, canOpenCustomerView {
                    // A quiet text button: the screen's one ink commit stays the bar at the bottom.
                    Button { openCustomerView(.estimates) } label: {
                        Label("Show customer", systemImage: "iphone")
                            .font(Theme.font(15, weight: .medium))
                            .foregroundStyle(Theme.foreground)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityHint("Shows this job's estimates to the customer")
                    .accessibilityIdentifier("job-money-customer-view")
                }
                if let summary = JobEstimateSummary(records: jobEstimates, complete: estimateRead?.isComplete == true) {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(summary.amounts) { amount in
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text("\(amount.status == "approved" ? "Approved work" : "Awaiting approval") · \(amount.currency)")
                                        .foregroundStyle(Theme.muted)
                                    Spacer(minLength: 8)
                                    Text(money(amount.cents, currency: amount.currency)).moneyStyle(.row)
                                }
                                .accessibilityElement(children: .contain)
                            }
                            if summary.approvedUnavailable {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Approved total unavailable")
                                    Text("Open approved estimates to review their amounts.")
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                            if summary.optionCount > 0 {
                                Text("\(summary.optionCount) \(summary.optionCount == 1 ? "estimate has" : "estimates have") pricing options. Review those options separately.")
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                        .padding(.top, 12)
                    } label: { Text("Estimate totals") }
                    .font(Theme.font(15))
                    .tint(Theme.foreground)
                    .padding(.horizontal, RecordRoom.labelInset).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .task(id: job.id) { await loadJobEstimates(job) }
    }

    private func scope(for job: JobRecord) -> JobDocumentScope? {
        guard job.id == jobId, job.organizationId == session.activeOrganization?.id else { return nil }
        return JobDocumentScope(jobID: job.id, organizationID: job.organizationId,
                                customerID: job.customerId, originEstimateID: job.estimateId)
    }

    private var documentReadIssue: String? {
        if estimatesFailed && invoicesFailed { return "Couldn't load all estimates and invoices for this job." }
        return estimateRead?.issue ?? invoiceRead?.issue
    }

    private func loadJobEstimates(_ job: JobRecord) async {
        guard session.can("estimate.view", feature: "estimates"), let scope = scope(for: job) else {
            documents.clearEstimates()
            return
        }
        let generation = session.generation
        let published = await documents.loadEstimates(scope: scope, api: api) {
            session.generation == generation && session.activeOrganization?.id == scope.organizationID &&
                self.job?.id == scope.jobID && self.job?.customerId == scope.customerID
        }
        guard session.generation == generation, published else { return }
    }

    private func invoiceContent(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            if !session.can("invoice.view", feature: "invoicing") {
                emptyCard("Invoice access is unavailable.")
            } else if !invoicesLoaded {
                SkeletonRows(count: 3, leading: false, inset: 0)
            } else if invoices.isEmpty && !invoicesFailed {
                VStack(alignment: .leading, spacing: 6) {
                    JobPanelLabel(title: "Invoices")
                    if session.can("invoice.create", feature: "invoicing") || (job.estimateId != nil && session.can("invoice.create", feature: "progress_billing")) {
                        JobPanel {
                            if session.can("invoice.create", feature: "invoicing") {
                                Button { Task { await createInvoice() } } label: {
                                    PaperMenuRow(creatingInvoice ? "Creating…" : "Create invoice", symbol: "doc.plaintext",
                                                 subtitle: "Lines come from the approved estimate; edit them before sending")
                                        .padding(.horizontal, 16)
                                }
                                .buttonStyle(RowPressStyle())
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
                VStack(alignment: .leading, spacing: 6) {
                    JobPanelLabel(title: "Invoices", count: invoices.isEmpty ? nil : "\(invoices.count)")
                    JobPanel {
                        ForEach(invoices) { invoice in
                            Button {
                                selectedInvoiceID = invoice.id
                                documentInvoiceID = invoice.id
                            } label: {
                                JobDocumentRow(invoice: invoice, fresh: invoiceRead?.freshIDs.contains(invoice.id) == true).onWell()
                            }
                            .buttonStyle(RowPressStyle())
                            .accessibilityIdentifier("job-invoice-\(invoice.id)")
                            .disabled(invoiceRead?.freshIDs.contains(invoice.id) != true)
                            // What the invoice is for: each line, its quantity and amount, two
                            // decimals, tabular (design.thorbis.com "Money is two decimals").
                            if !invoice.lines.isEmpty, invoiceRead?.freshIDs.contains(invoice.id) == true {
                                JobInvoiceLineRows(lines: invoice.lines, currency: invoice.currency)
                                    .padding(.bottom, 6)
                            }
                        }
                    }
                }
            }
        }
    }

    private var selectedInvoice: InvoiceRecord? {
        invoiceRead?.preferredInvoice(id: selectedInvoiceID)
    }

    private func updateInvoice(_ updated: InvoiceRecord) {
        documents.replaceInvoice(updated)
    }

    /// JobActivity.dc.html: one "Showing all ▾" menu instead of a row of filter chips.
    private func activityFilterMenu() -> some View {
        ThorbisMenu(items: activityFilters.map { filter in
            ThorbisMenuItem(filter == "All" ? "Everything" : filter, isSelected: filter == activityFilter) {
                withMotion(.snappy) { activityFilter = filter }
            }
        }, title: "Show", accessibilityLabel: "Activity filter, showing \(activityFilter == "All" ? "all" : activityFilter.lowercased())") {
            HStack(spacing: 4) {
                Text("Showing \(activityFilter == "All" ? "all" : activityFilter.lowercased())")
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .medium))
            }
            .font(Theme.font(13, weight: .medium))
            .foregroundStyle(Theme.foreground)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("activity-filter")
    }

    /// A day's label with the filter on the right, the way the first panel of Activity reads.
    private func activityFilterLabel(title: String, count: Int? = nil) -> some View {
        HStack(spacing: 8) {
            (Text(title).font(Theme.font(15, weight: .medium)) + Text(count.map { "  \($0)" } ?? "").font(Theme.font(15)))
                .monospacedDigit()
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            activityFilterMenu()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, -7)
        .frame(minHeight: 30)
    }

    /// Day-grouped timeline (Linear's activity): each day under its header, its entries on one
    /// thin line with a small glyph per kind; photos inline as thumbnails. The composer is pinned
    /// at the bottom of the screen (see `composer`).
    private func activityContent(_ job: JobRecord) -> some View {
        let days = activityDays(job)
        return VStack(alignment: .leading, spacing: 18) {
            if days.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    activityFilterLabel(title: "Activity")
                    PaperEmptyState(symbol: "clock", title: "No activity yet",
                                    message: "Status changes, notes and photos on this job show up here.")
                }
            }
            ForEach(Array(days.enumerated()), id: \.element.day) { index, group in
                VStack(alignment: .leading, spacing: 2) {
                    if index == 0 { activityFilterLabel(title: dayTitle(group.day), count: group.entries.count) }
                    else { JobPanelLabel(title: dayTitle(group.day), count: "\(group.entries.count)") }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(group.entries.enumerated()), id: \.element.id) { position, entry in
                            timelineRow(entry, showsDay: false, isFirst: position == 0, isLast: position == group.entries.count - 1, inset: 4)
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
        return JobTimelineItem(kind: entry.subject.kind, title: entry.title, pending: entry.id.hasPrefix("queued-"),
                               isFirst: isFirst, isLast: isLast) {
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    if let body = entry.body, !body.isEmpty {
                        // Long notes fold to four lines with "More"; nothing is cut off for good.
                        ExpandableNoteText(text: body, lines: 4)
                    }
                    if !entry.photos.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(entry.photos.prefix(3)) { photo in
                                Color.clear.frame(width: 64, height: 64)
                                    .overlay(MediaThumbnail(record: photo))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                        .padding(.top, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(-1)
                Text(timeLabel(entry.date, showsDay: showsDay))
                    .font(Theme.monoFont(13)).foregroundStyle(Theme.muted)
                    .fixedSize()
            }
        }
        .padding(.horizontal, inset)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        // One spoken item: when, what happened (and who), then the whole note, never the folded part.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([timeLabel(entry.date, showsDay: showsDay), entry.title, entry.body]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
    }

    /// JobActivity.dc.html: quick notes, then the field with the mic and a camera circle. Send
    /// takes the camera's place once there is something to save.
    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            QuickNotesRow { phrase in note = NoteDraftText.joined(note, phrase) }
                .disabled(dictation.isListening)
                .padding(.horizontal, Theme.gutter)
            HStack(alignment: .bottom, spacing: 8) {
                TextField(dictation.isListening ? "Listening…" : "Add a note", text: $note, prompt: .placeholder(dictation.isListening ? "Listening…" : "Add a note"), axis: .vertical)
                    .font(Theme.font(16))
                    .lineLimit(1...6)
                    .focused($noteFocused)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .panelBackground(cornerRadius: 23)
                    .accessibilityIdentifier("job-note-field")
                DictateNoteButton(isListening: dictation.isListening) {
                    if dictation.isListening { dictation.stop(); return }
                    Task { await dictation.start(draft: note, isOffline: session.isOffline) { note = $0 } }
                }
                if canSaveNote || busy {
                    Button { dictation.stop(); Task { await saveNote() } } label: {
                        Group { if busy { ProgressView().tint(Theme.onInk) } else { Image(systemName: "arrow.up").font(.system(size: 17, weight: .medium)) } }
                            .foregroundStyle(Theme.onInk).frame(width: 44, height: 44)
                            .background(Theme.ink.opacity(canSaveNote ? 1 : 0.35), in: Circle())
                    }
                    .buttonStyle(PressStyle())
                    .disabled(!canSaveNote || busy)
                    .accessibilityLabel("Save note")
                } else if session.can("job.edit", feature: "jobs") {
                    Button { openCapture(.camera(stage: nil)) } label: {
                        Image(systemName: "camera").font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.foreground)
                            .frame(width: 44, height: 44)
                            .background(Theme.well, in: Circle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Add photo")
                    .accessibilityIdentifier("job-composer-camera")
                }
            }
            .padding(.horizontal, Theme.gutter)
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
                .padding(.horizontal, Theme.gutter)
            }
        }
        .padding(.top, 10).padding(.bottom, 8)
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
        if filter == "All" || filter == "Estimates", session.can("estimate.view", feature: "estimates") {
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
        Text(message).font(Theme.font(13)).foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
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
        JobEstimateCreation.canOpen(canCreate: session.can("estimate.create", feature: "estimates"),
                                    canView: session.can("estimate.view", feature: "estimates"),
                                    estimatesComplete: estimateRead?.isComplete == true)
    }

    private var canOpenCustomerView: Bool {
        session.can("estimate.view", feature: "estimates") || session.can("invoice.view", feature: "invoicing")
            || session.can("customer.edit", feature: "core_crm")
    }

    /// Customer view: the job's one protected customer handoff (estimates, invoices, the customer's
    /// own details) with one staff hand-back. Every customer-facing door on the job opens it.
    private func openCustomerView(_ start: CustomerViewStart) {
        guard let job, scope(for: job) != nil, canOpenCustomerView else { return }
        let model = JobEstimateHandoffModel(job: job, customerName: store.customerName(job.customerId), documents: documents, api: api, session: session)
        let details = session.can("customer.edit", feature: "core_crm") ? CustomerSelfEditModel(customerID: job.customerId) : nil
        let originalScope = model.scope, actorID = session.user?.id
        let generation = session.generation, apiGeneration = api.requestGeneration, origin = api.normalizedOrigin
        let current: @MainActor () -> Bool = { [weak api, weak session] in
            guard let api, let session else { return false }
            return session.user?.id == actorID && session.activeOrganization?.id == originalScope.organizationID &&
                session.generation == generation && api.requestGeneration == apiGeneration && api.normalizedOrigin == origin &&
                session.can("job.view", feature: "jobs")
        }
        estimateHandoffPresenter.present(model, start: start, details: details, sourceGeneration: documentGeneration,
                                         invoiceUpdated: updateInvoice) { exit in
            guard current() else { return }
            // The customer may have changed a phone, an email or a contact in their own hands.
            await loadContacts(job)
            if case .collect(let invoiceID) = exit { customerPaymentInvoiceID = invoiceID }
            await finishCustomerDocuments()
        }
    }

    private func buildEstimate() {
        guard canBuildEstimate, let job, scope(for: job) != nil else { return }
        showNewEstimate = true
    }

    private func run(_ step: TechJobStep) {
        switch step {
        case .transition(let target): runTransition(target)
        case .buildEstimate: buildEstimate()
        case .presentEstimates: openCustomerView(.estimates)
        case .showEstimate(let id): openEstimate = OpenedEstimate(id: id, present: true)
        case .createInvoice:
            Task {
                // TF-08: one tap makes the invoice from the approved work and opens it for review.
                if let invoice = await createInvoice() { reviewInvoiceID = invoice.id }
            }
        case .reviewInvoice(let id): reviewInvoiceID = id
        case .collect(let invoiceID, _, _):
            Task {
                selectedInvoiceID = invoiceID
                if let invoice = invoices.first(where: { $0.id == invoiceID }) { await loadInvoicePayments(for: invoice) }
                if invoicePaymentModel?.canRecordPayment == true { showCollectPayment = true }
                else { withMotion(.snappy) { selectedTab = "Money" } }
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
        case "paused": "Pause job…"
        case "en_route": "On my way"
        case "arrived": "Arrive"
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
        guard session.can("invoice.view", feature: "invoicing"), let job, let scope = scope(for: job) else {
            documents.clearInvoices()
            return
        }
        let generation = session.generation
        let published = await documents.loadInvoices(scope: scope, api: api) {
            session.generation == generation && session.activeOrganization?.id == scope.organizationID &&
                self.job?.id == scope.jobID && self.job?.customerId == scope.customerID
        }
        guard session.generation == generation, published else { return }
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
        do {
            let invoice = try await api.ensureFieldCompletionInvoice(jobId)
            guard session.generation == generation, session.activeOrganization?.id == scope.organizationID else { return nil }
            guard scope.contains(invoice) else {
                throw Problem(title: "Invoice could not be verified for this job", status: nil, detail: nil)
            }
            JobInvoiceMemory.remember(invoice.id, jobID: jobId)
            selectedInvoiceID = invoice.id
            await loadInvoices()
            committed += 1
            return invoice
        } catch is CancellationError { return nil } catch { self.error = error.localizedDescription; return nil }
    }

    private func finishCustomerDocuments() async {
        let requestedID = customerPaymentInvoiceID
        customerPaymentInvoiceID = nil
        let generation = session.generation
        if let job { await loadJobEstimates(job) }
        await loadInvoices()
        guard session.generation == generation, let requestedID,
              session.can("invoice.payment.create", feature: "payments"),
              invoiceRead?.freshIDs.contains(requestedID) == true,
              let invoice = invoices.first(where: { $0.id == requestedID }) else { return }
        selectedInvoiceID = requestedID
        await loadInvoicePayments(for: invoice)
        guard session.generation == generation, loadedInvoiceModelID == requestedID,
              let actual = invoicePaymentModel?.invoice, actual.id == requestedID,
              let job, scope(for: job)?.contains(actual) == true,
              invoicePaymentModel?.canRecordPayment == true else { return }
        showCollectPayment = true
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
        await invoicePaymentModel?.load()
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
    private func loadContacts(_ job: JobRecord) async {
        guard let context = customerContext(job) else { return }
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
            let account = try? await api.fieldCustomer(job.customerId)
            guard stillCurrent() else { return }
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
        await loadCloseout()
        if isOnSite, officeContact == nil {
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
        let why = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = nextAction.trimmingCharacters(in: .whitespacesAndNewlines)
        pauseReasonProblem = why.isEmpty ? "Say why the job is paused." : (reason.utf16.count > 2000 ? "Keep it under 2,000 characters." : nil)
        pauseNextProblem = next.isEmpty ? "Say what needs to happen next." : (nextAction.utf16.count > 2000 ? "Keep it under 2,000 characters." : nil)
        guard pauseReasonProblem == nil, pauseNextProblem == nil, !busy else { return }
        Task { await pause() }
    }

    private func pause() async {
        if await progress(.pause(reason: reason.trimmingCharacters(in: .whitespacesAndNewlines), nextAction: nextAction.trimmingCharacters(in: .whitespacesAndNewlines))) {
            showPause = false
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

/// Where the visit is, in five steps: booked, on the way, on site, working, done.
/// An estimate opened from the job; `present` hands it to the customer as soon as it loads.
struct OpenedEstimate: Identifiable, Hashable {
    let id: String
    let present: Bool
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
