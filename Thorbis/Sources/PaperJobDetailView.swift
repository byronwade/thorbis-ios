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
    @State private var invoices: [InvoiceRecord] = []
    @State private var invoicesLoaded = false
    @State private var selectedInvoiceID: String?
    @State private var invoicePaymentModel: InvoicePaymentCollectionModel?
    @State private var loadedInvoiceModelID: String?
    @State private var showCollectPayment = false
    @State private var activityFilter = "All"
    @State private var showSchedule = false
    @State private var jobEstimates: [EstimateRecord] = []
    @State private var estimatesLoaded = false
    @State private var showNewEstimate = false
    @State private var committed = 0
    @State private var creatingInvoice = false
    @State private var reviewInvoiceID: String?
    @State private var showDeposit = false
    /// The customer's service locations; the first (or only) one is where the job is.
    @State private var locations: [ServiceLocationRecord] = []
    /// The primary contact's phone (else the customer's), for one-tap Call and Text.
    @State private var customerPhone: String?
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
            if let job {
                if selectedTab == "Photos" {
                    header(job, compact: true)
                    tabBar
                    JobMediaView(jobID: jobId)
                } else {
                    ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                    header(job)
                    tabBar
                    VStack(alignment: .leading, spacing: 16) {
                        switch selectedTab {
                        case "Estimates": estimatesContent(job)
                        case "Invoice": invoiceContent(job)
                        case "Activity": activityContent(job)
                        default: overviewContent(job)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, selectedTab == "Invoice" ? 4 : 22)
                    .padding(.bottom, 28)
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
        .fullScreenCover(isPresented: $showCustomerMode) {
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
            InvoiceDetailView(id: id)
                .onDisappear { Task { await loadInvoices() } }
        }
        .task(id: session.generation) {
            invoicePaymentModel = nil
            loadedInvoiceModelID = nil
            await load()
            if selectedTab == "Invoice" { await loadInvoices() }
        }
        .refreshable {
            if selectedTab == "Invoice" { await loadInvoices() }
            else { await load() }
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
        .onChange(of: selectedTab) { _, tab in
            if tab == "Invoice" { Task { await loadInvoices() } }
        }
        .onChange(of: selectedInvoiceID) { _, selectedID in
            guard let selectedID, let invoice = invoices.first(where: { $0.id == selectedID }) else { return }
            Task { await loadInvoicePayments(for: invoice) }
        }
        .safeAreaInset(edge: .bottom) {
            if selectedTab == "Overview", let job, let target = availableTransitions(job).first {
                // Directions now sits with Call and Text in the header; the bar carries one commit.
                PaperActionBar(title: transitionTitle(target), symbol: transitionSymbol(target), busy: busy) {
                    runTransition(target)
                }
            } else if selectedTab == "Estimates", let job, session.can("estimate.create", feature: "estimates") {
                PaperActionBar(title: "Build an estimate", symbol: "doc.badge.plus") { showNewEstimate = true }
                    .sheet(isPresented: $showNewEstimate) {
                        NewEstimateView(customerID: job.customerId, jobID: job.id, title: job.title) { _ in
                            Task { await loadJobEstimates(job) }
                        }
                    }
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
        .sheet(isPresented: $showCollectPayment) {
            if let invoice = selectedInvoice, let model = invoicePaymentModel {
                InvoicePaymentCollectionSheet(model: model, invoice: model.invoice ?? invoice)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    /// Native bar: system back on the left, share and more on the right (HIG-005).
    @ToolbarContentBuilder private var toolbarActions: some ToolbarContent {
        if let job {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: JobShareText.text(title: job.title, customer: store.customerName(job.customerId), scheduledFor: job.scheduledFor)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share job")
                Menu {
                    if session.can("customer.edit", feature: "core_crm") {
                        Button("Show to customer", systemImage: "person.crop.rectangle") { showCustomerMode = true }
                    }
                    Button("Copy job ID", systemImage: "doc.on.doc") { UIPasteboard.general.string = job.id }
                    NavigationLink { JobCloseoutView(jobID: jobId) } label: { Label("Closeout", systemImage: "checkmark.seal") }
                    NavigationLink { JobFollowUpsView(jobID: jobId) } label: { Label("Follow-ups", systemImage: "list.bullet") }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More job actions")
            }
        }
    }

    private func header(_ job: JobRecord, compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("JOB-\(job.id.suffix(4).uppercased()) · \(store.customerName(job.customerId))")
                .font(Theme.monoFont(12, weight: .medium))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            Text(job.title)
                .font(Theme.font(26, weight: .semibold))
                .tracking(-0.39)
                .lineLimit(compact ? 2 : nil)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            // One wrapping row of chips instead of two fixed rows (chips are pills).
            FlowRow(spacing: 6, lineSpacing: 6) {
                    statusControl(job)
                    if let date = JobFiltering.date(job.scheduledFor) {
                        Button { if session.can("job.assign", feature: "jobs") { showSchedule = true } } label: {
                            Label(scheduleLabel(date), systemImage: "clock")
                                .font(Theme.font(12, weight: .medium))
                                .foregroundStyle(Theme.muted)
                                .padding(.horizontal, 10)
                                .frame(height: Theme.chipHeight)
                                .background(Theme.fill, in: Capsule())
                                .padding(.vertical, 8).contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
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
                        .frame(height: Theme.chipHeight)
                        .background(Theme.fill, in: Capsule())
                    }
                    MemberChip(customerID: job.customerId)
                    if let balance = invoiceBalanceCents {
                        Text("\(money(balance, currency: "USD")) due")
                            .font(Theme.monoFont(12, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 10)
                            .frame(height: Theme.chipHeight)
                            .background(Theme.fill, in: Capsule())
                    }
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
        let surface: Color = switch job.status {
        case "completed": Theme.successSurface
        case "en_route", "dispatched": Theme.brandSurface
        case "scheduled", "canceled": Theme.fill
        default: Theme.warningSurface
        }
        let transitions = availableTransitions(job)
        if transitions.isEmpty {
            statusChip(job, tint: tint, surface: surface, showsMenu: false)
        } else {
            Menu {
                ForEach(transitions, id: \.self) { target in
                    Button(transitionTitle(target)) { runTransition(target) }
                }
            } label: {
                statusChip(job, tint: tint, surface: surface, showsMenu: true)
            }
            .buttonStyle(.plain)
        }
    }

    private func statusChip(_ job: JobRecord, tint: Color, surface: Color, showsMenu: Bool) -> some View {
        let queued = outbox.pendingStatus(for: job.id)
        return HStack(spacing: 5) {
            Image(systemName: queued == nil ? statusIcon(job.status).0 : "clock.arrow.circlepath")
                .font(.system(size: 12, weight: .medium))
            Text(queued.map { "\($0.statusLabel) · waiting to sync" } ?? job.status.statusLabel)
                .font(Theme.font(12, weight: .medium))
            if showsMenu { Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)) }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .frame(height: Theme.chipHeight)
        .background(surface, in: Capsule())
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityLabel("Job status, \(job.status.statusLabel)")
    }

    private func scheduleLabel(_ date: Date) -> String {
        let time = date.formatted(.dateTime.hour().minute())
        if Calendar.current.isDateInToday(date) { return "Today · \(time)" }
        return "\(date.formatted(.dateTime.weekday())) · \(time)"
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

    /// Paper 21: description as plain text, quiet value rows, then the job's other actions.
    private func overviewContent(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let detail = job.notes, !detail.isEmpty {
                Text(detail)
                    .font(Theme.font(15)).lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            VStack(alignment: .leading, spacing: 0) {
                PaperGroupHeader(title: "Details") {
                    if session.can("job.assign", feature: "jobs") {
                        Button("Edit time") { showSchedule = true }
                            .font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.brandText)
                            .frame(minHeight: 44)
                    }
                }
                PaperDetailRow("Customer", value: store.customerName(job.customerId))
                if let place = locations.first {
                    Button {
                        if let url = Directions.url(address: place.address, coordinates: place.coordinates) { openURL(url) }
                    } label: {
                        PaperDetailRow(label: "Address") {
                            HStack(spacing: 4) {
                                Text(place.address).foregroundStyle(Theme.brandText)
                                Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.brandText)
                            }
                        }
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityHint("Opens driving directions in Maps")
                    let access = [place.gateCode.map { "Gate \($0)" }, place.alarmCode.map { "Alarm \($0)" },
                                  place.dogOnSite.map { "Dog: \($0)" }, place.parking.map { "Parking: \($0)" }].compactMap { $0 }
                    if !access.isEmpty { PaperDetailRow("Access", value: access.joined(separator: " · ")) }
                }
                if let date = JobFiltering.date(job.scheduledFor) {
                    PaperDetailRow("Scheduled", value: date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                } else {
                    PaperDetailRow("Scheduled", value: "Not scheduled")
                }
                if let reason = job.pauseReason { PaperDetailRow("Pause reason", value: reason) }
                if let next = job.pauseNextAction { PaperDetailRow("Next action", value: next) }
            }
            // What's installed at this address, so the tech arrives knowing model and serial.
            CustomerEquipmentSection(customerID: job.customerId, locations: locations, onlyLocationID: locations.first?.id)
            VStack(alignment: .leading, spacing: 0) {
                PaperGroupHeader(title: "On this job")
                ForEach(availableTransitions(job).dropFirst(), id: \.self) { target in
                    Button { runTransition(target) } label: {
                        PaperMenuRow(transitionTitle(target), symbol: transitionSymbol(target))
                    }
                    .buttonStyle(RowPressStyle()).disabled(busy)
                }
                if session.can("job.assign", feature: "jobs") {
                    Button { showSchedule = true } label: { PaperMenuRow("Schedule", symbol: "calendar", subtitle: "Pick a day and arrival window") }
                        .buttonStyle(RowPressStyle())
                    NavigationLink { JobAssignmentView(jobID: jobId) } label: { PaperMenuRow("Assign technician", symbol: "person.crop.circle.badge.plus") }
                        .buttonStyle(RowPressStyle())
                }
                NavigationLink { JobCloseoutView(jobID: jobId) } label: { PaperMenuRow("Wrap up", symbol: "checkmark.seal", subtitle: "Closeout checklist") }
                    .buttonStyle(RowPressStyle())
                NavigationLink { JobFollowUpsView(jobID: jobId) } label: { PaperMenuRow("Follow-ups", symbol: "list.bullet") }
                    .buttonStyle(RowPressStyle())
            }
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
                        summary("Awaiting approval", money(waiting, currency: "USD"))
                        Rectangle().fill(Theme.border).frame(width: 1, height: 40).padding(.horizontal, 16)
                        summary("Approved", money(approved, currency: "USD"))
                    }
                    .padding(.bottom, 6)
                }
                PaperGroupHeader(title: "Estimates", count: jobEstimates.count)
                if !estimatesLoaded {
                    SkeletonRows(count: 2, leading: false, inset: 0)
                } else if jobEstimates.isEmpty {
                    PaperEmptyState(symbol: "doc.text", title: "No estimates yet",
                                    message: "Build one from the price book. It's added to this job automatically.")
                }
                ForEach(jobEstimates) { estimate in
                    NavigationLink { EstimateDetailView(id: estimate.id, jobID: jobId) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(estimate.title).font(Theme.font(16, weight: .semibold))
                                    .foregroundStyle(Theme.foreground).multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                if let total = paperLinesTotal(estimate.lines) {
                                    Text(money(total, currency: estimate.lines.first?.unitPrice.currency ?? "USD"))
                                        .font(Theme.monoFont(14, weight: .semibold)).foregroundStyle(Theme.foreground)
                                }
                            }
                            HStack(spacing: 8) {
                                PaperStatusChip(status: estimate.status)
                                Text("EST-\(estimate.id.suffix(4).uppercased())").font(Theme.monoFont(11)).foregroundStyle(Theme.muted)
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                            }
                        }
                        .padding(16)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
        .task(id: job.id) { await loadJobEstimates(job) }
    }

    private func summary(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.font(13)).foregroundStyle(Theme.muted)
            Text(value).font(Theme.monoFont(19, weight: .semibold))
        }
    }

    /// Linked estimates first; the job's origin estimate is included even without a link record.
    private func loadJobEstimates(_ job: JobRecord) async {
        guard session.can("estimate.view", feature: "estimates") else { return }
        let generation = session.generation
        do {
            var ids = try await api.fieldJobEstimateLinks(job.id).map(\.estimateId)
            if let origin = job.estimateId, !ids.contains(origin) { ids.insert(origin, at: 0) }
            var loaded: [EstimateRecord] = []
            for id in ids {
                loaded.append(try await api.fieldEstimate(id))
            }
            guard session.generation == generation else { return }
            jobEstimates = loaded
            estimatesLoaded = true
        } catch is CancellationError {} catch {
            guard session.generation == generation else { return }
            if let origin = job.estimateId, let single = try? await api.fieldEstimate(origin) { jobEstimates = [single] }
            estimatesLoaded = true
            self.error = error.localizedDescription
        }
    }

    private func invoiceContent(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            if !session.can("invoice.view", feature: "invoicing") {
                emptyCard("Invoice access is unavailable.")
            } else if !invoicesLoaded {
                ProgressView("Loading invoices…").frame(maxWidth: .infinity).padding(30)
            } else if invoices.isEmpty {
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
                        .padding(.horizontal, 10)
                        .frame(minHeight: 36)
                        .background(Theme.fill, in: Capsule())
                    }
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
                        ProgressView("Loading invoice…")
                            .frame(maxWidth: .infinity, minHeight: 100)
                    }
                }
            }
        }
    }

    private var selectedInvoice: InvoiceRecord? {
        if let selectedInvoiceID, let selected = invoices.first(where: { $0.id == selectedInvoiceID }) {
            return selected
        }
        return invoices.first
    }

    private func updateInvoice(_ updated: InvoiceRecord) {
        guard let index = invoices.firstIndex(where: { $0.id == updated.id }) else { return }
        invoices[index] = updated
    }

    /// Paper 21B: filter pills, a quiet timeline of notes and status changes, composer last.
    private func activityContent(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                ForEach(["All", "Notes", "Status"], id: \.self) { filter in
                    Button { activityFilter = filter } label: {
                        Text(filter)
                            .font(Theme.font(12, weight: activityFilter == filter ? .semibold : .medium))
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
                                .foregroundStyle(entry.isNote ? Theme.brandText : Theme.muted)
                                .frame(width: 26, height: 26)
                                .background(entry.isNote ? Theme.brandSurface : Theme.fill, in: Circle())
                            Rectangle().fill(Theme.border).frame(width: 1).frame(maxHeight: .infinity)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(entry.title).font(Theme.font(14, weight: .semibold))
                                Spacer(minLength: 8)
                                Text(entry.date.formatted(.dateTime.hour().minute())).font(Theme.monoFont(11)).foregroundStyle(Theme.muted)
                            }
                            if let body = entry.body {
                                Text(body).font(Theme.font(14)).foregroundStyle(Theme.foreground)
                                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                                    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.border))
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
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.border))
                    Button { Task { await saveNote() } } label: {
                        Group { if busy { ProgressView().tint(Theme.onInk) } else { Image(systemName: "arrow.up").font(.system(size: 16, weight: .medium)) } }
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
        Text(title).font(Theme.font(16, weight: .semibold))
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
            Text(title).font(Theme.font(14, weight: .medium))
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
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
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
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
        guard session.can("invoice.view", feature: "invoicing") else { return }
        let generation = session.generation
        do {
            let all = try await api.fieldInvoices()
            guard session.generation == generation else { return }
            var mine = all.filter { $0.jobId == jobId }
            // Technicians' invoice list is empty by design; re-read the ones this phone has seen
            // for the job by id, which the server allows through the assigned job.
            if mine.isEmpty {
                for id in JobInvoiceMemory.ids(jobId) {
                    if let invoice = try? await api.fieldInvoice(id) { mine.append(invoice) }
                }
            }
            invoices = mine.sorted { $0.createdAt > $1.createdAt }
            mine.forEach { JobInvoiceMemory.remember($0.id, jobID: jobId) }
            invoicesLoaded = true
            if let selectedInvoice {
                selectedInvoiceID = selectedInvoice.id
                await loadInvoicePayments(for: selectedInvoice)
            }
        } catch is CancellationError {} catch {
            guard session.generation == generation else { return }
            self.error = error.localizedDescription
            invoicesLoaded = true
        }
    }

    /// The job's canonical completion draft (POST /v1/jobs/{id}/completion-invoice); idempotent per job.
    private func createInvoice() async {
        guard !creatingInvoice, session.can("invoice.create", feature: "invoicing") else { return }
        creatingInvoice = true
        defer { creatingInvoice = false }
        do {
            let invoice = try await api.ensureFieldCompletionInvoice(jobId)
            JobInvoiceMemory.remember(invoice.id, jobID: jobId)
            selectedInvoiceID = invoice.id
            await loadInvoices()
            committed += 1
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
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
            job = loadedJob
            // Record before the follow-up requests below, while the identity is known to match.
            RecentItems.shared.record(.job, id: loadedJob.id, title: loadedJob.title,
                                      subtitle: "JOB-\(loadedJob.id.suffix(4).uppercased()) · \(store.customerName(loadedJob.customerId))")
            if locations.isEmpty, session.can("customer.view", feature: "core_crm"),
               let places = try? await api.fieldLocations(loadedJob.customerId), session.generation == generation {
                locations = places
            }
            if customerPhone == nil, session.can("customer.view", feature: "core_crm") {
                let contacts = (try? await api.fieldContacts(loadedJob.customerId)) ?? []
                let primary = contacts.first(where: \.primary)?.phone ?? contacts.first?.phone
                if let primary { customerPhone = primary }
                else { customerPhone = (try? await api.fieldCustomer(loadedJob.customerId))?.phone }
            }
            outbox.learn(loadedJob)
            JobDetailCache.save(loadedJob)
            let loadedNotes = try await api.fieldNotes(jobId)
            guard session.generation == generation else { return }
            notes = loadedNotes
            JobDetailCache.save(notes: loadedNotes, jobID: jobId)
            error = nil
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

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}
