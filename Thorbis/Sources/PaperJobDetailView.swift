import SwiftUI
import UIKit

struct JobDetailView: View {
    let jobId: String
    let showsBack: Bool

    init(jobId: String, showsBack: Bool = true) {
        self.jobId = jobId
        self.showsBack = showsBack
        #if DEBUG
        let previewTabs = ["job-invoice": "Invoice", "job-estimates": "Estimates", "job-activity": "Activity", "job-media": "Photos", "job-invoice-empty": "Invoice"]
        _selectedTab = State(initialValue: PaperPreview.enabled ? previewTabs[PaperPreview.screen] ?? "Overview" : "Overview")
        #endif
    }
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @EnvironmentObject var session: SessionController
    @EnvironmentObject var outbox: FieldOutbox
    @Environment(\.dismiss) private var dismiss
    @State private var job: JobRecord?
    @State private var showCustomerMode = false
    @State private var notes: [JobNoteRecord] = []
    @State private var note = ""
    @State private var reason = ""
    @State private var nextAction = ""
    @State private var showPause = false
    @State private var busy = false
    @State private var error: String?
    @State private var selectedTab = "Overview"
    @State private var invoiceRead: JobDocumentRead<InvoiceRecord>?
    private var invoices: [InvoiceRecord] { invoiceRead?.records ?? [] }
    private var invoicesLoaded: Bool { invoiceRead != nil }
    private var invoicesFailed: Bool { invoiceRead?.isComplete == false }
    @State private var selectedInvoiceID: String?
    @State private var invoicePaymentModel: InvoicePaymentCollectionModel?
    @State private var loadedInvoiceModelID: String?
    @State private var showCollectPayment = false
    @State private var activityFilter = "All"
    @State private var showSchedule = false
    @State private var estimateRead: JobDocumentRead<EstimateRecord>?
    private var jobEstimates: [EstimateRecord] { estimateRead?.records ?? [] }
    private var estimatesLoaded: Bool { estimateRead != nil }
    private var estimatesFailed: Bool { estimateRead?.isComplete == false }
    @State private var showNewEstimate = false
    @State private var committed = 0
    @State private var creatingInvoice = false
    @State private var reviewInvoiceID: String?
    @State private var showDeposit = false
    /// TF-01: the estimate opened from the next step; it goes straight to the customer when asked.
    @State private var openEstimate: OpenedEstimate?
    /// Set by a new estimate's save, opened once its sheet has closed (TF-06).
    @State private var createdEstimateID: String?
    @State private var showWrapUp = false
    /// The customer's service locations; the first (or only) one is where the job is.
    @State private var locations: [ServiceLocationRecord] = []
    /// The primary contact's phone (else the customer's), for one-tap Call and Text.
    @State private var customerPhone: String?
    /// JS-06: every contact on the account, and the account for its preferred channel.
    @State private var contacts: [CustomerContactRecord] = []
    @State private var customerRecord: CustomerRecord?
    @State private var contactsLoaded = false
    @State private var contactsFailed = false
    /// JS-09/JS-10: this visit in counts, and the customer's other visits. Nil until read.
    @State private var followUps: [FieldFollowUpRecord]?
    @State private var mediaCount: Int?
    @State private var visits: [JobVisitRecord] = []
    @State private var bookingCall: BookingCallRecord?
    @State private var showAssign = false
    @State private var showFollowUps = false
    @Environment(\.openURL) private var openURL

    private let tabs = ["Overview", "Estimates", "Invoice", "Photos", "Activity"]

    private var liveActivityKey: String {
        guard let job else { return "" }
        return [job.id, job.status, outbox.pendingStatus(for: job.id) ?? "", locations.first?.address ?? ""].joined(separator: "|")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OfflineBanner().padding(.top, 4)
            if let error { ErrorBanner(message: error) { await retry() }.padding(.top, 4) }
            if let issue = documentReadIssue {
                ErrorBanner(message: issue) { await retry() }.padding(.top, 4)
            }
            if let job {
                if selectedTab == "Photos" {
                    header(job, compact: true)
                    tabBar
                    JobMediaView(jobID: jobId)
                } else {
                    ScrollView {
                    // The tabs pin under the nav bar, so switching Overview, Invoice or Activity
                    // never means scrolling back to the top first.
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    header(job)
                    Section {
                        VStack(alignment: .leading, spacing: 16) {
                            switch selectedTab {
                            case "Estimates": estimatesContent(job)
                            case "Invoice": invoiceContent(job)
                            case "Activity": activityContent(job)
                            default: overviewContent(job)
                            }
                        }
                        .padding(.horizontal, Theme.gutter)
                        .padding(.top, selectedTab == "Invoice" ? 4 : 22)
                        .padding(.bottom, 28)
                    } header: {
                        tabBar.background(Theme.background)
                    }
                    }
                    }
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
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarActions }
        .toolbar(.hidden, for: .tabBar)
        .sensoryFeedback(.success, trigger: committed)
        // The customer may have changed a phone, an email or a contact in their own hands.
        .fullScreenCover(isPresented: $showCustomerMode, onDismiss: {
            if let job { Task { await loadContacts(job) } }
        }) {
            if let customerID = job?.customerId {
                CustomerSelfEditView(customerID: customerID) { showCustomerMode = false }
            }
        }
        .sheet(isPresented: $showDeposit) {
            JobDepositSheet(jobID: jobId) { invoice in
                selectedInvoiceID = invoice.id
                Task { await loadInvoices() }
            }
        }
        .navigationDestination(item: $reviewInvoiceID) { id in
            InvoiceDetailView(id: id, returnsWhenPaid: true)
                .onDisappear { Task { await loadInvoices() } }
        }
        .navigationDestination(item: $openEstimate) { opened in
            EstimateDetailView(id: opened.id, jobID: jobId, presentsOnOpen: opened.present)
                .onDisappear { if let job { Task { await loadJobEstimates(job); await loadInvoices() } } }
        }
        .navigationDestination(isPresented: $showWrapUp) { JobCloseoutView(jobID: jobId) }
        .navigationDestination(isPresented: $showAssign) { JobAssignmentView(jobID: jobId) }
        .navigationDestination(isPresented: $showFollowUps) {
            JobFollowUpsView(jobID: jobId).onDisappear { Task { await loadFollowUps() } }
        }
        .sheet(isPresented: $showNewEstimate, onDismiss: {
            // A saved estimate opens next, so the tech reviews it and hands it over (TF-06).
            if let id = createdEstimateID { createdEstimateID = nil; openEstimate = OpenedEstimate(id: id, present: false) }
        }) {
            if let job {
                NewEstimateView(customerID: job.customerId, jobID: job.id, title: job.title) { estimate in
                    createdEstimateID = estimate.id
                    Task { await loadJobEstimates(job) }
                }
            }
        }
        .task(id: session.generation) {
            invoiceRead = nil
            estimateRead = nil
            selectedInvoiceID = nil
            invoicePaymentModel = nil
            loadedInvoiceModelID = nil
            await load()
            // The next step needs the job's paper, so it loads with the job, not only on its tab.
            await loadInvoices()
            if let job { await loadJobEstimates(job) }
        }
        .refreshable {
            await load()
            if let job { await loadContacts(job) }
            await loadInvoices()
            if let job { await loadJobEstimates(job) }
        }
        // The Lock Screen card follows the status shown here, queued steps included.
        .task(id: liveActivityKey) {
            guard let job else { return }
            let pending = outbox.pendingStatus(for: job.id)
            await JobLiveActivity.sync(job: job, status: pending ?? job.status, waitingToSync: pending != nil,
                                       customer: store.customerName(job.customerId), address: locations.first?.address)
        }
        // Coming back from Assign, Wrap up or Follow-ups: the job may have moved on.
        .onAppear { if job != nil { Task { await load() } } }
        .onChange(of: selectedTab) { previous, tab in
            if tab == "Invoice" { Task { await loadInvoices() } }
            // Photos added on the Photos tab show in the Overview count straight away (JS-09).
            if previous == "Photos" { Task { await loadMediaCount() } }
        }
        .onChange(of: selectedInvoiceID) { _, selectedID in
            guard let selectedID, let invoice = invoices.first(where: { $0.id == selectedID }) else { return }
            Task { await loadInvoicePayments(for: invoice) }
        }
        .safeAreaInset(edge: .bottom) {
            if selectedTab == "Overview", let step = nextStep {
                // TF-01: the bar always carries the one next step of the call, money steps included.
                PaperActionBar(title: step.title(resuming: job?.status == "paused"), symbol: step.symbol,
                               busy: busy || creatingInvoice) {
                    run(step)
                }
            } else if selectedTab == "Estimates", session.can("estimate.create", feature: "estimates") {
                PaperActionBar(title: "Build an estimate", symbol: "doc.badge.plus") { showNewEstimate = true }
            } else if selectedTab == "Invoice", let invoice = selectedInvoice, invoice.status == "draft",
                      session.can("invoice.view", feature: "invoicing") {
                // A draft is reviewed (lines) and issued on its own screen, then collected here.
                PaperActionBar(title: "Review and send invoice", symbol: "paperplane") { reviewInvoiceID = invoice.id }
            } else if selectedTab == "Invoice",
                      session.can("invoice.payment.create", feature: "payments"),
                      let invoice = selectedInvoice,
                      let model = invoicePaymentModel,
                      loadedInvoiceModelID == invoice.id {
                PaperInvoiceCollectionFooter(model: model) { showCollectPayment = true }
            }
        }
        .sheet(isPresented: $showPause) {
            // MA-16: Cancel leading, the commit trailing where the thumb is; the form keeps what was typed.
            NavigationStack {
                Form {
                    Section {
                        TextField("Why are you pausing?", text: $reason, axis: .vertical)
                        TextField("What needs to happen next?", text: $nextAction, axis: .vertical)
                    } footer: {
                        if let error { Text(error).foregroundStyle(Theme.destructive) }
                        else { Text("The office sees both on the job.") }
                    }
                }
                .navigationTitle("Pause job")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showPause = false }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Pause") { Task { await pause() } }
                            .disabled(busy || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || nextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reason.utf16.count > 2000 || nextAction.utf16.count > 2000)
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .interactiveDismissDisabled(busy || !reason.isEmpty || !nextAction.isEmpty)
        }
        .sheet(isPresented: $showSchedule, onDismiss: { Task { await load() } }) {
            if let job {
                JobScheduleView(job: job) { updatedJob in
                    self.job = updatedJob
                }
            }
        }
        // A payment changes the balance the next step reads, wherever it was collected from.
        .sheet(isPresented: $showCollectPayment, onDismiss: { Task { await loadInvoices() } }) {
            if let invoice = selectedInvoice, let model = invoicePaymentModel {
                InvoicePaymentCollectionSheet(model: model, invoice: model.invoice ?? invoice)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    /// Native bar: system back on the left, share and the job's one menu on the right (HIG-005, JS-02).
    @ToolbarContentBuilder private var toolbarActions: some ToolbarContent {
        if let job {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: JobShareText.text(title: job.title, customer: store.customerName(job.customerId), scheduledFor: job.scheduledFor)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share job")
                let groups = menuGroups(job)
                if !groups.isEmpty {
                    Menu {
                        ForEach(groups.indices, id: \.self) { index in
                            Section { ForEach(groups[index], id: \.self) { menuItem($0, job: job) } }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Job actions")
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
            canBillWithoutEstimate: invoicesLoaded && !invoicesFailed && invoices.isEmpty && nextStep != .createInvoice
                && job.status == "in_progress" && session.can("invoice.create", feature: "invoicing"),
            canRequestDeposit: invoicesLoaded && !invoicesFailed && invoices.isEmpty && job.estimateId != nil
                && session.can("invoice.create", feature: "progress_billing"),
            // The bar shows only on Overview; on the other tabs Wrap up stays in the menu.
            barIsWrapUp: selectedTab == "Overview" && nextStep == .wrapUp,
            canShowToCustomer: session.can("customer.edit", feature: "core_crm")))
    }

    @ViewBuilder
    private func menuItem(_ action: JobMenuAction, job: JobRecord) -> some View {
        switch action {
        case .transition(let target):
            Button(transitionTitle(target), systemImage: transitionSymbol(target)) { runTransition(target) }.disabled(busy)
        case .schedule:
            Button(job.scheduledFor == nil ? "Schedule" : "Reschedule", systemImage: "calendar") { showSchedule = true }
        case .assign:
            Button(job.assignedToUserId == nil ? "Assign technician" : "Reassign technician", systemImage: "person.crop.circle.badge.plus") { showAssign = true }
        case .billWithoutEstimate:
            Button { run(.createInvoice) } label: {
                Label { Text("Create invoice"); Text("Bill without an estimate") } icon: { Image(systemName: "doc.plaintext") }
            }
            .disabled(creatingInvoice)
        case .deposit:
            Button { showDeposit = true } label: {
                Label { Text("Request a deposit"); Text("Bill part up front") } icon: { Image(systemName: "banknote") }
            }
        case .wrapUp:
            Button { showWrapUp = true } label: {
                Label { Text("Wrap up"); Text("Closeout checklist") } icon: { Image(systemName: "checkmark.seal") }
            }
        case .followUps:
            Button("Follow-ups", systemImage: "list.bullet") { showFollowUps = true }
        case .showToCustomer:
            Button("Show to customer", systemImage: "person.crop.rectangle") { showCustomerMode = true }
        case .copyID:
            Button("Copy job ID", systemImage: "doc.on.doc") { UIPasteboard.general.string = job.id }
        }
    }

    private func header(_ job: JobRecord, compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // The reference is mono so its digits line up; the customer's name reads as a name.
            PaperEyebrow(reference: "JOB-\(job.id.suffix(4).uppercased())", text: store.customerName(job.customerId))
            Text(job.title)
                .font(Theme.font(24, weight: .medium))
                .tracking(-0.36)
                .lineLimit(compact ? 2 : nil)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            // One wrapping row of chips instead of two fixed rows (chips are pills).
            FlowRow(spacing: 6, lineSpacing: 6) {
                    statusControl(job)
                    if let date = JobFiltering.date(job.scheduledFor) {
                        Button { if session.can("job.assign", feature: "jobs") { showSchedule = true } } label: {
                            Label(date.visitLabel(), systemImage: "clock")
                                .font(Theme.font(12, weight: .medium))
                                .foregroundStyle(Theme.muted)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5).frame(minHeight: Theme.chipHeight)
                                .background(Theme.fill, in: Capsule())
                                .padding(.vertical, 8).contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        // Without scheduling rights the chip is a label, not a button that does nothing.
                        .allowsHitTesting(session.can("job.assign", feature: "jobs"))
                        .accessibilityHint(session.can("job.assign", feature: "jobs") ? "Change the scheduled time" : "")
                    }
                    if let assignedName = assignedDisplayName(for: job) {
                        HStack(spacing: 6) {
                            Text(nameInitials(assignedName))
                                .font(Theme.font(12, weight: .medium))
                                .foregroundStyle(Theme.brandText)
                                .frame(width: 22, height: 22)
                                .dynamicTypeSize(...DynamicTypeSize.large)
                                .background(Theme.brandSurface, in: Circle())
                            Text(shortName(assignedName))
                                .font(Theme.font(12, weight: .medium))
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(.leading, 3).padding(.trailing, 10)
                        .padding(.vertical, 5).frame(minHeight: Theme.chipHeight)
                        .background(Theme.fill, in: Capsule())
                    }
                    MemberChip(customerID: job.customerId)
            }
            if let balance = invoiceBalanceCents {
                // MF-01/MF-03: what's owed on the job is a labelled figure, not a chip. It jumps to
                // the Invoice tab, where it can be collected.
                Button { withMotion(.snappy) { selectedTab = "Invoice" } } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Balance due").font(Theme.font(15)).foregroundStyle(Theme.muted)
                        Spacer(minLength: 12)
                        Text(money(balance, currency: "USD")).moneyStyle(.total).foregroundStyle(Theme.foreground)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .padding(.top, 8)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens the invoice")
            }
            if !compact {
                JobProgressTrack(status: outbox.pendingStatus(for: job.id) ?? job.status).padding(.top, 10)
                quickActions
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    /// Everything a tech reaches for on arrival, without leaving the job: call, text, drive.
    private var quickActions: some View {
        PaperQuickActions(phone: customerPhone,
                          directions: locations.first.flatMap { Directions.url(address: $0.address, coordinates: $0.coordinates) })
            .padding(.top, 8)
    }

    @ViewBuilder
    private func statusControl(_ job: JobRecord) -> some View {
        let tint: Color = switch job.status {
        case "completed": Theme.success
        case "en_route", "dispatched": Theme.brandText
        case "scheduled", "canceled": Theme.muted
        default: Theme.warning
        }
        let transitions = availableTransitions(job)
        if transitions.isEmpty {
            statusChip(job, tint: tint, showsMenu: false)
        } else {
            Menu {
                ForEach(transitions, id: \.self) { target in
                    Button(transitionTitle(target)) { runTransition(target) }
                }
            } label: {
                statusChip(job, tint: tint, showsMenu: true)
            }
            .buttonStyle(.plain)
        }
    }

    private func statusChip(_ job: JobRecord, tint: Color, showsMenu: Bool) -> some View {
        let queued = outbox.pendingStatus(for: job.id)
        return HStack(spacing: 5) {
            // MA-10: the hue rides on the glyph; the word and the pill stay neutral.
            Image(systemName: queued == nil ? statusIcon(job.status).0 : "clock.arrow.circlepath")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(queued == nil ? tint : Theme.warning)
            Text(queued.map { "\($0.statusLabel) · waiting to sync" } ?? job.status.statusLabel)
                .font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.foreground)
            if showsMenu { Image(systemName: "chevron.down").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5).frame(minHeight: Theme.chipHeight)
        .background(Theme.fill, in: Capsule())
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityLabel("Job status, \(job.status.statusLabel)")
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

    private func nameInitials(_ name: String) -> String {
        String(name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first))
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

    private var tabBar: some View {
        PaperTabs(options: tabs, selection: $selectedTab).padding(.bottom, 4)
    }

    /// JS-01: the body is for reading, in the order a tech needs it at the door. Every action that
    /// isn't the bar's next step is in the ••• menu at the top right.
    private func overviewContent(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            JobOfficeNote(notes: job.notes, pauseReason: job.pauseReason, pauseNextAction: job.pauseNextAction)
            // JS-05: only when the platform recorded the call that booked this job.
            if let bookingCall { JobBookingCallSection(call: bookingCall) }
            if session.can("customer.view", feature: "core_crm") {
                JobContactsSection(people: JobContacts.people(contacts: contacts, customer: customerRecord),
                                   preference: JobContacts.preference(customerRecord),
                                   loaded: contactsLoaded, failed: contactsFailed) { await loadContacts(job) }
            }
            if let place = locations.first {
                JobSiteSection(place: place, showsLabel: locations.count > 1)
            }
            // What's installed here and what they pay (JS-08); the tech records a unit they find in place.
            CustomerEquipmentSection(customerID: job.customerId, locations: locations, onlyLocationID: locations.first?.id)
            CustomerMembershipSection(customerID: job.customerId, editable: false)
            JobVisitCounts(latestNote: notes.last?.body, noteCount: notes.count + outbox.pendingNotes(for: job.id).count,
                           photoCount: mediaCount, openFollowUps: followUps.map { $0.filter { $0.status == "open" }.count },
                           openNotes: { activityFilter = "Notes"; withMotion(.snappy) { selectedTab = "Activity" } },
                           openPhotos: { withMotion(.snappy) { selectedTab = "Photos" } },
                           openFollowUpsScreen: { showFollowUps = true })
            JobPastVisitsSection(visits: visits, currentUserID: session.user?.id)
            detailsGroup(job)
        }
    }

    private func detailsGroup(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperGroupHeader(title: "Details")
            if let customer = store.customers.first(where: { $0.id == job.customerId }),
               session.can("customer.view", feature: "core_crm") {
                // The customer opens from the job: history, contacts and equipment in one tap.
                NavigationLink(value: customer) {
                    PaperDetailRow(label: "Customer") {
                        HStack(spacing: 4) {
                            Text(customer.name).foregroundStyle(Theme.foreground)
                            PaperDisclosure()
                        }
                    }
                }
                .buttonStyle(RowPressStyle())
                .accessibilityHint("Opens the customer")
            } else {
                PaperDetailRow("Customer", value: store.customerName(job.customerId))
            }
            if let date = JobFiltering.date(job.scheduledFor) {
                PaperDetailRow("Scheduled", value: date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
            } else {
                PaperDetailRow("Scheduled", value: "Not scheduled")
            }
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
            PaperDetailRow(label: "Job ID") { Text("JOB-\(job.id.suffix(4).uppercased())").font(Theme.monoFont(15, weight: .medium)) }
                .contextMenu { Button("Copy job ID", systemImage: "doc.on.doc") { UIPasteboard.general.string = job.id } }
        }
    }

    /// Paper 23: every estimate on the job with totals, approved vs awaiting, and one commit to build another.
    private func estimatesContent(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !session.can("estimate.view", feature: "estimates") {
                PaperEmptyState(symbol: "doc.text", title: "Estimates unavailable", message: "Your role cannot view estimates.")
            } else {
                let approved = jobEstimates.filter { $0.status == "approved" }.compactMap { paperLinesTotal($0.lines) }.reduce(0, +)
                let waiting = jobEstimates.filter { $0.status == "sent" }.compactMap { paperLinesTotal($0.lines) }.reduce(0, +)
                if !jobEstimates.isEmpty {
                    HStack(spacing: 0) {
                        summary("Awaiting approval", money(waiting, currency: "USD"), quiet: waiting == 0)
                        Rectangle().fill(Theme.border).frame(width: 1, height: 40).padding(.horizontal, 16)
                        summary("Approved", money(approved, currency: "USD"), quiet: approved == 0)
                    }
                    .padding(.bottom, 6)
                }
                PaperGroupHeader(title: "Estimates", count: jobEstimates.count)
                if !estimatesLoaded {
                    SkeletonRows(count: 2, leading: false, inset: 0)
                } else if jobEstimates.isEmpty && !estimatesFailed {
                    PaperEmptyState(symbol: "doc.text", title: "No estimates yet",
                                    message: "Build one from the price book. It's added to this job automatically.")
                }
                ForEach(jobEstimates) { estimate in
                    NavigationLink { EstimateDetailView(id: estimate.id, jobID: jobId) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(estimate.title).font(Theme.font(15, weight: .medium))
                                    .foregroundStyle(Theme.foreground).multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                if let total = paperLinesTotal(estimate.lines) {
                                    Text(money(total, currency: estimate.lines.first?.unitPrice.currency ?? "USD"))
                                        .moneyStyle(.row).foregroundStyle(Theme.foreground)
                                }
                            }
                            HStack(spacing: 8) {
                                PaperStatusChip(status: estimate.status)
                                Text("EST-\(estimate.id.suffix(4).uppercased())").font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
                                Spacer()
                                PaperDisclosure()
                            }
                        }
                        .padding(16)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.border))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .disabled(estimateRead?.freshIDs.contains(estimate.id) != true)
                }
            }
        }
        .task(id: job.id) { await loadJobEstimates(job) }
    }

    /// A zero total is muted, so the figure that matters ("$970.00 awaiting") reads first.
    private func summary(_ label: String, _ value: String, quiet: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.font(13)).foregroundStyle(Theme.muted)
            Text(value).moneyStyle(.total).foregroundStyle(quiet ? Theme.subtle : Theme.foreground)
        }
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
            estimateRead = nil
            return
        }
        let generation = session.generation
        let read = await JobDocumentsLoader.estimates(scope: scope, api: api, retaining: estimateRead) {
            session.generation == generation && session.activeOrganization?.id == scope.organizationID &&
                self.job?.id == scope.jobID && self.job?.customerId == scope.customerID
        }
        guard session.generation == generation, let read else { return }
        estimateRead = read
    }

    private func invoiceContent(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            if !session.can("invoice.view", feature: "invoicing") {
                emptyCard("Invoice access is unavailable.")
            } else if !invoicesLoaded {
                SkeletonRows(count: 3, leading: false, inset: 0)
            } else if invoices.isEmpty && !invoicesFailed {
                PaperEmptyState(symbol: "doc.plaintext", title: "No invoice yet",
                                message: "Start the invoice from this job. Lines come from its approved estimate; you can edit them before sending.",
                                actionTitle: session.can("invoice.create", feature: "invoicing") ? (creatingInvoice ? "Creating…" : "Create invoice") : nil,
                                action: { Task { await createInvoice() } })
                if job.estimateId != nil, session.can("invoice.create", feature: "progress_billing") {
                    Button { showDeposit = true } label: {
                        PaperMenuRow("Request a deposit", symbol: "banknote", subtitle: "Bill part up front from the approved estimate")
                    }
                    .buttonStyle(RowPressStyle())
                }
            } else {
                if invoices.count > 1 {
                    Menu {
                        ForEach(invoices) { invoice in
                            Button("INV-\(invoice.id.suffix(4).uppercased()) · \(invoice.status.statusLabel)") {
                                selectedInvoiceID = invoice.id
                            }
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Text("INV-\((selectedInvoice?.id ?? invoices[0].id).suffix(4).uppercased())")
                                .font(Theme.monoFont(12, weight: .medium))
                            Image(systemName: "chevron.down").font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5).frame(minHeight: Theme.chipHeight)
                        .background(Theme.fill, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Choose invoice")
                }
                if let invoice = selectedInvoice {
                    if let model = invoicePaymentModel, loadedInvoiceModelID == invoice.id {
                        PaperJobInvoiceContent(
                            invoice: invoice,
                            paymentModel: model,
                            onCollectPayment: { showCollectPayment = true },
                            onInvoiceUpdated: updateInvoice
                        )
                    } else {
                        SkeletonRows(count: 4, leading: false, inset: 0)
                    }
                }
            }
        }
    }

    private var selectedInvoice: InvoiceRecord? {
        invoiceRead?.preferredInvoice(id: selectedInvoiceID)
    }

    private func updateInvoice(_ updated: InvoiceRecord) {
        invoiceRead = invoiceRead?.replacing(updated)
    }

    /// Paper 21B: filter pills, a quiet timeline of notes and status changes, composer last.
    private func activityContent(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                ForEach(["All", "Notes", "Status"], id: \.self) { filter in
                    Button { activityFilter = filter } label: {
                        Text(filter)
                            .font(Theme.font(12, weight: .medium))
                            .foregroundStyle(activityFilter == filter ? Theme.background : Theme.muted)
                            .padding(.horizontal, 12).frame(height: 28)
                            .background(activityFilter == filter ? Theme.foreground : Theme.fill, in: Capsule())
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityAddTraits(activityFilter == filter ? .isSelected : [])
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(timeline(job)) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            Image(systemName: entry.symbol).font(.system(size: 12, weight: .medium))
                                .foregroundStyle(entry.isNote ? Theme.foreground : Theme.muted)
                                .frame(width: 26, height: 26)
                                .background(Theme.fill, in: Circle())
                            Rectangle().fill(Theme.border).frame(width: 1).frame(maxHeight: .infinity)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(entry.title).font(Theme.font(15, weight: .medium))
                                Spacer(minLength: 8)
                                Text(entry.date.formatted(.dateTime.hour().minute())).font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
                            }
                            if let body = entry.body {
                                Text(body).font(Theme.font(15)).foregroundStyle(Theme.foreground)
                                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).stroke(Theme.border))
                                    .textSelection(.enabled)
                            }
                            Text(entry.date.formatted(.dateTime.month(.abbreviated).day())).font(Theme.font(12)).foregroundStyle(Theme.muted)
                        }
                        .padding(.bottom, 16)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if timeline(job).isEmpty {
                PaperEmptyState(symbol: "clock", title: "No activity yet", message: "Notes and status changes on this job show up here.")
            }
            if session.can("job.note", feature: "jobs") {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Add a note or update…", text: $note, axis: .vertical)
                        .font(Theme.font(16))
                        .lineLimit(1...6)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.border))
                    Button { Task { await saveNote() } } label: {
                        Group { if busy { ProgressView().tint(Theme.onInk) } else { Image(systemName: "arrow.up").font(.system(size: 17, weight: .medium)) } }
                            .foregroundStyle(Theme.onInk).frame(width: 44, height: 44)
                            .background(Theme.ink.opacity(canSaveNote ? 1 : 0.35), in: Circle())
                    }
                    .buttonStyle(PressStyle())
                    .disabled(!canSaveNote || busy)
                    .accessibilityLabel("Save note")
                }
            }
        }
    }

    private var canSaveNote: Bool {
        !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && note.utf16.count <= 10_000
    }

    private struct TimelineEntry: Identifiable {
        let id: String
        let title: String
        let body: String?
        let date: Date
        let symbol: String
        var isNote: Bool { body != nil }
    }

    private func timeline(_ job: JobRecord) -> [TimelineEntry] {
        var entries: [TimelineEntry] = []
        if activityFilter != "Status" {
            entries += outbox.pendingNotes(for: job.id).compactMap { entry in
                guard case .note(let payload) = entry.action else { return nil }
                let waiting = entry.state == .pending ? "Note · waiting to sync" : "Note · couldn't sync"
                return TimelineEntry(id: "queued-\(entry.id)", title: waiting, body: payload.body, date: entry.createdAt, symbol: "clock.arrow.circlepath")
            }
            entries += notes.compactMap { record in
                JobFiltering.date(record.createdAt).map { TimelineEntry(id: "note-\(record.id)", title: "Note", body: record.body, date: $0, symbol: "text.bubble") }
            }
        }
        if activityFilter != "Notes" {
            entries += statusEvents(job).map { TimelineEntry(id: "status-\($0.0)", title: $0.0, body: nil, date: $0.1, symbol: "circle.fill") }
        }
        return entries.sorted { $0.date > $1.date }
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
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
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

    private func run(_ step: TechJobStep) {
        switch step {
        case .transition(let target): runTransition(target)
        case .buildEstimate: showNewEstimate = true
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
                else { withMotion(.snappy) { selectedTab = "Invoice" } }
            }
        case .wrapUp: showWrapUp = true
        }
    }

    private func availableTransitions(_ job: JobRecord) -> [String] {
        let allowed: [String]
        if let queued = outbox.pendingStatus(for: job.id) {
            allowed = outbox.offlineSteps(from: queued).filter { ["en_route", "arrived", "in_progress"].contains($0) }
        } else {
            allowed = job.allowedTransitions ?? []
        }
        return allowed.filter {
            ["scheduled", "dispatched", "en_route", "arrived", "in_progress", "paused"].contains($0)
                && session.can(["scheduled", "dispatched"].contains($0) ? "job.assign" : "job.edit", feature: "jobs")
        }
    }

    private func transitionTitle(_ target: String) -> String {
        switch target {
        case "paused": "Pause job…"
        case "en_route": "On my way"
        case "arrived": "Mark arrived"
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
            invoiceRead = nil
            return
        }
        let generation = session.generation
        let read = await JobDocumentsLoader.invoices(scope: scope, api: api, knownIDs: JobInvoiceMemory.ids(jobId), retaining: invoiceRead) {
            session.generation == generation && session.activeOrganization?.id == scope.organizationID &&
                self.job?.id == scope.jobID && self.job?.customerId == scope.customerID
        }
        guard session.generation == generation, let read else { return }
        invoiceRead = read
        if read.isComplete {
            JobInvoiceMemory.replace(read.records.map(\.id), jobID: jobId)
        } else {
            read.records.filter { read.freshIDs.contains($0.id) }.forEach { JobInvoiceMemory.remember($0.id, jobID: jobId) }
        }
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

    private func loadInvoicePayments(for invoice: InvoiceRecord) async {
        guard session.can("invoice.view", feature: "invoicing") else { return }
        if loadedInvoiceModelID != invoice.id {
            loadedInvoiceModelID = invoice.id
            invoicePaymentModel = InvoicePaymentCollectionModel(api: api, invoiceID: invoice.id)
        }
        await invoicePaymentModel?.load()
    }
    private func load() async {
        let generation = session.generation
        do {
            let loadedJob = try await api.fieldJob(jobId)
            guard session.generation == generation else { return }
            guard loadedJob.id == jobId, loadedJob.organizationId == session.activeOrganization?.id else {
                throw Problem(title: "Job could not be verified", status: nil, detail: nil)
            }
            job = loadedJob
            // Record before the follow-up requests below, while the identity is known to match.
            RecentItems.shared.record(.job, id: loadedJob.id, title: loadedJob.title,
                                      subtitle: "JOB-\(loadedJob.id.suffix(4).uppercased()) · \(store.customerName(loadedJob.customerId))")
            if locations.isEmpty, session.can("customer.view", feature: "core_crm"),
               let places = try? await api.fieldLocations(loadedJob.customerId), session.generation == generation {
                locations = places
            }
            if !contactsLoaded { await loadContacts(loadedJob) }
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

    /// JS-06: every contact and the account; the header's Call and Text reach the primary one.
    private func loadContacts(_ job: JobRecord) async {
        guard session.can("customer.view", feature: "core_crm") else { return }
        let generation = session.generation
        do {
            let people = try await api.fieldContacts(job.customerId)
            let account = try? await api.fieldCustomer(job.customerId)
            guard session.generation == generation else { return }
            contacts = people
            customerRecord = account
            contactsFailed = false
            customerPhone = people.first(where: \.primary)?.phone ?? people.first(where: { $0.phone != nil })?.phone ?? account?.phone
        } catch is CancellationError { return } catch {
            guard session.generation == generation else { return }
            contactsFailed = true
            if customerPhone == nil { customerPhone = (try? await api.fieldCustomer(job.customerId))?.phone }
        }
        contactsLoaded = true
    }

    /// JS-09/JS-10: follow-ups, photo count and past visits. Each is optional: a section whose
    /// read fails or that an older server doesn't offer simply stays out.
    private func loadBrief() async {
        let generation = session.generation
        await loadFollowUps()
        let loadedMedia = try? await api.fieldMedia(jobId)
        let loadedVisits = try? await api.fieldVisitHistory(jobId)
        let loadedCall = try? await api.fieldBookingCall(jobId)
        guard session.generation == generation else { return }
        if let loadedMedia { mediaCount = loadedMedia.count }
        if let loadedVisits { visits = loadedVisits }
        if let loadedCall { bookingCall = loadedCall }
    }

    private func loadMediaCount() async {
        let generation = session.generation
        guard let loaded = try? await api.fieldMedia(jobId), session.generation == generation else { return }
        mediaCount = loaded.count
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

struct JobProgressTrack: View {
    let status: String
    private static let steps = ["Booked", "On the way", "On site", "Working", "Done"]

    private var current: Int? {
        switch status {
        case "scheduled", "dispatched": 0
        case "en_route": 1
        case "arrived": 2
        case "in_progress", "paused": 3
        case "completed": 4
        default: nil
        }
    }

    var body: some View {
        if let current {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(Self.steps.indices, id: \.self) { index in
                        Capsule()
                            .fill(index <= current ? tint : Theme.fill)
                            .frame(height: 5)
                    }
                }
                // The status chip above names the step and the bottom bar names the next one,
                // so the track stays a quiet bar without a second line of words.
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(current + 1) of 5, \(Self.steps[current])")
        }
    }

    /// One accent for progress; status is the word, not a rainbow (design.thorbis.com Color).
    private var tint: Color { status == "completed" ? Theme.success : Theme.brandText }
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
