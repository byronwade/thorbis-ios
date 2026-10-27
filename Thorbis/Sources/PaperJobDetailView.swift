import SwiftUI
import UIKit

struct JobDetailView: View {
    let jobId: String
    let showsBack: Bool

    init(jobId: String, showsBack: Bool = true) {
        self.jobId = jobId
        self.showsBack = showsBack
        #if DEBUG
        let previewTabs = ["job-invoice": "Invoice", "job-estimates": "Estimates", "job-activity": "Activity", "job-media": "Media"]
        _selectedTab = State(initialValue: PaperPreview.enabled ? previewTabs[PaperPreview.screen] ?? "Overview" : "Overview")
        #endif
    }
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @EnvironmentObject var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var job: JobRecord?
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

    private let tabs = ["Overview", "Estimates", "Invoice", "Media", "Activity"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error { ErrorBanner(message: error).padding(.horizontal, 20).padding(.top, 12) }
            if let job {
                if selectedTab == "Media" {
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
                ProgressView("Loading job…")
                    .frame(maxWidth: .infinity, minHeight: 240)
            }
        }
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarActions }
        .toolbar(.hidden, for: .tabBar)
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
            } else if selectedTab == "Invoice",
                      session.can("invoice.payment.create", feature: "payments"),
                      let invoice = selectedInvoice,
                      let model = invoicePaymentModel,
                      loadedInvoiceModelID == invoice.id {
                PaperInvoiceCollectionFooter(model: model) { showCollectPayment = true }
            }
        }
        .sheet(isPresented: $showPause) {
            NavigationStack {
                Form {
                    TextField("Why are you pausing?", text: $reason, axis: .vertical)
                    TextField("What needs to happen next?", text: $nextAction, axis: .vertical)
                    if let error { Text(error).foregroundStyle(Theme.destructive) }
                    Button("Pause job") { Task { await pause() } }
                        .disabled(busy || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || nextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reason.utf16.count > 2000 || nextAction.utf16.count > 2000)
                }
                .navigationTitle("Pause job")
                .toolbar { Button("Cancel") { showPause = false }.disabled(busy) }
            }
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
                ShareLink(item: "\(job.title) · \(job.id)") {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share job")
                Menu {
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
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    statusControl(job)
                    if let date = JobFiltering.date(job.scheduledFor) {
                        Button { if session.can("job.assign", feature: "jobs") { showSchedule = true } } label: {
                            Label(scheduleLabel(date), systemImage: "clock")
                                .font(Theme.font(12, weight: .medium))
                                .foregroundStyle(Theme.muted)
                                .padding(.horizontal, 9)
                                .frame(height: 24)
                                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 8))
                                .padding(.vertical, 10).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(session.can("job.assign", feature: "jobs") ? "Change the scheduled time" : "")
                    }
                }

                HStack(spacing: 8) {
                    if let assignedName = assignedDisplayName(for: job) {
                        HStack(spacing: 6) {
                            Text(nameInitials(assignedName))
                                .font(Theme.font(8, weight: .semibold))
                                .foregroundStyle(Theme.brandText)
                                .frame(width: 16, height: 16)
                                .background(Theme.brandSurface, in: Circle())
                            Text(shortName(assignedName))
                                .font(Theme.font(12, weight: .medium))
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(.horizontal, 7)
                        .frame(height: 24)
                        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 8))
                    }
                    if let balance = invoiceBalanceCents {
                        Text("\(money(balance, currency: "USD")) due")
                            .font(Theme.monoFont(11, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 4)
        .padding(.bottom, 10)
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
        HStack(spacing: 5) {
            Image(systemName: statusIcon(job.status).0)
                .font(.system(size: 11, weight: .semibold))
            Text(job.status.statusLabel)
                .font(Theme.font(12, weight: .medium))
            if showsMenu { Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)) }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(surface, in: RoundedRectangle(cornerRadius: 8))
        .padding(.vertical, 10)
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
                if let date = JobFiltering.date(job.scheduledFor) {
                    PaperDetailRow("Scheduled", value: date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                } else {
                    PaperDetailRow("Scheduled", value: "Not scheduled")
                }
                PaperDetailRow("Status", value: job.status.statusLabel)
                if let reason = job.pauseReason { PaperDetailRow("Pause reason", value: reason) }
                if let next = job.pauseNextAction { PaperDetailRow("Next action", value: next) }
            }
            VStack(alignment: .leading, spacing: 0) {
                PaperGroupHeader(title: "On this job")
                ForEach(availableTransitions(job).dropFirst(), id: \.self) { target in
                    Button { runTransition(target) } label: {
                        PaperMenuRow(transitionTitle(target), symbol: transitionSymbol(target))
                    }
                    .buttonStyle(.plain).disabled(busy)
                }
                if session.can("job.assign", feature: "jobs") {
                    Button { showSchedule = true } label: { PaperMenuRow("Schedule", symbol: "calendar", subtitle: "Pick a day and arrival window") }
                        .buttonStyle(.plain)
                    NavigationLink { JobAssignmentView(jobID: jobId) } label: { PaperMenuRow("Assign technician", symbol: "person.crop.circle.badge.plus") }
                        .buttonStyle(.plain)
                }
                NavigationLink { JobCloseoutView(jobID: jobId) } label: { PaperMenuRow("Wrap up", symbol: "checkmark.seal", subtitle: "Closeout checklist") }
                    .buttonStyle(.plain)
                NavigationLink { JobFollowUpsView(jobID: jobId) } label: { PaperMenuRow("Follow-ups", symbol: "list.bullet") }
                    .buttonStyle(.plain)
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
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
                } else if jobEstimates.isEmpty {
                    PaperEmptyState(symbol: "doc.text", title: "No estimates yet",
                                    message: "Build one from the price book. It's added to this job automatically.")
                }
                ForEach(jobEstimates) { estimate in
                    NavigationLink { EstimateDetailView(id: estimate.id) } label: {
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
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
                emptyCard("No invoice is linked to this job.")
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
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
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
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(activityFilter == filter ? .isSelected : [])
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(timeline(job)) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            Image(systemName: entry.symbol).font(.system(size: 11, weight: .semibold))
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
                                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
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
                        Group { if busy { ProgressView().tint(.white) } else { Image(systemName: "arrow.up").font(.system(size: 16, weight: .semibold)) } }
                            .foregroundStyle(.white).frame(width: 44, height: 44)
                            .background(Theme.brand.opacity(canSaveNote ? 1 : 0.4), in: Circle())
                    }
                    .buttonStyle(.plain)
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
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        .foregroundStyle(Theme.foreground)
        .padding(15)
        .contentShape(Rectangle())
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { actionLabel(title, icon: icon) }
            .buttonStyle(.plain)
            .disabled(busy)
    }

    private func emptyCard(_ message: String) -> some View {
        Text(message).font(Theme.font(13)).foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func availableTransitions(_ job: JobRecord) -> [String] {
        (job.allowedTransitions ?? []).filter {
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

    private func loadInvoices() async {
        guard session.can("invoice.view", feature: "invoicing") else { return }
        let generation = session.generation
        do {
            let all = try await api.fieldInvoices()
            guard session.generation == generation else { return }
            invoices = all.filter { $0.jobId == jobId }
                .sorted { $0.createdAt > $1.createdAt }
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
            let loadedNotes = try await api.fieldNotes(jobId)
            guard session.generation == generation else { return }
            notes = loadedNotes
            error = nil
        } catch is CancellationError {} catch {
            guard session.generation == generation else { return }
            self.error = error.localizedDescription
        }
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
        busy = true
        defer { busy = false }
        do {
            job = try await api.progressFieldJob(jobId, request: request)
            // The progress response carries no allowedTransitions; re-read the job so the
            // next step (Mark arrived, Start work, ...) appears without a manual refresh.
            await load()
            await store.refresh(api)
            error = nil
            return true
        } catch is CancellationError { return false } catch { self.error = error.localizedDescription; return false }
    }
    private func saveNote() async {
        busy = true
        defer { busy = false }
        do {
            let saved = try await api.addFieldNote(jobId, body: note.trimmingCharacters(in: .whitespacesAndNewlines))
            notes.append(saved)
            note = ""
            error = nil
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}
