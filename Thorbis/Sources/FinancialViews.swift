import SwiftUI
import UIKit

struct EstimatesView: View {
    /// Opened from the scorecard: only the estimates behind Close rate (TG-19), until cleared.
    var filter: RecordFilter? = nil
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var session: SessionController
    @EnvironmentObject var store: Store
    @State private var showAll = false
    @State private var missing = 0
    @State private var records: [EstimateRecord] = []
    @State private var loading = true
    @State private var error: String?
    @State private var search = ""
    /// Open, Approved or Declined (Paper 20E).
    @State private var tab = "Open"
    @State private var showCreate = false
    /// iPad's toolbar already carries the one create +; the list doesn't add a second.
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Title, customer or reference, so "EST-4F2A" or a customer's name finds it too.
    private var visible: [EstimateRecord] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return records }
        return records.filter { record in
            [record.title, store.customerName(record.customerId), "EST-\(record.id.suffix(4).uppercased())"]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    /// Which tab an estimate sits under (Paper 20E): approved and declined have their own; drafts,
    /// sent and viewed ones are all still open.
    private static func bucket(_ status: String) -> String {
        switch status {
        case "approved": "Approved"
        case "declined": "Declined"
        default: "Open"
        }
    }

    /// The tab's estimates: the ones out with customers first, then drafts, otherwise as listed.
    /// Opened from the scorecard, the filter owns the list and every status shows.
    private var shown: [EstimateRecord] {
        let rows = activeFilter == nil ? visible.filter { Self.bucket($0.status) == tab } : visible
        return rows.enumerated()
            .sorted { ($0.element.status == "draft" ? 1 : 0, $0.offset) < ($1.element.status == "draft" ? 1 : 0, $1.offset) }
            .map(\.element)
    }

    /// "Open · 4", "Approved", "Declined": only the open tab carries its count, as in Paper.
    private var tabBinding: Binding<String> {
        Binding(get: { tabLabel(tab) }, set: { label in tab = ["Open", "Approved", "Declined"].first { tabLabel($0) == label } ?? "Open" })
    }
    private func tabLabel(_ key: String) -> String {
        guard key == "Open" else { return key }
        let open = records.filter { Self.bucket($0.status) == "Open" }.count
        return open == 0 ? "Open" : "Open \u{00B7} \(open)"
    }

    /// Paper 20E: the 34 Bold title with what's open and waiting, a search field, Open / Approved /
    /// Declined, then the tab's estimates on one card. Each row: the customer and the amount, the
    /// reference and the work, then the status chip and when it last moved.
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                PaperHeader(title: "Estimates", subtitle: records.isEmpty && loading ? "Loading…" : estimatesSummary(records))
                    .environment(\.paperMenuButton, false)
                if let error { ErrorBanner(message: error) { await load() } }
                if let active = activeFilter { RecordFilterBar(filter: active, missing: missing) { showAll = true } }
                DocumentSearchField(text: $search, label: "Search estimates")
                if activeFilter == nil && !records.isEmpty {
                    PaperTabs(options: ["Open", "Approved", "Declined"].map { tabLabel($0) }, selection: tabBinding)
                        .padding(.top, 12)
                }
                if loading && records.isEmpty { ListRoomSkeleton(count: 5, threeLines: true) }
                let rows = shown
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, record in
                    PaperSplitDestinationLink(id: record.id, value: PaperRoute.estimate(record.id)) {
                        EstimateDetailView(id: record.id).thorbisBackButton()
                    } label: {
                        DocumentCardRow(title: store.customerName(record.customerId),
                                        amount: paperLinesTotal(record.lines).map { money($0, currency: record.lines.first?.unitPrice.currency ?? "USD") },
                                        subtitle: "EST-\(record.id.suffix(4).uppercased()) \u{00B7} \(record.title)",
                                        chip: DocumentStatus(estimateStatus: record.status),
                                        note: estimateNote(record),
                                        divider: index > 0)
                    }
                    .buttonStyle(RowPressStyle())
                    .documentCardSlot(first: index == 0, last: index == rows.count - 1)
                }
                if !records.isEmpty && visible.isEmpty {
                    ListRoomEmpty(title: "No estimates match \u{201C}\(search.trimmingCharacters(in: .whitespaces))\u{201D}.",
                                  message: "Try a customer's name, the work, or an EST number.")
                } else if !records.isEmpty && rows.isEmpty {
                    ListRoomEmpty(title: tab == "Open" ? "No open estimates." : "No \(tab.lowercased()) estimates.",
                                  message: tab == "Open" ? "Drafts and estimates out with customers show here." : nil)
                }
                if !loading && records.isEmpty && error == nil {
                    let canCreate = session.can("estimate.create", feature: "estimates")
                    ListRoomEmpty(title: "No estimates.",
                                  message: canCreate ? "Price the work before you start." : "Estimates your shop sends show up here.",
                                  actionTitle: canCreate ? "Create an estimate" : nil, action: { showCreate = true })
                }
            }
            .environment(\.paperRowInset, ListRoom.gutter)
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: showAll) { await load() }
        .refreshable { await load() }
        .toolbar {
            // The same quiet + circle as the Jobs and Customers headers, not the stock glass button.
            if session.can("estimate.create", feature: "estimates"), sizeClass != .regular {
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    Button { showCreate = true } label: { CreamCircleLabel(symbol: "plus", ink: true) }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("New estimate")
                }
            }
        }
        .sheet(isPresented: $showCreate, onDismiss: { Task { await load() } }) { SheetSurface { NewEstimateView() } }
    }
    private var activeFilter: RecordFilter? { showAll ? nil : filter }

    /// Beside the chip, when the estimate last moved: "Not sent · edited yesterday", "3 days ago".
    private func estimateNote(_ record: EstimateRecord) -> String? {
        func when(_ raw: String?) -> String? {
            JobFiltering.date(raw).map { $0.formatted(.relative(presentation: .named)) }
        }
        switch record.status {
        case "draft": return when(record.updatedAt).map { "Not sent \u{00B7} edited \($0)" } ?? "Not sent"
        case "approved": return when(record.approvedAt)
        case "declined": return when(record.declinedAt)
        default: return when(record.sentAt)
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        if let active = activeFilter {
            let result = await FilteredRecords.load(active.ids, fetch: { id in
                let estimate = try await api.fieldEstimate(id)
                JobDetailCache.save(estimate: estimate)
                return estimate
            }, cached: { JobDetailCache.estimate($0) })
            // "Show all" while this was loading: the unfiltered list owns the screen now.
            guard !Task.isCancelled, activeFilter == active else { return }
            records = result.records
            missing = result.missing
            error = nil
            return
        }
        do { records = try await api.fieldEstimates(); error = nil }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

struct EstimateDetailView: View {
    let id: String
    /// The job it was opened from; in-person approval stores the signature with that job.
    var jobID: String? = nil
    /// Opened from the job's next step: hand it to the customer as soon as it loads (TF-05), and
    /// go back to the job once they approve, where the invoice is the next step (TF-06).
    var presentsOnOpen = false
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var session: SessionController
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var autoPresented = false
    @State private var record: EstimateRecord?
    @State private var error: String?
    @State private var busy = false
    @State private var confirm = false
    @State private var succeeded = 0
    @State private var showRevisionEditor = false
    @State private var action = ""
    @EnvironmentObject private var customerView: JobEstimateHandoffPresenter
    @EnvironmentObject private var legacyHandoff: LegacyCustomerPresenter
    @StateObject private var customerWindowAnchor = CustomerWindowAnchor()
    @State private var memberPricing: MemberPricing?
    @State private var showPDF = false
    @State private var openCustomer: Customer?
    @State private var showRevisions = false
    /// Paper 35C: the reference and status pill, the customer at 28 Bold, what it's for and its total;
    /// then (16 from the edges) the progress card, the lines on one card, Edit, and the activity.
    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OfflineBanner()
                SavedCopyNote(savedAt: api.savedCopyDate("/v1/estimates/\(id)"))
                if let error {
                    ErrorBanner(message: error, retry: record == nil ? { await load() } : nil)
                        .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 8)
                }
                if let record {
                    let currency = record.lines.first?.unitPrice.currency ?? record.options?.first?.currency ?? "USD"
                    estimateHeader(record, currency: currency)
                        .padding(.horizontal, Theme.gutter).padding(.top, 14)
                    VStack(alignment: .leading, spacing: 12) {
                        estimateTimeline(record)
                        if let signature = record.approvalSignature { SignatureBadge(label: "Approved by", signature: signature) }
                        // The estimate's own lines. With options they are listed apart and honestly labelled;
                        // the customer approves an option's lines, not these.
                        let options = record.options ?? []
                        if !record.lines.isEmpty || options.isEmpty {
                            LinesCard(label: options.isEmpty ? nil : "Estimate line items",
                                      lines: record.lines, totalLabel: "Total",
                                      total: paperLinesTotal(record.lines), currency: currency,
                                      memberLine: memberLine(record.lines, currency: currency))
                        }
                        ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                            LinesCard(label: "Option \(index + 1) · \(option.title)", note: option.description,
                                      lines: option.lines, totalLabel: "Option total",
                                      total: option.totalAmount, currency: option.currency,
                                      memberLine: memberLine(option.lines, currency: option.currency))
                        }
                        if canEdit(record) {
                            Button { showRevisionEditor = true } label: {
                                Text("Edit").font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.foreground)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(Theme.card, in: Capsule())
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityLabel(record.status == "draft" ? "Edit lines" : "Revise estimate")
                        }
                        RecordActivitySection(recordType: "estimate", recordID: record.id)
                    }
                    .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 16)
                } else if error == nil {
                    SkeletonRows(count: 5, leading: false, inset: 0).padding(.horizontal, Theme.gutter).padding(.top, 12)
                }
            }
            .padding(.bottom, 28)
        }
        #if DEBUG
        .modifier(PaperPreviewScrollAnchor())
        #endif
    }

    /// Edit while it's a draft, revise once it's been sent or declined.
    private func canEdit(_ record: EstimateRecord) -> Bool {
        guard session.can("estimate.create", feature: "estimates") else { return false }
        return record.status == "draft" || record.status == "sent" || record.status == "declined"
    }

    /// "EST-4F2A" with the status pill, the customer (opens them), then what it's for and its total.
    @ViewBuilder private func estimateHeader(_ record: EstimateRecord, currency: String) -> some View {
        let status = DocumentStatus(estimateStatus: record.status)
        let customerName = store.customerName(record.customerId)
        let customer = session.can("customer.view", feature: "core_crm") ? store.customers.first(where: { $0.id == record.customerId }) : nil
        let figure = estimateFigure(record, currency: currency)
        let revision: String? = (record.currentRevisionNumber ?? 0) > 1 ? "Rev \(record.currentRevisionNumber ?? 0)" : nil
        let name: String? = record.title.isEmpty ? nil : record.title
        let parts: [String?] = [name, figure, revision]
        let subtitle = parts.compactMap { $0 }.joined(separator: " \u{00B7} ")
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("EST-\(record.id.suffix(4).uppercased())").font(Theme.font(14, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.muted)
                Text(status.word).font(Theme.font(12, weight: .semibold)).foregroundStyle(status.tone.text)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(status.tone.surface, in: Capsule())
                    .accessibilityLabel("Status, \(status.word)")
                    .accessibilityIdentifier("estimate-chip-status")
            }
            if let customer {
                Button { openCustomer = customer } label: { estimateTitle(customerName) }
                    .buttonStyle(RowPressStyle())
                    .accessibilityHint("Opens the customer")
            } else {
                estimateTitle(customerName)
            }
            if !subtitle.isEmpty {
                Text(subtitle).font(Theme.font(15)).monospacedDigit().foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "$340.00", or with options "3 options from $1,200.00"; nil when the lines can't be totalled.
    private func estimateFigure(_ record: EstimateRecord, currency: String) -> String? {
        let options = record.options ?? []
        if options.isEmpty { return paperLinesTotal(record.lines).map { money($0, currency: currency) } }
        guard let lowest = options.map({ $0.totalAmount }).min() else { return nil }
        return "\(options.count) options from \(money(lowest, currency: currency))"
    }

    /// Paper 35C: the customer at 28 Bold, -0.02em.
    private func estimateTitle(_ name: String) -> some View {
        Text(name).font(Theme.heading()).tracking(-0.56)
            .foregroundStyle(Theme.foreground)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("document-title")
    }

    /// One step of Paper 35C's progress card: Created, Sent, then Approved (or Declined).
    struct TimelineStep {
        let label: String
        let date: Date?
    }

    private func timelineSteps(_ record: EstimateRecord) -> [TimelineStep] {
        let declined = record.status == "declined"
        return [
            TimelineStep(label: "Created", date: JobFiltering.date(record.createdAt)),
            TimelineStep(label: "Sent", date: JobFiltering.date(record.sentAt)),
            TimelineStep(label: declined ? "Declined" : "Approved",
                         date: JobFiltering.date(declined ? record.declinedAt : record.approvedAt)),
        ]
    }

    /// Paper 35C: dots joined by a line; done steps green, the current one a larger brand dot, the
    /// rest hollow with "Not yet". Only the dates the record carries; nothing is guessed.
    @ViewBuilder private func estimateTimeline(_ record: EstimateRecord) -> some View {
        let steps = timelineSteps(record)
        let finished = record.status == "approved" || record.status == "declined"
        let current = steps.lastIndex(where: { $0.date != nil }) ?? 0
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                timelineColumn(step, index: index, count: steps.count, current: current,
                               finished: finished, declined: record.status == "declined")
            }
        }
        .padding(.vertical, 14).padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func timelineColumn(_ step: TimelineStep, index: Int, count: Int, current: Int,
                                             finished: Bool, declined: Bool) -> some View {
        let reached = index <= current
        let isCurrent = index == current && !finished
        let mark: Color = declined && index == count - 1 ? Theme.statusAttention : Theme.statusDone
        let pending = Theme.muted.opacity(0.5)
        let leftLine: Color = index == 0 ? .clear : (reached ? Theme.statusDone : pending)
        let rightLine: Color = index == count - 1 ? .clear : (index + 1 <= current ? Theme.statusDone : pending)
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                Rectangle().fill(leftLine).frame(height: 2)
                if isCurrent {
                    Circle().fill(Theme.brand).frame(width: 18, height: 18)
                } else if reached {
                    Circle().fill(mark).frame(width: 12, height: 12)
                } else {
                    Circle().strokeBorder(pending, lineWidth: 2).frame(width: 12, height: 12)
                }
                Rectangle().fill(rightLine).frame(height: 2)
            }
            .frame(height: 18)
            .accessibilityHidden(true)
            VStack(spacing: 0) {
                Text(step.label).font(Theme.font(13, weight: .semibold))
                    .foregroundStyle(isCurrent ? Theme.brandText : reached ? Theme.foreground : Theme.muted)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(step.date.map { $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) } ?? "Not yet")
                    .font(Theme.font(12)).foregroundStyle(Theme.muted)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Paper 35C's lines card: each line's name and amount (15), a hairline between, then the total
    /// in 16 Bold over a stronger rule. Invoices use the same card. A label above it only when there
    /// is more than one card (an estimate's options).
    struct LinesCard: View {
        var label: String? = nil
        var note: String = ""
        let lines: [FieldLine]
        let totalLabel: String
        let total: Int?
        let currency: String
        var extraRows: [(String, String)] = []
        var memberLine: String? = nil

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                if let label { SectionHeader(title: label, count: lines.isEmpty ? nil : lines.count) }
                VStack(alignment: .leading, spacing: 0) {
                    if !note.isEmpty {
                        Text(note).font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                    }
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        lineRow(line)
                            .overlay(alignment: .top) { if index > 0 || !note.isEmpty { WellDivider(leading: 0) } }
                    }
                    if lines.isEmpty {
                        Text("No line items yet.").font(Theme.font(15)).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    if let total, !lines.isEmpty {
                        totalRow(totalLabel, money(total, currency: currency), strong: extraRows.isEmpty)
                            .overlay(alignment: .top) { Rectangle().fill(Theme.muted.opacity(0.5)).frame(height: 1) }
                        ForEach(Array(extraRows.enumerated()), id: \.offset) { index, row in
                            totalRow(row.0, row.1, strong: index == extraRows.count - 1)
                                .overlay(alignment: .top) { WellDivider(leading: 0) }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                if let memberLine {
                    Text(memberLine).font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func lineRow(_ line: FieldLine) -> some View {
            let text = LineText(line.description)
            let unit = money(line.unitPrice.amount, currency: line.unitPrice.currency)
            let amount = paperLinesTotal([line]).map { money($0, currency: line.unitPrice.currency) }
            return HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.name).font(Theme.font(15)).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    if line.quantity != 1 {
                        Text("\(line.quantity) \u{00D7} \(unit)").font(Theme.font(13)).monospacedDigit()
                            .foregroundStyle(Theme.muted)
                    }
                    if let detail = text.detail {
                        Text(detail).font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let amount {
                    Text(amount).font(Theme.monoFont(15)).foregroundStyle(Theme.foreground)
                        .lineLimit(1).fixedSize()
                }
            }
            .padding(.vertical, 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([text.name, text.detail, "quantity \(line.quantity)", "\(unit) each", amount]
                .compactMap { $0 }.joined(separator: ", "))
        }

        private func totalRow(_ label: String, _ value: String, strong: Bool) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label).font(Theme.font(strong ? 16 : 15, weight: strong ? .bold : .regular))
                    .foregroundStyle(strong ? Theme.foreground : Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(value).font(Theme.monoFont(strong ? 16 : 15, weight: strong ? .bold : .regular))
                    .foregroundStyle(strong ? Theme.foreground : Theme.muted)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)
        }
    }

    private func estimateDateVerb(_ status: String) -> String {
        switch status {
        case "sent": "Sent"
        case "approved": "Approved"
        case "declined": "Declined"
        default: "Created"
        }
    }

    /// The date that goes with the status word: when it was sent, approved or declined.
    private func estimateStatusDate(_ record: EstimateRecord) -> String? {
        switch record.status {
        case "sent": record.sentAt ?? record.createdAt
        case "approved": record.approvedAt ?? record.createdAt
        case "declined": record.declinedAt ?? record.createdAt
        default: record.createdAt
        }
    }

    /// MF-05: a member's price is the supporting line under a total, never a second total.
    private func memberLine(_ lines: [FieldLine], currency: String) -> String? {
        guard let memberPricing, memberPricing.isMember, memberPricing.discountPercent > 0, !lines.isEmpty else { return nil }
        let memberTotal = lines.reduce(0) { $0 + $1.quantity * memberPricing.memberPrice($1.unitPrice.amount) }
        return "Member price \(money(memberTotal, currency: currency)) · \(memberPricing.discountPercent)% off"
    }

    /// Paper 35D's sheet heading: "EST-1039 · Nikolai Petrov".
    private var menuTitle: String {
        guard let record else { return "Estimate" }
        return "EST-\(record.id.suffix(4).uppercased()) \u{00B7} \(store.customerName(record.customerId))"
    }

    /// Everything that isn't the next step: approve, decline, the PDF and the customer.
    private var menuItems: [ThorbisMenuItem] {
        guard let record else { return [] }
        var items: [ThorbisMenuItem] = []
        // Paper 35C/35D: Edit is the pill under the lines, so the menu keeps the rest.
        if record.status == "draft", jobID != nil, TechJobFlow.canShow(record, can: estimateAbilities),
           session.can("estimate.send", feature: "estimates") {
            // The commit shows (and so sends) it; sending without showing stays one tap away.
            items.append(ThorbisMenuItem("Send estimate", icon: "paperplane") { action = "Send"; confirm = true })
        }
        if record.status == "sent", session.can("estimate.approve", feature: "estimates") {
            items.append(ThorbisMenuItem(jobID != nil && (record.options ?? []).isEmpty ? "Approve without a signature" : "Approve estimate",
                                         icon: "checkmark.circle") { action = "Approve"; confirm = true })
            items.append(ThorbisMenuItem("Decline estimate", icon: "xmark.circle", role: .destructive) { action = "Decline"; confirm = true })
        }
        items.append(ThorbisMenuItem("View PDF", icon: "doc.text") { showPDF = true })
        // Paper 35B: every sent version, newest first. A draft that was never sent has none.
        let sentRevisions = record.currentRevisionNumber ?? 0
        if sentRevisions > 0 {
            items.append(ThorbisMenuItem("Revisions", icon: "clock.arrow.circlepath", detail: "\(sentRevisions)") { showRevisions = true })
        }
        if session.can("customer.view", feature: "core_crm"), let customer = store.customers.first(where: { $0.id == record.customerId }) {
            items.append(ThorbisMenuItem(customer.name, icon: "person", subtitle: "Customer") { openCustomer = customer })
        }
        return items
    }

    var body: some View {
        scrollContent
        .background(Theme.canvas)
        .background(CustomerWindowAnchorView(anchor: customerWindowAnchor))
        .onAppear { customerWindowAnchor.visible = true }
        .onDisappear { customerWindowAnchor.visible = false }
        .foregroundStyle(Theme.foreground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if record != nil {
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    // Paper 35D: the page's own menu is a bottom sheet under "EST-1039 · Nikolai Petrov".
                    ThorbisMenu(items: menuItems, title: menuTitle, accessibilityLabel: "Edit, approve or open the PDF",
                                presentation: .sheet) {
                        PaperCircleLabel(symbol: "ellipsis", size: 44, fill: Theme.card)
                    }
                }
            }
        }
        .thorbisDestination(isPresented: $showPDF) {
            CommercialDocumentView(path: "/v1/estimates/\(id)/document").toolbar(.visible, for: .navigationBar)
        }
        .thorbisDestination(item: $openCustomer) { CustomerDetailView(customer: $0) }
        .thorbisDestination(isPresented: $showRevisions) {
            if let record {
                EstimateRevisionsView(estimate: record, customerName: store.customerName(record.customerId),
                                      onRevised: { revised in
                                          self.record = revised
                                          error = nil
                                      })
            }
        }
        .safeAreaInset(edge: .bottom) { estimateBar }
        .sensoryFeedback(.success, trigger: succeeded)
        .thorbisConfirm("\(action) this estimate?", isPresented: $confirm,
                        actions: [ThorbisConfirmAction(action, role: action == "Decline" ? .destructive : nil) { Task { await performAction() } }])
        .sheet(isPresented: $showRevisionEditor) { SheetSurface {
            if let record {
                EstimateRevisionEditorView(estimate: record) { revised in
                    self.record = revised
                    error = nil
                }
            }
        } }
        .task { await loadAndMaybePresent() }
        .refreshable { await SavedCopies.$liveOnly.withValue(true) { await load() } }
    }

    private func customerMode(_ record: EstimateRecord, lease: LegacyCustomerHandoffLease) -> some View {
        CustomerModeContainer(onUnlocked: { legacyHandoff.authenticatedExit(for: lease) }, authenticateOwner: customerHandoffAuthenticate) { handBack in
            CustomerEstimatePresentation(estimate: record, jobID: jobID, customerName: store.customerName(record.customerId),
                                         financing: session.can("organization.view", feature: FinancingWords.feature),
                                         currentAuthority: { legacyHandoff.active?.lease === lease && legacyHandoff.active?.isCurrent(api: api, session: session) == true },
                                         onApproved: { if legacyHandoff.active?.lease === lease,
                                                          legacyHandoff.active?.isCurrent(api: api, session: session) == true,
                                                          let updated = $0 { self.record = updated } }, onDone: handBack)
        }
        .environmentObject(api)
    }

    private func customerModeClosed(authority: CustomerHandoffExitAuthority, source: UIWindow) {
        guard let exitRevision = customerView.idleRevision else { return }
        Task {
            guard customerView.isIdleRevision(exitRevision), customerWindowAnchor.isAttached(to: source), authority.isCurrent(api: api, session: session) else { return }
            await load()
            guard customerView.isIdleRevision(exitRevision), customerWindowAnchor.isAttached(to: source), authority.isCurrent(api: api, session: session) else { return }
            // TF-06: approved from the job's next step, the job (and its invoice step) comes back.
            if presentsOnOpen, record?.status == "approved" { dismiss() }
        }
    }
    @ViewBuilder private var estimateBar: some View {
        if let record, record.status == "draft", jobID != nil, TechJobFlow.canShow(record, can: estimateAbilities) {
            // TF-05: on site, showing is sending. The draft is issued as it's handed over, no second step.
            PaperActionBar(title: "Customer view · Estimates", symbol: "iphone", busy: busy) { Task { await handToCustomer() } }
        } else if let record, record.status == "draft", session.can("estimate.send", feature: "estimates") {
            PaperActionBar(title: "Send estimate", symbol: "paperplane", busy: busy) { action = "Send"; confirm = true }
        } else if let record, record.status == "sent", canShowSent(record) {
            // On site, the next step is the customer's yes: hand them the options to choose and sign.
            // Options (and estimates without a job) are signed through an issued link, which needs estimate.send.
            PaperActionBar(title: "Customer view · Estimates", symbol: "iphone", busy: busy) { Task { await presentToCustomer() } }
        }
    }

    private func canShowSent(_ record: EstimateRecord) -> Bool {
        guard session.can("estimate.approve", feature: "estimates") else { return false }
        let singleScopeOnJob = jobID != nil && (record.options ?? []).isEmpty
        return singleScopeOnJob || session.can("estimate.send", feature: "estimates")
    }

    private func loadAndMaybePresent() async {
        await load()
        guard presentsOnOpen, !autoPresented, let record, TechJobFlow.canShow(record, can: estimateAbilities) else { return }
        autoPresented = true
        await handToCustomer()
    }

    private var estimateAbilities: TechJobAbilities {
        TechJobAbilities(sendEstimate: session.can("estimate.send", feature: "estimates"),
                         approveEstimate: session.can("estimate.approve", feature: "estimates"))
    }

    /// Issues a draft (the revision the customer signs is frozen first), then opens customer mode.
    private func handToCustomer() async {
        guard let current = record else { return }
        if current.status == "draft" {
            busy = true
            defer { busy = false }
            do { record = try await api.sendFieldEstimate(id, expectedRevisionNumber: current.currentRevisionNumber ?? 0) }
            catch is CancellationError { return } catch { self.error = error.localizedDescription; return }
        }
        await presentToCustomer()
    }

    /// On a job, the estimate opens in that job's Customer view, so the customer can also see the
    /// job's other estimates, invoices and their own details. Without a job it stays a single document.
    private func presentToCustomer() async {
        guard let record else { return }
        guard let fallbackAuthority = CustomerHandoffExitAuthority.capture(api: api, session: session),
              let source = customerWindowAnchor.window else { return }
        if let jobID {
            busy = true
            let opened = await customerView.openCustomerView(jobID: jobID, customerID: record.customerId,
                customerName: store.customerName(record.customerId), start: .estimate(record.id), api: api, session: session, sourceWindow: source,
                sourceStillAttached: { customerWindowAnchor.isAttached(to: source) }) { _ in
                guard let exitRevision = customerView.idleRevision, customerWindowAnchor.isAttached(to: source), fallbackAuthority.isCurrent(api: api, session: session) else { return }
                await load()
                guard customerView.isIdleRevision(exitRevision), customerWindowAnchor.isAttached(to: source), fallbackAuthority.isCurrent(api: api, session: session) else { return }
                if presentsOnOpen, self.record?.status == "approved" { dismiss() }
            }
            busy = false
            if opened != .unavailable { return }
        }
        guard customerWindowAnchor.isAttached(to: source), fallbackAuthority.isCurrent(api: api, session: session),
              let lease = customerView.claimLegacy() else { return }
        let content = AnyView(customerMode(record, lease: lease))
        guard let handoff = LegacyCustomerHandoff(lease: lease, content: content, api: api, session: session,
            sourceAttached: { customerWindowAnchor.isAttached(to: source) },
            onDismiss: { _ in customerModeClosed(authority: fallbackAuthority, source: source) }),
              legacyHandoff.present(handoff, sourceWindow: source, api: api, session: session) else {
            lease.release(); error = "Customer view is unavailable. Please try again."; return
        }
    }

    private func performAction() async {
        guard let current = record else { return }
        busy = true
        defer { busy = false }
        do {
            switch action {
            case "Send": record = try await api.sendFieldEstimate(id, expectedRevisionNumber: current.currentRevisionNumber ?? 0)
            case "Approve":
                guard let revision = current.currentRevisionNumber else { return }
                record = try await api.approveFieldEstimate(id, revisionNumber: revision)
            case "Decline":
                guard let revision = current.currentRevisionNumber else { return }
                record = try await api.declineFieldEstimate(id, revisionNumber: revision)
            default: return
            }
            error = nil
            if action != "Decline" { succeeded += 1 }
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func load() async {
        do {
            let loaded = try await api.fieldEstimate(id)
            record = loaded
            JobDetailCache.save(estimate: loaded)
            error = nil
            if let customer = record?.customerId { memberPricing = try? await api.memberPricing(customer) }
        }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

struct InvoicesView: View {
    /// Opened from the scorecard: only the invoices behind Sold (TG-19), until cleared.
    var filter: RecordFilter? = nil
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @State private var showAll = false
    @State private var missing = 0
    @State private var records: [InvoiceRecord] = []
    @State private var error: String?
    @State private var loading = true
    @State private var search = ""
    /// Unpaid, Paid or Drafts (Paper 20F); Void only while there is a void invoice to show.
    @State private var tab = "Unpaid"
    /// Customer or reference, the two things a tech has in hand when a customer calls about a bill.
    private var visible: [InvoiceRecord] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return records }
        return records.filter { record in
            InvoiceReferenceSearch.matches(query: query, invoiceID: record.id,
                                           customerName: store.customerName(record.customerId))
        }
    }

    /// Which tab an invoice sits under: anything sent and not settled is unpaid.
    private static func bucket(_ status: String) -> String {
        switch status {
        case "paid": "Paid"
        case "draft": "Drafts"
        case "void", "voided": "Void"
        default: "Unpaid"
        }
    }

    private var tabKeys: [String] {
        records.contains { Self.bucket($0.status) == "Void" } ? ["Unpaid", "Paid", "Drafts", "Void"] : ["Unpaid", "Paid", "Drafts"]
    }

    /// The chosen tab, falling back to Unpaid when Void goes away.
    private var currentTab: String { tabKeys.contains(tab) ? tab : "Unpaid" }

    /// The tab's invoices; opened from the scorecard, the filter owns the list and every status shows.
    private var shown: [InvoiceRecord] {
        activeFilter == nil ? visible.filter { Self.bucket($0.status) == currentTab } : visible
    }

    /// "Unpaid · 5", "Paid", "Drafts": only the unpaid tab carries its count, as in Paper.
    private var tabBinding: Binding<String> {
        Binding(get: { tabLabel(currentTab) },
                set: { label in tab = tabKeys.first { tabLabel($0) == label } ?? "Unpaid" })
    }
    private func tabLabel(_ key: String) -> String {
        guard key == "Unpaid" else { return key }
        let unpaid = records.filter { Self.bucket($0.status) == "Unpaid" }.count
        return unpaid == 0 ? "Unpaid" : "Unpaid \u{00B7} \(unpaid)"
    }

    /// Paper 20F: the 34 Bold title with what's owed, a search field, Unpaid / Paid / Drafts, then
    /// the tab's invoices on one card: the customer and what's owed now (MF-04), the reference and
    /// where it stands under them.
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                PaperHeader(title: "Invoices", subtitle: records.isEmpty && loading ? "Loading…" : invoicesSummary(records))
                    .environment(\.paperMenuButton, false)
                if let error { ErrorBanner(message: error) { await load() } }
                if let active = activeFilter { RecordFilterBar(filter: active, missing: missing) { showAll = true } }
                DocumentSearchField(text: $search, label: "Search invoices")
                if activeFilter == nil && !records.isEmpty {
                    PaperTabs(options: tabKeys.map { tabLabel($0) }, selection: tabBinding)
                        .padding(.top, 12)
                }
                if loading && records.isEmpty { ListRoomSkeleton(count: 5, threeLines: false) }
                let rows = shown
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, record in
                    PaperSplitDestinationLink(id: record.id, value: PaperRoute.invoice(record.id)) {
                        InvoiceDetailView(id: record.id).thorbisBackButton()
                    } label: {
                        // MF-04: an unpaid invoice's row shows what's owed now, and says so.
                        DocumentCardRow(title: store.customerName(record.customerId),
                                        amount: invoiceAmount(record),
                                        subtitle: invoiceLine(record),
                                        divider: index > 0)
                    }
                    .buttonStyle(RowPressStyle())
                    .documentCardSlot(first: index == 0, last: index == rows.count - 1)
                }
                if !records.isEmpty && visible.isEmpty {
                    ListRoomEmpty(title: "No invoices match \u{201C}\(search.trimmingCharacters(in: .whitespaces))\u{201D}.",
                                  message: "Try a customer's name or an INV number.")
                } else if !records.isEmpty && rows.isEmpty {
                    ListRoomEmpty(title: currentTab == "Unpaid" ? "Nothing unpaid." : currentTab == "Drafts" ? "No drafts." : "No \(currentTab.lowercased()) invoices.",
                                  message: currentTab == "Unpaid" ? "Every sent invoice is paid." : nil)
                }
                if !loading && records.isEmpty && error == nil {
                    ListRoomEmpty(title: "No invoices.", message: "Invoices are made from a job. Open a finished job to invoice it.")
                }
            }
            .environment(\.paperRowInset, ListRoom.gutter)
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: showAll) { await load() }
        .refreshable { await load() }
    }

    /// What's owed now on a sent invoice; the whole total otherwise.
    private func invoiceAmount(_ record: InvoiceRecord) -> String? {
        let total = paperLinesTotal(record.lines)
        let due = total.map { max(0, $0 - record.amountPaid) }
        return (record.status == "issued" ? due : total).map { money($0, currency: record.currency) }
    }

    /// "INV-2188 · issued 21 days ago · balance due", "INV-2190 · paid Jul 3", "INV-2204 · not sent".
    private func invoiceLine(_ record: InvoiceRecord) -> String {
        var parts = ["INV-\(record.id.suffix(4).uppercased())"]
        switch record.status {
        case "draft":
            parts.append("not sent")
        case "paid":
            parts.append(JobFiltering.date(record.paidAt).map { "paid \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? "paid")
        case "void", "voided":
            parts.append("void")
        default:
            if let issued = JobFiltering.date(record.issuedAt) {
                let calendar = Calendar.current
                let days = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: issued),
                                                          to: calendar.startOfDay(for: .now)).day ?? 0)
                parts.append(days == 0 ? "issued today" : "issued \(days) day\(days == 1 ? "" : "s") ago")
            }
            let word = DocumentStatus(invoice: record).word
            parts.append(word == "Unpaid" ? "balance due" : word.lowercased())
        }
        return parts.joined(separator: " \u{00B7} ")
    }
    private var activeFilter: RecordFilter? { showAll ? nil : filter }

    private func load() async {
        loading = true
        defer { loading = false }
        if let active = activeFilter {
            let result = await FilteredRecords.load(active.ids, fetch: { try await api.fieldInvoice($0) },
                                                    cached: { JobDetailCache.invoice($0) })
            // "Show all" while this was loading: the unfiltered list owns the screen now.
            guard !Task.isCancelled, activeFilter == active else { return }
            records = result.records
            missing = result.missing
            error = nil
            return
        }
        do { records = try await api.fieldInvoices(); error = nil }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

struct InvoiceDetailView: View {
    let id: String
    /// Opened from the job's next step: once it's paid, go back to the job for wrap up (TF-09).
    var returnsWhenPaid = false
    var expectedJobScope: JobDocumentScope? = nil
    /// The job-scoped label is display only; the full id still controls every read and payment.
    var invoiceReference: String? = nil
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var session: SessionController
    @EnvironmentObject var store: Store
    @EnvironmentObject private var outbox: FieldOutbox
    @Environment(\.dismiss) private var dismiss
    @State private var record: InvoiceRecord?
    @State private var error: String?
    @State private var busy = false
    @State private var confirmIssue = false
    @State private var issued = 0
    @State private var showEditDraft = false
    @State private var showCollectPayment = false
    @State private var paymentModel: InvoicePaymentCollectionModel?
    @State private var showSignature = false
    @EnvironmentObject private var customerView: JobEstimateHandoffPresenter
    @EnvironmentObject private var legacyHandoff: LegacyCustomerPresenter
    @StateObject private var customerWindowAnchor = CustomerWindowAnchor()
    @State private var showPDF = false
    @State private var showDiscount = false
    @State private var openCustomer: Customer?

    /// "INV-2188 · Hollis Property Group" above the menu's rows (Paper 35D's heading, on invoices too).
    private var menuTitle: String {
        guard let record else { return "Invoice" }
        return "\(displayReference(record)) \u{00B7} \(store.customerName(record.customerId))"
    }

    /// The commit at the bottom is the next step (Issue or Collect); the rest lives here.
    private var menuItems: [ThorbisMenuItem] {
        guard let record else { return [] }
        var items: [ThorbisMenuItem] = []
        if record.status != "draft", record.status != "void" {
            items.append(ThorbisMenuItem("Customer view", icon: "iphone", isDisabled: busy) { Task { await presentToCustomer() } })
        }
        // Paper 40C: Edit is the pill under the payments.
        if canDiscountInvoice(record) {
            items.append(ThorbisMenuItem("Add discount or credit", icon: "tag") { if canDiscountInvoice(record) { showDiscount = true } })
        }
        items.append(ThorbisMenuItem("View PDF", icon: "doc.text") { showPDF = true })
        if let application = financingApplications.first, application.isOpen,
           session.can("invoice.payment.create", feature: FinancingWords.feature) {
            items.append(ThorbisMenuItem("Cancel financing application", icon: "xmark.circle", role: .destructive) { confirmCancelFinancing = true })
        }
        if session.can("customer.view", feature: "core_crm"), let customer = store.customers.first(where: { $0.id == record.customerId }) {
            items.append(ThorbisMenuItem(customer.name, icon: "person", subtitle: "Customer") { openCustomer = customer })
        }
        return items
    }

    @State private var financingApplications: [FinancingApplication] = []
    @State private var confirmCancelFinancing = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OfflineBanner()
                SavedCopyNote(savedAt: api.savedCopyDate("/v1/invoices/\(id)"))
                if let error {
                    ErrorBanner(message: error, retry: record == nil ? { await load() } : nil)
                        .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 8)
                }
                if let record {
                    // Paper 40C: the reference and status pill, the customer at 28 Bold and what it
                    // bills; then (16 from the edges) the balance card, payments, Edit, the lines.
                    let amounts = invoiceAmounts(record)
                    let total = amounts?.total
                    let due = amounts?.due
                    invoiceHeader(record)
                        .padding(.horizontal, Theme.gutter).padding(.top, 14)
                    VStack(alignment: .leading, spacing: 12) {
                    balanceCard(record, total: total, due: due)
                        .thorbisConfirm("Cancel this application?", message: "The customer's link stops working.",
                                        isPresented: $confirmCancelFinancing,
                                        actions: [
                                            ThorbisConfirmAction("Cancel application", role: .destructive) {
                                                if let application = financingApplications.first { Task { await cancelFinancing(application) } }
                                            },
                                        ])
                    invoiceProperties(record)
                    if let signed = record.customerAuthorization, signed.linesRevision == record.linesRevision {
                        SignatureBadge(label: "Authorized by", signature: signed)
                    } else if let waiting = outbox.waitingSignature(invoiceID: record.id), waiting.expectedLinesRevision == record.linesRevision {
                        // OF-02: signed on this phone, not yet on the server.
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Signed by \(waiting.signerName)").font(Theme.font(15, weight: .medium))
                            WaitingToSyncLabel()
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    } else if amounts != nil, record.jobId != nil, record.status != "void", session.can("invoice.edit", feature: "invoicing") {
                        Button { if canSignInvoice(record) { showSignature = true } } label: {
                            Label("Get customer signature", systemImage: "signature")
                                .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                    }
                    if let paymentModel {
                        InvoicePaymentsSection(
                            model: paymentModel,
                            invoice: record,
                            onCollectPayment: { startCollection() },
                            onInvoiceUpdated: { _ = accept($0) },
                            invoiceReference: displayReference(record)
                        )
                    }
                    if record.status == "draft", session.can("invoice.edit", feature: "invoicing") {
                        Button { showEditDraft = true } label: {
                            Text("Edit").font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.foreground)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(Theme.card, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Edit line items")
                    }
                    EstimateDetailView.LinesCard(label: "Line items", lines: record.lines, totalLabel: "Total", total: total,
                                                 currency: record.currency,
                                                 extraRows: due.map { due in
                                                     record.amountPaid > 0 && record.status != "draft"
                                                        ? [("Paid", money(record.amountPaid, currency: record.currency)), ("Balance due", money(due, currency: record.currency))] : []
                                                 } ?? [])
                    RecordActivitySection(recordType: "invoice", recordID: record.id)
                    }
                    .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 16)
                } else if error == nil {
                    SkeletonRows(count: 5, leading: false, inset: 0).padding(.horizontal, Theme.gutter).padding(.top, 12)
                }
            }
            .padding(.bottom, 28)
        }
        #if DEBUG
        .modifier(PaperPreviewScrollAnchor())
        #endif
        .background(Theme.canvas)
        .background(CustomerWindowAnchorView(anchor: customerWindowAnchor))
        .onAppear { customerWindowAnchor.visible = true }
        .onDisappear { customerWindowAnchor.visible = false }
        .foregroundStyle(Theme.foreground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if record != nil {
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    // Paper 35D ("Same menu on invoices"): a bottom sheet under "INV-2188 · Hollis Property Group".
                    ThorbisMenu(items: menuItems, title: menuTitle, accessibilityLabel: "Customer view, edit or open the PDF",
                                presentation: .sheet) {
                        PaperCircleLabel(symbol: "ellipsis", size: 44, fill: Theme.card)
                    }
                }
            }
        }
        .thorbisDestination(isPresented: $showPDF) {
            CommercialDocumentView(path: "/v1/invoices/\(id)/document").toolbar(.visible, for: .navigationBar)
        }
        .thorbisDestination(item: $openCustomer) { CustomerDetailView(customer: $0) }
        .sheet(isPresented: $showDiscount) { SheetSurface {
            if let record, canDiscountInvoice(record) {
                InvoiceDiscountSheet(invoice: record, canApply: { canDiscountInvoice(record) }) { updated in _ = accept(updated) }
            }
        } }
        .sheet(isPresented: $showSignature) { SheetSurface {
            if let record, let jobID = record.jobId, let amounts = invoiceAmounts(record) {
                SignatureCaptureSheet(title: "Sign for \(money(amounts.total, currency: record.currency))",
                                      summary: "By signing, \(store.customerName(record.customerId)) authorizes the work and charges on this invoice.",
                                      jobID: jobID, suggestedName: store.customerName(record.customerId),
                                      heading: "Sign invoice", summaryTitle: "Invoice summary",
                                      reference: displayReference(record),
                                      lines: signatureLines(record),
                                      totalText: money(amounts.total, currency: record.currency),
                                      queueOffline: { png, assetID, signer, signedAt in
                                          guard canSignInvoice(record) else { return false }
                                          // OF-01: the ink stays on the phone and authorizes this exact revision once online.
                                          return outbox.enqueueSignature(png, payload: .init(jobId: jobID, invoiceId: record.id,
                                                                                      expectedLinesRevision: record.linesRevision,
                                                                                      signerName: signer, signedAt: signedAt,
                                                                                      clientAssetId: assetID),
                                                                  policyVersion: session.policyVersion ?? 0) != nil
                                      }) { signature in
                    guard canSignInvoice(record) else { return "Refresh this invoice before signing." }
                    do {
                        let updated = try await api.authorizeFieldInvoice(id, expectedLinesRevision: record.linesRevision, signature: signature)
                        return accept(updated) ? nil : paymentModel?.loadError
                    } catch {
                        return error.isConnectivityFailure ? SignatureCaptureSheet.noSignal : error.localizedDescription
                    }
                }
            }
        } }
        .safeAreaInset(edge: .bottom) {
            if let paymentModel {
                InvoiceDetailFooter(
                    model: paymentModel,
                    canCollect: record.flatMap(invoiceAmounts) != nil && session.can("invoice.payment.create", feature: "payments"),
                    canIssue: record.flatMap(invoiceAmounts) != nil && session.can("invoice.issue", feature: "invoicing"),
                    issueTitle: issueCollects ? "Issue and collect payment" : "Issue invoice",
                    busy: busy,
                    onCollect: { startCollection() },
                    onIssue: { confirmIssue = true }
                )
            } else if let record, record.status == "draft", invoiceAmounts(record) != nil, session.can("invoice.issue", feature: "invoicing") {
                PrimaryButton(title: "Issue invoice", busy: busy) { confirmIssue = true }
                    .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
                    .background(Theme.canvas)
            }
        }
        .sensoryFeedback(.success, trigger: issued)
        .thorbisConfirm("Issue this invoice? Its line items will become final.", isPresented: $confirmIssue,
                        actions: [ThorbisConfirmAction(issueCollects ? "Issue and collect" : "Issue invoice") { Task { await issueThenCollect() } }])
        .sheet(isPresented: $showEditDraft) { SheetSurface {
            if let record {
                NavigationStack {
                    InvoiceLineEditorView(invoice: record) { updated in
                        guard accept(updated) else { return }
                        error = nil
                        Task { await paymentModel?.load() }
                    }
                    .environmentObject(api)
                    .environmentObject(session)
                    .environmentObject(store)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        } }
        .sheet(isPresented: $showCollectPayment, onDismiss: returnIfPaid) {
            if let paymentModel, let record, let paymentInvoice = paymentModel.invoice,
               paymentInvoice.id == record.id, invoiceAmounts(record) != nil, invoiceAmounts(paymentInvoice) != nil,
               session.can("invoice.payment.create", feature: "payments") {
                InvoicePaymentCollectionSheet(model: paymentModel, invoice: record, invoiceReference: displayReference(record))
                    .thorbisSheetSurface()
                    .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .task(id: session.generation) {
            paymentModel = nil
            record = nil
            await load()
            #if DEBUG
            if PaperPreview.enabled, PaperPreview.screen == "invoice-payment" {
                showCollectPayment = paymentModel?.canRecordPayment == true
            }
            #endif
        }
        .refreshable { await SavedCopies.$liveOnly.withValue(true) { await load() } }
    }
    /// Paper 40C: "INV-2188" with the status pill, the customer at 28 Bold (opens them), then the
    /// job it bills. There is no due date on an invoice record, so no "due" or "late" is worked out.
    @ViewBuilder private func invoiceHeader(_ record: InvoiceRecord) -> some View {
        let status = DocumentStatus(invoice: record)
        let job = record.jobId.flatMap { id in store.jobs.first(where: { $0.id == id }) }
        let customer = session.can("customer.view", feature: "core_crm") ? store.customers.first(where: { $0.id == record.customerId }) : nil
        let name = store.customerName(record.customerId)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                // The reference carries the title's identifier; tests read "Invoice 2209" from it.
                Text(displayReference(record)).font(Theme.font(14, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("invoice-detail-title")
                Text(status.word).font(Theme.font(12, weight: .semibold)).foregroundStyle(status.tone.text)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(status.tone.surface, in: Capsule())
                    .accessibilityLabel("Status, \(status.word)")
                    .accessibilityIdentifier("invoice-chip-status")
            }
            if let customer {
                Button { openCustomer = customer } label: { invoiceTitle(name) }
                    .buttonStyle(RowPressStyle())
                    .accessibilityHint("Opens the customer")
            } else {
                invoiceTitle(name)
            }
            if let job {
                Text(job.title).font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func invoiceTitle(_ name: String) -> some View {
        Text(name).font(Theme.heading()).tracking(-0.56)
            .foregroundStyle(Theme.foreground)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    /// Paper 40C's balance card: what's owed now (or the total, or what was paid) in the 28 Bold
    /// heading (Paper draws 30), and on the trailing side when it was issued, paid or voided. Red
    /// only when the server says overdue.
    @ViewBuilder private func balanceCard(_ record: InvoiceRecord, total: Int?, due: Int?) -> some View {
        // A total that can't be worked out safely reads "Unavailable" instead of a wrong figure.
        let paidInFull = due == 0 && record.amountPaid > 0
        let label = record.status == "draft" ? "Total" : paidInFull ? "Paid in full" : "Balance due"
        let cents: Int? = paidInFull ? record.amountPaid : record.status == "draft" ? total : due
        let overdue = record.status == "overdue"
        let date = invoiceDate(record)
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(Theme.font(13, weight: .semibold))
                    .foregroundStyle(overdue ? Theme.destructive : Theme.muted)
                Text(cents.map { money($0, currency: record.currency) } ?? "Unavailable")
                    .font(Theme.heading()).monospacedDigit().tracking(-0.7)
                    .accessibilityIdentifier(cents == nil ? "invoice-invalid-total" : "document-figure")
                    .foregroundStyle(cents == 0 ? Theme.muted : Theme.foreground)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
            if let date {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(date.0).font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.foreground)
                    Text(date.1).font(Theme.font(13)).foregroundStyle(Theme.muted)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(overdue ? Theme.destructiveSurface : Theme.card,
                    in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    /// When it was paid, voided, issued or created, as ("Issued", "Jul 18").
    private func invoiceDate(_ record: InvoiceRecord) -> (String, String)? {
        if record.status == "paid" { return JobFiltering.date(record.paidAt).map { ("Paid", documentDate($0)) } }
        if record.status == "void" { return JobFiltering.date(record.voidedAt).map { ("Voided", documentDate($0)) } }
        let verb = record.issuedAt == nil ? "Created" : "Issued"
        return JobFiltering.date(record.issuedAt ?? record.createdAt).map { (verb, documentDate($0)) }
    }

    /// CP-17: the financing application in words (never a credit reason), as a card row.
    @ViewBuilder private func invoiceProperties(_ record: InvoiceRecord) -> some View {
        if let application = financingApplications.first, let words = FinancingWords.status(application, forCustomer: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Financing").font(Theme.font(15)).foregroundStyle(Theme.foreground)
                Text("\(words) · \(money(application.amount.amount, currency: application.amount.currency))")
                    .font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    private func displayReference(_ invoice: InvoiceRecord) -> String {
        invoiceReference ?? "INV-\(invoice.id.suffix(4).uppercased())"
    }

    /// Paper 36's summary above the signature: each line's name, "2 × $60.00" under it when there
    /// is more than one, and the line's amount as the lines card shows it.
    private func signatureLines(_ record: InvoiceRecord) -> [SignatureSummaryLine] {
        record.lines.map { line in
            let unit = money(line.unitPrice.amount, currency: line.unitPrice.currency)
            let detail: String? = line.quantity == 1 ? nil : "\(line.quantity) \u{00D7} \(unit)"
            let amount = paperLinesTotal([line]).map { money($0, currency: line.unitPrice.currency) } ?? ""
            return SignatureSummaryLine(id: line.id, title: LineText(line.description).name, detail: detail, amount: amount)
        }
    }

    private func customerInvoiceMode(_ record: InvoiceRecord, lease: LegacyCustomerHandoffLease) -> some View {
        CustomerModeContainer(onUnlocked: { legacyHandoff.authenticatedExit(for: lease) }, authenticateOwner: customerHandoffAuthenticate) { handBack in
            CustomerInvoicePresentation(
                invoice: record, customerName: store.customerName(record.customerId),
                canSign: session.can("invoice.edit", feature: "invoicing"),
                onPay: paymentModel?.canRecordPayment == true && session.can("invoice.payment.create", feature: "payments") ? {
                    Task {
                        guard await StaffUnlock.unlock(reason: "Unlock to take payment"),
                              legacyHandoff.active?.lease === lease,
                              legacyHandoff.active?.isCurrent(api: api, session: session) == true else { return }
                        legacyHandoff.authenticatedExit(for: lease, .collect)
                    }
                } : nil,
                financing: session.can("invoice.payment.create", feature: FinancingWords.feature),
                currentAuthority: { legacyHandoff.active?.lease === lease && legacyHandoff.active?.isCurrent(api: api, session: session) == true },
                onSigned: { updated in
                    guard legacyHandoff.active?.lease === lease,
                          legacyHandoff.active?.isCurrent(api: api, session: session) == true else { return }
                    let paidChanged = updated.amountPaid != self.record?.amountPaid
                    _ = accept(updated)
                    if paidChanged, let paymentModel {
                        Task {
                            await paymentModel.load()
                            guard legacyHandoff.active?.lease === lease,
                                  legacyHandoff.active?.isCurrent(api: api, session: session) == true else { return }
                            if let loaded = paymentModel.invoice { self.record = loaded }
                        }
                    }
                }, onDone: handBack)
        }.environmentObject(api)
    }

    /// On a job, the invoice opens in that job's Customer view, with its payments and balance beside
    /// the job's other documents. Without a verified job it stays a single document.
    private func presentToCustomer() async {
        guard let record else { return }
        guard let fallbackAuthority = CustomerHandoffExitAuthority.capture(api: api, session: session),
              let source = customerWindowAnchor.window else { return }
        if let jobID = record.jobId, expectedJobScope.map({ $0.contains(record) }) != false {
            busy = true
            let handoffAuthority = CustomerHandoffExitAuthority.capture(api: api, session: session)
            let opened = await customerView.openCustomerView(jobID: jobID, customerID: record.customerId,
                customerName: store.customerName(record.customerId), start: .invoice(record.id), api: api, session: session, sourceWindow: source,
                sourceStillAttached: { customerWindowAnchor.isAttached(to: source) }) { exit in
                guard let exitRevision = customerView.idleRevision, customerWindowAnchor.isAttached(to: source), let handoffAuthority,
                      handoffAuthority.isCurrent(api: api, session: session) else { return }
                await load(currentAuthority: { customerView.isIdleRevision(exitRevision) && customerWindowAnchor.isAttached(to: source) && handoffAuthority.isCurrent(api: api, session: session) })
                guard customerView.isIdleRevision(exitRevision), customerWindowAnchor.isAttached(to: source), handoffAuthority.isCurrent(api: api, session: session) else { return }
                guard case .collect(let invoiceID) = exit, invoiceID == id, paymentModel?.canRecordPayment == true,
                      paymentModel?.invoice?.id == invoiceID,
                      paymentModel?.offlineCopy == false, paymentModel?.historyComplete == true, paymentModel?.loadError == nil,
                      session.can("invoice.payment.create", feature: "payments") else { return }
                startCollection()
            }
            busy = false
            if opened != .unavailable { return }
        }
        guard customerWindowAnchor.isAttached(to: source), fallbackAuthority.isCurrent(api: api, session: session),
              let lease = customerView.claimLegacy() else { return }
        let content = AnyView(customerInvoiceMode(record, lease: lease))
        guard let handoff = LegacyCustomerHandoff(lease: lease, content: content, api: api, session: session,
            capability: "invoice.view", feature: "invoicing",
            sourceAttached: { customerWindowAnchor.isAttached(to: source) }, onDismiss: { exit in
                guard let exitRevision = customerView.idleRevision else { return }
                Task {
                    guard customerView.isIdleRevision(exitRevision), customerWindowAnchor.isAttached(to: source), fallbackAuthority.isCurrent(api: api, session: session) else { return }
                    if case .collect = exit {
                        await load(currentAuthority: { customerView.isIdleRevision(exitRevision) && customerWindowAnchor.isAttached(to: source) && fallbackAuthority.isCurrent(api: api, session: session) })
                        guard customerView.isIdleRevision(exitRevision), customerWindowAnchor.isAttached(to: source), fallbackAuthority.isCurrent(api: api, session: session) else { return }
                        guard paymentModel?.invoice?.id == record.id, paymentModel?.canRecordPayment == true,
                              paymentModel?.offlineCopy == false, paymentModel?.historyComplete == true,
                              paymentModel?.loadError == nil, session.can("invoice.payment.create", feature: "payments") else {
                            error = "Refresh this invoice before collecting payment."
                            return
                        }
                        startCollection()
                    }
                    guard customerView.isIdleRevision(exitRevision), customerWindowAnchor.isAttached(to: source), fallbackAuthority.isCurrent(api: api, session: session) else { return }
                    await loadFinancing(currentAuthority: { customerView.isIdleRevision(exitRevision) && customerWindowAnchor.isAttached(to: source) && fallbackAuthority.isCurrent(api: api, session: session) })
                }
            }), legacyHandoff.present(handoff, sourceWindow: source, api: api, session: session) else {
            lease.release(); error = "Customer view is unavailable. Please try again."; return
        }
    }

    /// TF-08: issuing and collecting are one step for the tech; payment opens right after.
    private func invoiceAmounts(_ invoice: InvoiceRecord) -> CustomerDocumentAmounts? {
        CustomerDocumentAmounts(lines: invoice.lines, currency: invoice.currency, amountPaid: invoice.amountPaid)
    }

    private func canSignInvoice(_ invoice: InvoiceRecord) -> Bool {
        guard let current = record, current == invoice, current.status != "void",
              current.jobId != nil, invoiceAmounts(current) != nil else { return false }
        return session.can("invoice.edit", feature: "invoicing")
    }

    private func canDiscountInvoice(_ invoice: InvoiceRecord) -> Bool {
        guard let current = record, current == invoice, current.status == "draft",
              invoiceAmounts(current) != nil, !session.isOffline else { return false }
        return session.can("invoice.discount", feature: "invoicing")
    }

    private func startCollection() {
        guard let record, invoiceAmounts(record) != nil, let paymentModel,
              paymentModel.invoice == record, paymentModel.canRecordPayment,
              session.can("invoice.payment.create", feature: "payments") else { return }
        showCollectPayment = true
    }

    private func issueThenCollect() async {
        guard await issue(), issueCollects, paymentModel?.canRecordPayment == true else { return }
        startCollection()
    }

    private func returnIfPaid() {
        if returnsWhenPaid, paymentModel?.invoice?.status == "paid" { dismiss() }
    }

    private var issueCollects: Bool {
        session.can("invoice.issue", feature: "invoicing") && session.can("invoice.payment.create", feature: "payments")
    }
    @discardableResult private func issue() async -> Bool {
        guard let current = record, current.status == "draft", invoiceAmounts(current) != nil,
              session.can("invoice.issue", feature: "invoicing") else { return false }
        busy = true
        defer { busy = false }
        do {
            let issued = try await api.issueFieldInvoice(id, expectedLinesRevision: current.linesRevision)
            guard accept(issued) else { return false }
            error = nil
            self.issued += 1
            await paymentModel?.load()
            record = paymentModel?.invoice
            return true
        }
        catch is CancellationError { return false } catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult private func accept(_ invoice: InvoiceRecord) -> Bool {
        guard let paymentModel, paymentModel.acceptInvoiceMutationResponse(invoice) else {
            record = nil
            error = paymentModel?.loadError
            return false
        }
        record = invoice
        return true
    }

    private func load(currentAuthority: @escaping @MainActor () -> Bool = { true }) async {
        guard currentAuthority() else { return }
        let generation = session.generation
        guard expectedJobScope.map({ $0.organizationID == session.activeOrganization?.id }) != false else {
            record = nil
            paymentModel = nil
            return
        }
        if paymentModel == nil {
            paymentModel = InvoicePaymentCollectionModel(api: api, invoiceID: id, expectedJobScope: expectedJobScope)
            paymentModel?.outbox = outbox
            paymentModel?.policyVersion = session.policyVersion ?? 0
        }
        guard let paymentModel else { return }
        await paymentModel.load()
        guard currentAuthority(), session.generation == generation else { return }
        record = paymentModel.invoice
        if paymentModel.invoice != nil {
            error = nil
        } else if let loadError = paymentModel.loadError {
            error = loadError
        }
        await loadFinancing(currentAuthority: currentAuthority)
    }

    private func cancelFinancing(_ application: FinancingApplication) async {
        do {
            let canceled = try await api.cancelFinancingApplication(invoiceID: id, applicationID: application.id)
            financingApplications = financingApplications.map { $0.id == canceled.id ? canceled : $0 }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Reads applications back from the lender; a newly funded loan reloads the payments.
    private func loadFinancing(currentAuthority: @escaping @MainActor () -> Bool = { true }) async {
        guard currentAuthority(), let record, record.status != "draft", record.status != "void",
              session.can("invoice.view", feature: FinancingWords.feature),
              let latest = try? await api.refreshFinancingApplications(invoiceID: id) else { return }
        guard currentAuthority() else { return }
        let newlyFunded = latest.contains { $0.status == "funded" } && !financingApplications.contains { $0.status == "funded" }
        financingApplications = latest
        if newlyFunded, let paymentModel {
            await paymentModel.load()
            guard currentAuthority() else { return }
            if let invoice = paymentModel.invoice { self.record = invoice }
        }
    }
}

/// One priced line, same type as the job's Invoice tab: 15/500 description over a 13pt
/// "2 × $60.00" and the line total in mono. Space, not a line, sits between lines (v2).
struct CommercialLineView: View {
    let line: FieldLine
    var divider = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        // At accessibility sizes the amount reads under the line, so the description keeps the full width.
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                             : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 3) {
                Text(line.description).font(Theme.font(15, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(line.quantity) × \(money(line.unitPrice.amount, currency: line.unitPrice.currency))")
                    .font(Theme.font(15)).monospacedDigit().foregroundStyle(Theme.muted)
            }
            if !stacked { Spacer(minLength: 8) }
            let total = line.quantity.multipliedReportingOverflow(by: line.unitPrice.amount)
            if !total.overflow {
                Text(money(total.partialValue, currency: line.unitPrice.currency))
                    .moneyStyle(.line)
            }
        }
        .foregroundStyle(Theme.foreground)
        .padding(15)
        .frame(maxWidth: stacked ? .infinity : nil, minHeight: 56, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// MF-01/MF-03/MF-04: the amount a screen is about, labelled, at the hero size. Zero reads muted.
struct MoneyFigure: View {
    let label: String
    let cents: Int
    let currency: String
    /// Redesign phase 3: the staff document screens set the figure in semibold.
    var strong = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.font(15)).foregroundStyle(Theme.muted)
            // MF-06: a recorded payment rolls the balance down instead of swapping it.
            Group {
                if strong {
                    Text(money(cents, currency: currency))
                        .font(Font.custom("Inter-Regular", size: 34, relativeTo: .largeTitle).weight(.semibold).monospacedDigit())
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                } else {
                    Text(money(cents, currency: currency)).moneyStyle(.hero)
                }
            }
            .tracking(-0.5)
            .foregroundStyle(cents == 0 ? Theme.muted : Theme.foreground)
            .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: cents)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Document pieces (estimate and invoice detail)

/// Redesign phase 3: a document's header in Linear's grammar — the kind and reference as a quiet
/// eyebrow, the title at 30 semibold, then property chips that wrap (status with its glyph, who,
/// the job, the date, the amount). Chips with something to open are buttons; the rest are labels.
struct DocumentHeader<Chips: View>: View {
    let eyebrow: String
    let title: String
    @ViewBuilder var chips: Chips

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(eyebrow).font(Theme.font(13, weight: .medium)).monospacedDigit().foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text(title).font(Theme.font(30, weight: .medium)).tracking(-0.6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)
            FlowRow(spacing: 6, lineSpacing: 6) { chips }
                .padding(.top, 14)
                .accessibilityElement(children: .contain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Sent Jul 18" for a document's date chip; nil when the date doesn't parse.
func documentDateChipText(_ verb: String, _ raw: String?) -> String? {
    JobFiltering.date(raw).map { "\(verb) \(documentDate($0))" }
}

/// "Jul 18", with the year only when it isn't this year.
func documentDate(_ date: Date) -> String {
    Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        ? date.formatted(.dateTime.month(.abbreviated).day())
        : date.formatted(.dateTime.month(.abbreviated).day().year())
}

/// A status's colour, used only for the dot beside its word.
func documentStatusTint(_ status: String) -> Color {
    switch status {
    case "approved", "paid", "completed": Theme.success
    case "sent", "issued", "open": Theme.warning
    case "declined", "void", "canceled": Theme.destructive
    default: Theme.muted
    }
}

extension View {
    /// The panel a section's rows sit on: radius 14, tone only (v2: a 1px box around a section is a
    /// costume, so there is no rim).
    func documentPanel() -> some View {
        clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .panelBackground(cornerRadius: Theme.cardRadius)
    }
}

/// A section label, the lines on one panel with every description in full, then the totals in
/// the amount column and an optional supporting line (a member's price) under the panel.
/// v2 Evidence: name, quantity, then the two-decimal amount right-aligned and tabular. Space, not a
/// rule, sets the totals apart.
struct DocumentLinesSection: View {
    let label: String
    var note: String = ""
    let lines: [FieldLine]
    let totalLabel: String
    let total: Int?
    let currency: String
    var extraRows: [(String, String)] = []
    var memberLine: String? = nil
    var onEdit: (() -> Void)? = nil
    var editDisabled = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The column hint only when the label fits beside it on one line; a long option name
            // ("Option 1 · Full system replacement") keeps the row to itself instead of wrapping.
            if let onEdit {
                SectionHeader(title: label, count: lines.isEmpty ? nil : lines.count) {
                    if !typeSize.isAccessibilitySize { editItemsButton(onEdit) }
                }
                if typeSize.isAccessibilitySize { editItemsButton(onEdit) }
                if !lines.isEmpty && !typeSize.isAccessibilitySize {
                    Text("Qty · Amount").font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .accessibilityHidden(true)
                        .padding(.horizontal, 4).padding(.bottom, 2)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    SectionHeader(title: label, count: lines.isEmpty ? nil : lines.count) {
                        if !lines.isEmpty && !typeSize.isAccessibilitySize {
                            Text("Qty · Amount").font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.muted)
                                .accessibilityHidden(true)
                        }
                    }
                    SectionHeader(title: label, count: lines.isEmpty ? nil : lines.count) { EmptyView() }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 2)
            }
            Well {
                if !note.isEmpty {
                    Text(note).font(Theme.font(15)).foregroundStyle(Theme.subtle)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, PaperCardMetrics.inset).padding(.top, 14).padding(.bottom, 4)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { line in EvidenceLineRow(line: line) }
                }
                .padding(.vertical, 6)
                if lines.isEmpty {
                    Text("No line items yet.").font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(PaperCardMetrics.inset)
                }
                if let total, !lines.isEmpty {
                    VStack(spacing: 0) {
                        EvidenceTotalRow(label: totalLabel, value: money(total, currency: currency), strong: extraRows.isEmpty)
                        ForEach(Array(extraRows.enumerated()), id: \.offset) { index, row in
                            EvidenceTotalRow(label: row.0, value: row.1, strong: index == extraRows.count - 1)
                        }
                    }
                    .padding(.top, 10).padding(.bottom, 12)
                }
            }
            if let memberLine {
                Text(memberLine).font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4).padding(.top, 8)
            }
        }
    }

    private func editItemsButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("Edit items", systemImage: "pencil")
                .font(Theme.font(14, weight: .medium))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.brandText)
        .disabled(editDisabled)
        .accessibilityHint("Opens the invoice editor")
        .accessibilityIdentifier("invoice-detail-edit-items")
    }
}

/// A line's one text shown as a name and its explanation (EstimateDetail.dc.html): "Coil cleaning"
/// then "Clean the outdoor and indoor coils…". Lines carry a single description, so this splits only
/// at a first sentence that reads like a name (2–8 words, at most 48 characters, not ending in an
/// abbreviation or number); anything else stays whole as the name. Nothing is dropped either way.
struct LineText: Equatable {
    let name: String
    let detail: String?

    private static let abbreviations: Set<String> = [
        "approx", "incl", "excl", "misc", "etc", "est", "qty", "ea", "no", "nos", "in", "ft", "yd", "lb", "lbs",
        "oz", "gal", "hr", "hrs", "min", "max", "std", "dia", "mr", "mrs", "ms", "dr", "st", "ave", "rd", "vs", "pt", "sq"]

    init(_ description: String) {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let stop = text.range(of: ". ") else { name = text; detail = nil; return }
        let head = String(text[..<stop.lowerBound]).trimmingCharacters(in: .whitespaces)
        let rest = String(text[stop.upperBound...]).trimmingCharacters(in: .whitespaces)
        let words = head.split(whereSeparator: \.isWhitespace)
        let last = words.last.map { String($0).lowercased().trimmingCharacters(in: .punctuationCharacters) } ?? ""
        guard (2...8).contains(words.count), head.count <= 48, !rest.isEmpty,
              !Self.abbreviations.contains(last), last.rangeOfCharacter(from: .letters) != nil,
              last.count > 1, rest.first?.isUppercase == true || rest.first?.isNumber == true
        else { name = text; detail = nil; return }
        name = head
        detail = rest
    }
}

/// Sum of line amounts in cents, or nil on overflow or a negative line.
/// The estimate lines a customer sees (EB-13): materials marked hidden fold into one "Materials"
/// line after the others with their sum, so no price is hidden and the lines still add up to the
/// total. The server's PDF and approval link fold the same way.
func customerEstimateLines(_ lines: [FieldLine]) -> [FieldLine] {
    customerEstimateProjection(lines, currency: lines.first?.unitPrice.currency ?? "USD") ?? []
}

func paperLinesTotal(_ lines: [FieldLine]) -> Int? {
    var total = 0
    for line in lines {
        guard line.quantity >= 0 else { return nil }
        let (amount, o1) = line.quantity.multipliedReportingOverflow(by: line.unitPrice.amount)
        let (next, o2) = total.addingReportingOverflow(amount)
        guard !o1, !o2 else { return nil }
        total = next
    }
    return total
}

/// Groups documents by status in a fixed order, unknown statuses last.
func paperDocumentGroups<T>(_ records: [T], status: KeyPath<T, String>, order: [String]) -> [(String, [T])] {
    let grouped = Dictionary(grouping: records) { $0[keyPath: status] }
    let keys = grouped.keys.sorted { (order.firstIndex(of: $0) ?? order.count, $0) < (order.firstIndex(of: $1) ?? order.count, $1) }
    return keys.map { ($0, grouped[$0] ?? []) }
}

/// Paper's document row, shaped like job and customer rows: the title over one muted line
/// ("customer · EST-1A2B", reference in mono), the amount on the right. Lists grouped by
/// status pass `showsStatus: false`, since the group header already says it.
struct PaperDocumentRow: View {
    enum Kind {
        case estimate, invoice, billingSchedule

        var symbol: String {
            switch self {
            case .estimate: "doc.text"
            case .invoice: "doc.plaintext"
            case .billingSchedule: "list.bullet.rectangle"
            }
        }
    }

    let kind: Kind
    let reference: String
    let title: String
    let subtitle: String
    let status: String
    let amount: String?
    var showsStatus = true
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.paperRowInset) private var inset

    /// design 2026-10-30: the list row, no tile. Title, then who and the reference; on the right
    /// the amount over the status word (or only the amount when the subtitle already says it).
    var body: some View {
        PaperListRow(title: title, subtitle: "\(subtitle) · \(reference)") {
            VStack(alignment: .trailing, spacing: 4) {
                if let amount { Text(amount).font(Theme.moneyFont(.line)).foregroundStyle(Theme.foreground) }
                if showsStatus { StatusWord(documentStatus: status) }
            }
            .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Document status as a word in a tinted chip (never colour alone).
struct PaperStatusChip: View {
    let status: String
    var body: some View {
        let tint: Color = switch status {
        case "approved", "paid", "completed": Theme.success
        case "sent", "issued", "open": Theme.warning
        case "declined", "void", "canceled": Theme.destructive
        default: Theme.muted
        }
        // MA-10: the word on the neutral well; the hue is a dot beside it, never the word itself.
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(status == "issued" ? "Unpaid" : status.statusLabel)
        }
            .font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.foreground)
            .padding(.horizontal, 10).frame(minHeight: Theme.chipHeight)
            .background(Theme.fill, in: Capsule())
    }
}

func money(_ cents: Int, currency: String) -> String {
    (Decimal(cents) / 100).formatted(.currency(code: currency))
}

/// The Estimates header's subtitle: what's waiting on customers and how much.
/// Paper 20E: "4 open · $21,190 waiting on customers".
func estimatesSummary(_ estimates: [EstimateRecord]) -> String {
    let open = estimates.filter { $0.status != "approved" && $0.status != "declined" }
    let waiting = estimates.filter { $0.status == "sent" }
    if open.isEmpty { return "Nothing open" }
    let count = "\(open.count) open"
    guard !waiting.isEmpty else { return "\(count) · nothing waiting on customers" }
    var total = 0
    for estimate in waiting {
        guard let amount = CustomerDocumentAmounts(lines: estimate.lines, currency: "USD")?.total else {
            return "\(count) · total unavailable"
        }
        let (next, overflow) = total.addingReportingOverflow(amount)
        guard !overflow else { return "\(count) · total unavailable" }
        total = next
    }
    return "\(count) · \(money(total, currency: "USD")) waiting on customers"
}

/// The Invoices header's subtitle (Paper 20F): "$8,615 unpaid · 5 invoices". Invoices carry no due
/// date yet, so the overdue figure Paper shows beside it is left out.
func invoicesSummary(_ invoices: [InvoiceRecord]) -> String {
    let unpaid = invoices.filter { $0.status == "issued" }
    guard !unpaid.isEmpty else { return "Everything is paid" }
    let count = "\(unpaid.count) invoice\(unpaid.count == 1 ? "" : "s")"
    var owed = 0
    for invoice in unpaid {
        guard invoice.currency == "USD",
              let amount = CustomerDocumentAmounts(lines: invoice.lines, currency: invoice.currency, amountPaid: invoice.amountPaid) else {
            return "Balance unavailable · \(count)"
        }
        let (next, overflow) = owed.addingReportingOverflow(amount.due)
        guard !overflow else { return "Balance unavailable · \(count)" }
        owed = next
    }
    return "\(money(owed, currency: "USD"))\u{00A0}unpaid · \(count)"
}

/// Paper 20E/20F's search field: a card well 48 tall, radius 14, the magnifier and 16pt words.
struct DocumentSearchField: View {
    @Binding var text: String
    /// Spoken name of the field ("Search estimates").
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.muted).accessibilityHidden(true)
            TextField(label, text: $text, prompt: .placeholder("Search"))
                .font(Theme.font(16)).foregroundStyle(Theme.foreground)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14).padding(.trailing, text.isEmpty ? 14 : 2)
        .frame(minHeight: 48)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 4)
    }
}

/// Paper 20E/20F's document row on a card: the customer and the amount in 16 Semibold, the
/// reference and what it's for in the 15 muted line, and (estimates) the status chip with when it
/// last moved. A hairline sits between rows. One VoiceOver stop.
struct DocumentCardRow: View {
    let title: String
    let amount: String?
    let subtitle: String
    var chip: DocumentStatus? = nil
    var note: String? = nil
    var divider = false
    /// Paper 54 and 54A's money rows (Payments, Get paid): the name in 16 Medium, the line under it
    /// in 14, 11 above and below. Paper 20E/20F's document rows keep the default.
    var compact = false
    /// The amount's colour; a refund reads in the destructive text colour.
    var amountTint: Color = Theme.foreground
    /// Compact rows only: a 13 Medium word under the amount ("Balance due").
    var amountNote: String? = nil
    var amountNoteTint: Color = Theme.muted
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if compact { compactRow } else { documentRow }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { if divider { WellDivider(leading: compact ? 16 : 0) } }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, subtitle, chip?.word, note, amount, amountNote].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
    }

    /// Paper 54/54A: words on the left, the amount (and its word) on the right, centred on the row.
    private var compactRow: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                             : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Theme.font(16, weight: .medium)).tracking(-0.16)
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(stacked ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                    .lineLimit(stacked ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: stacked ? .leading : .trailing, spacing: 0) {
                if let amount {
                    Text(amount).font(Theme.monoFont(16, weight: .semibold)).foregroundStyle(amountTint)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                if let amountNote {
                    Text(amountNote).font(Theme.font(13, weight: .medium)).foregroundStyle(amountNoteTint)
                        .lineLimit(1)
                }
            }
            .fixedSize(horizontal: !stacked, vertical: true)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .frame(minHeight: 56)
    }

    private var documentRow: some View {
        let stacked = typeSize.isAccessibilitySize
        let top = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                          : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return VStack(alignment: .leading, spacing: 3) {
            top {
                Text(title).font(Theme.font(16, weight: .semibold))
                    .foregroundStyle(chip?.tone == .cancelled ? Theme.muted : Theme.foreground)
                    .lineLimit(stacked ? nil : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let amount {
                    Text(amount).font(Theme.monoFont(16, weight: .semibold)).foregroundStyle(amountTint)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .fixedSize(horizontal: !stacked, vertical: false)
                }
            }
            Text(subtitle).font(Theme.font(15)).foregroundStyle(Theme.muted)
                .lineLimit(stacked ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
            if chip != nil || note != nil {
                HStack(spacing: 6) {
                    if let chip {
                        Text(chip.word).font(Theme.font(12, weight: .semibold)).foregroundStyle(chip.tone.text)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(chip.tone.surface, in: Capsule())
                    }
                    if let note {
                        Text(note).font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .lineLimit(stacked ? nil : 1)
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }
}

extension View {
    /// One row of a Paper 20E/20F card built row by row so long lists stay lazy: 16 from the screen
    /// edge, the first row rounds the top (`topGap` under what sits above it), the last the bottom.
    func documentCardSlot(first: Bool, last: Bool, topGap: CGFloat = 16) -> some View {
        let r = Theme.cardRadius
        let shape = UnevenRoundedRectangle(topLeadingRadius: first ? r : 0, bottomLeadingRadius: last ? r : 0,
                                           bottomTrailingRadius: last ? r : 0, topTrailingRadius: first ? r : 0,
                                           style: .continuous)
        return background(Theme.card, in: shape)
            .clipShape(shape)
            .padding(.horizontal, PaperCardMetrics.margin)
            .padding(.top, first ? topGap : 0)
    }
}

/// Web parity: discount a draft invoice. The amount and a reason the customer sees ("Discount —
/// Loyalty"), checked here against the total so the server's refusal is the rare case.
struct InvoiceDiscountSheet: View {
    let invoice: InvoiceRecord
    let canApply: () -> Bool
    let applied: (InvoiceRecord) -> Void
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var reason = ""
    @State private var amountProblem: String?
    @State private var reasonProblem: String?
    @State private var error: String?
    @State private var busy = false
    @FocusState private var amountFocused: Bool

    private var total: Int? { CustomerDocumentAmounts(lines: invoice.lines, currency: invoice.currency, amountPaid: invoice.amountPaid)?.total }

    /// "150", "150.5", "$1,250.00" → cents; nil when it isn't a plain amount.
    private var cents: Int? {
        let cleaned = amount.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Decimal(string: cleaned), value > 0 else { return nil }
        var scaled = value * 100, rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    var body: some View {
        // Paper 40D: Cancel, "Discount or credit" and Add in the title row; Amount off and the reason
        // the customer sees on one card; then the new total. The server takes an amount off the
        // whole invoice with a reason, so Paper's Type chips and "Applies to" are not offered.
        ThorbisModalSheet(title: "Discount or credit", closeLabel: "Cancel", onClose: busy ? nil : { dismiss() },
                          commitTitle: "Add", busy: busy,
                          commitIdentifier: "invoice-discount-apply", commit: { Task { await press() } },
                          commitInHeader: true) {
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Amount off").font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .accessibilityHidden(true)
                        TextField("", text: $amount, prompt: .placeholder("$0.00"))
                            .font(Theme.font(24, weight: .semibold)).monospacedDigit()
                            .keyboardType(.decimalPad)
                            .focused($amountFocused)
                            .onChange(of: amount) { _, _ in amountProblem = nil }
                            .accessibilityLabel("Discount amount in dollars")
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    WellDivider(leading: 0)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reason \u{00B7} shown to customer").font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .accessibilityHidden(true)
                        TextField("", text: $reason, prompt: .placeholder("Loyalty"))
                            .font(Theme.font(17, weight: .medium))
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.done)
                            .onSubmit { Task { await press() } }
                            .onChange(of: reason) { _, _ in reasonProblem = nil }
                            .accessibilityLabel("Reason")
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                }
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                if let amountProblem { FieldProblem(message: amountProblem).padding(.horizontal, 4) }
                if let reasonProblem { FieldProblem(message: reasonProblem).padding(.horizontal, 4) }
                if amountProblem == nil, reasonProblem == nil {
                    Text("Shown on the invoice as \u{201C}Discount \u{2014} \(reason.isEmpty ? "Loyalty" : reason)\u{201D}.")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
            }
            if let off = cents, let total, off <= total {
                newTotalCard(off, total: total)
            }
            if let error { ErrorBanner(message: error).padding(.horizontal, -Theme.gutter) }
        }
        .onAppear { amountFocused = true }
        .interactiveDismissDisabled(busy || !amount.isEmpty || !reason.isEmpty)
    }

    /// Paper 40D: what the invoice comes to with this discount, and what it was.
    private func newTotalCard(_ off: Int, total: Int) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text("New total").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.success)
                Text("Was \(money(total, currency: invoice.currency))").font(Theme.font(14)).monospacedDigit()
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(money(total - off, currency: invoice.currency))
                .font(Theme.font(24, weight: .bold)).monospacedDigit().tracking(-0.4)
                .foregroundStyle(Theme.foreground)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Theme.successSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Validate on commit: say what's missing under the field instead of locking the button.
    private func press() async {
        guard !busy else { return }
        guard canApply(), let total else { error = "Invoice total unavailable. Refresh before applying a discount."; return }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cents else { amountProblem = "Enter an amount, like 50.00."; return }
        guard cents <= total else { amountProblem = "A discount can\u{2019}t be more than the invoice total."; return }
        guard !trimmed.isEmpty else { reasonProblem = "Add a reason the customer will see, like Loyalty."; return }
        busy = true
        defer { busy = false }
        do {
            let updated = try await api.discountFieldInvoice(invoice.id, amountCents: cents, reason: trimmed)
            applied(updated)
            dismiss()
        } catch {
            self.error = error.isConnectivityFailure ? "No signal. The discount wasn\u{2019}t applied; try again when you\u{2019}re back online."
                                                     : error.localizedDescription
        }
    }
}

// MARK: - Estimate revisions (Paper 35B, 35E)

/// How one line differs between the revision being read and the one it is compared with.
struct EstimateRevisionChange: Identifiable, Equatable {
    enum Kind: Equatable { case same, repriced, removed, added }
    let id: String
    let name: String
    let kind: Kind
    /// The line's amount in the revision being read; for an added line, its amount in the other one.
    let amount: Int
    /// The line's amount in the other revision, when it is there too.
    let otherAmount: Int?

    /// `lines` against `other`: matched by line id, then by wording. A line only in `lines` is
    /// removed; lines only in `other` come last as added. Display only: amounts are the same
    /// quantity times unit price the lines card shows.
    static func compare(_ lines: [FieldLine], with other: [FieldLine]) -> [EstimateRevisionChange] {
        var remaining = other
        var changes: [EstimateRevisionChange] = []
        for line in lines {
            let amount = paperLinesTotal([line]) ?? 0
            let name = LineText(line.description).name
            let byID = remaining.firstIndex(where: { $0.id == line.id })
            let match = byID ?? remaining.firstIndex(where: { wording($0) == wording(line) })
            if let match {
                let twin = remaining.remove(at: match)
                let twinAmount = paperLinesTotal([twin]) ?? 0
                changes.append(EstimateRevisionChange(id: "line-\(line.id)", name: name,
                                                      kind: twinAmount == amount ? .same : .repriced,
                                                      amount: amount, otherAmount: twinAmount))
            } else {
                changes.append(EstimateRevisionChange(id: "line-\(line.id)", name: name, kind: .removed,
                                                      amount: amount, otherAmount: nil))
            }
        }
        for line in remaining {
            let amount = paperLinesTotal([line]) ?? 0
            changes.append(EstimateRevisionChange(id: "other-\(line.id)", name: LineText(line.description).name,
                                                  kind: .added, amount: amount, otherAmount: amount))
        }
        return changes
    }

    /// "1 added, 1 removed", "2 prices changed", or "no line changes".
    static func summary(_ changes: [EstimateRevisionChange]) -> String {
        let added = changes.filter { $0.kind == .added }.count
        let removed = changes.filter { $0.kind == .removed }.count
        let repriced = changes.filter { $0.kind == .repriced }.count
        var words: [String] = []
        if added > 0 { words.append("\(added) added") }
        if removed > 0 { words.append("\(removed) removed") }
        if repriced > 0 { words.append("\(repriced) price\(repriced == 1 ? "" : "s") changed") }
        return words.isEmpty ? "no line changes" : words.joined(separator: ", ")
    }

    private static func wording(_ line: FieldLine) -> String {
        line.description.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Paper 35B: every version of an estimate that was sent, newest first, then what the newest one
/// changed. A row opens that version as it went out (Paper 35E). Read-only: these are the
/// server's frozen copies (`GET /v1/estimates/{id}/revisions/{n}`), and nothing here edits one;
/// "Restore this version" on an older one opens the estimate's own revision editor on its lines.
struct EstimateRevisionsView: View {
    let estimate: EstimateRecord
    let customerName: String
    /// A restore saved a replacement draft: the estimate as the server returned it.
    var onRevised: (EstimateRecord) -> Void = { _ in }
    /// The estimate after a restore here, so no other version offers a second one over the new draft.
    @State private var revised: EstimateRecord?
    @EnvironmentObject private var api: APIClient
    @State private var revisions: [EstimateRevisionRecord] = []
    @State private var loading = true
    @State private var error: String?
    @State private var opened: EstimateRevisionRecord?

    private var reference: String { "EST-\(estimate.id.suffix(4).uppercased())" }
    private var newest: EstimateRevisionRecord? { revisions.first }

    private func previous(of revision: EstimateRevisionRecord) -> EstimateRevisionRecord? {
        revisions.first(where: { $0.revisionNumber == revision.revisionNumber - 1 })
    }

    /// Option packages keep their lines inside each option, so a line-by-line compare of the
    /// estimate's own lines would say nothing changed. Those versions are read as sent instead.
    private func comparable(_ a: EstimateRevisionRecord, _ b: EstimateRevisionRecord) -> Bool {
        (a.options ?? []).isEmpty && (b.options ?? []).isEmpty
    }

    private var card: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Revisions").font(Theme.font(34, weight: .bold)).tracking(-0.85)
                        .foregroundStyle(Theme.foreground)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(reference) \u{00B7} \(customerName)").font(Theme.font(15)).monospacedDigit()
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.gutter).padding(.top, 14)
                if let error {
                    ErrorBanner(message: error, retry: { await load() })
                        .padding(.top, 12)
                }
                if !revisions.isEmpty {
                    sectionLabel("Newest first")
                    VStack(spacing: 0) {
                        ForEach(Array(revisions.enumerated()), id: \.element.id) { index, revision in
                            Button { opened = revision } label: { row(revision, divided: index > 0) }
                                .buttonStyle(RowPressStyle())
                        }
                    }
                    .background(Theme.card, in: card)
                    .clipShape(card)
                    .padding(.horizontal, PaperCardMetrics.margin)
                } else if loading {
                    SkeletonRows(count: 3, leading: false, inset: 0)
                        .padding(.horizontal, Theme.gutter).padding(.top, 22)
                }
                if let newest, let before = previous(of: newest), comparable(newest, before) {
                    whatChanged(newest, since: before)
                }
            }
            .padding(.bottom, 44)
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .thorbisDestination(item: $opened) { revision in
            EstimateRevisionDetailView(reference: reference, customerName: customerName, revision: revision,
                                       current: revision.revisionNumber == newest?.revisionNumber ? nil : newest,
                                       estimate: revised ?? estimate,
                                       onRestored: { saved in
                                           revised = saved
                                           onRevised(saved)
                                       })
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.gutter).padding(.top, 22).padding(.bottom, 8)
    }

    /// Paper 35B's row: "Revision 3 · $340.00" in 16 Medium, when it was sent and what it changed in
    /// 14, and where it stands at the trailing edge (the newest in the brand tone, older ones
    /// "Replaced").
    private func row(_ revision: EstimateRevisionRecord, divided: Bool) -> some View {
        let isNewest = revision.revisionNumber == newest?.revisionNumber
        let state = isNewest ? Self.statusWord(revision.status) : "Replaced"
        let words = detail(revision)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Revision \(revision.revisionNumber) \u{00B7} \(money(revision.totalAmount, currency: revision.currency))")
                    .font(Theme.font(16, weight: .medium)).monospacedDigit().tracking(-0.16)
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if !words.isEmpty {
                    Text(words).font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(state).font(Theme.font(14, weight: .medium))
                .foregroundStyle(isNewest ? Theme.brandText : Theme.muted)
                .fixedSize()
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 11)
        .frame(minHeight: 56)
        .overlay(alignment: .top) { if divided { WellDivider() } }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this version as it was sent")
    }

    private static func statusWord(_ status: String) -> String {
        switch status {
        case "approved": return "Approved"
        case "declined": return "Declined"
        default: return "Sent"
        }
    }

    /// "Sent Jul 18, 9:12 a.m. · first estimate", or what it changed from the one before.
    private func detail(_ revision: EstimateRevisionRecord) -> String {
        var parts: [String] = []
        if let sent = JobFiltering.date(revision.issuedAt) { parts.append("Sent \(sent.stampLabel(year: false))") }
        if revision.revisionNumber == 1 {
            parts.append("first estimate")
        } else if let before = previous(of: revision), comparable(revision, before) {
            parts.append(EstimateRevisionChange.summary(EstimateRevisionChange.compare(before.lines, with: revision.lines)))
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// Paper 35B "What changed in revision 3": 52pt rows, what was added, removed or repriced since
    /// the version before, with the difference at the trailing edge.
    private func whatChanged(_ revision: EstimateRevisionRecord, since before: EstimateRevisionRecord) -> some View {
        let changes = EstimateRevisionChange.compare(before.lines, with: revision.lines).filter { $0.kind != .same }
        return VStack(alignment: .leading, spacing: 0) {
            sectionLabel("What changed in revision \(revision.revisionNumber)")
            VStack(spacing: 0) {
                if changes.isEmpty {
                    Text("No line changes.").font(Theme.font(16)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .padding(.horizontal, PaperCardMetrics.inset)
                }
                ForEach(Array(changes.enumerated()), id: \.element.id) { index, change in
                    changeRow(change, currency: revision.currency, divided: index > 0)
                }
            }
            .background(Theme.card, in: card)
            .clipShape(card)
            .padding(.horizontal, PaperCardMetrics.margin)
        }
    }

    /// Compared from the older version: "added" is new in this one, "removed" was dropped by it.
    private func changeRow(_ change: EstimateRevisionChange, currency: String, divided: Bool) -> some View {
        let delta: Int
        let verb: String
        switch change.kind {
        case .added:
            delta = change.amount
            verb = "Added"
        case .removed:
            delta = -change.amount
            verb = "Removed"
        case .repriced:
            delta = (change.otherAmount ?? change.amount) - change.amount
            verb = "Changed"
        case .same:
            delta = 0
            verb = ""
        }
        let sign: String = delta > 0 ? "+" : (delta < 0 ? "\u{2212}" : "")
        return HStack(alignment: .center, spacing: 12) {
            Text("\(verb) \(change.name)").font(Theme.font(16, weight: .medium)).tracking(-0.16)
                .foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(sign)\(money(abs(delta), currency: currency))").font(Theme.font(16, weight: .medium)).monospacedDigit()
                .foregroundStyle(delta > 0 ? Theme.success : Theme.foreground)
                .lineLimit(1).fixedSize()
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 8)
        .frame(minHeight: 52)
        .overlay(alignment: .top) { if divided { WellDivider() } }
        .accessibilityElement(children: .combine)
    }

    /// Revisions are numbered 1 up to the last one sent; each is read on its own, newest first.
    private func load() async {
        let last = estimate.currentRevisionNumber ?? 0
        guard last > 0 else { loading = false; return }
        loading = true
        defer { loading = false }
        var found: [EstimateRevisionRecord] = []
        var failure: String?
        for number in stride(from: last, through: 1, by: -1) {
            if Task.isCancelled { return }
            do {
                let revision = try await api.fieldEstimateRevision(estimate.id, number: number)
                found.append(revision)
                revisions = found
            } catch is CancellationError {
                return
            } catch {
                failure = error.isConnectivityFailure ? "No signal. Revisions show once you\u{2019}re back online."
                                                      : error.localizedDescription
                break
            }
        }
        error = failure
    }
}

/// Paper 35E: one sent version, read-only. An older version opens on what the current one changed
/// ("Changes vs Rev 2": lines the current one repriced on a warning row, lines it dropped struck
/// through on a red row) with the version as it was sent on the second segment. "Restore this
/// version" opens the estimate's revision editor on this version's lines; saving there is the
/// ordinary revise request, which makes a replacement draft and keeps every sent version. Paper's
/// "Why it changed" note needs a note on the revision, which the server does not store, so it is
/// not drawn.
struct EstimateRevisionDetailView: View {
    let reference: String
    let customerName: String
    let revision: EstimateRevisionRecord
    /// The estimate's current version when this is an older one; nil when this is the current one.
    let current: EstimateRevisionRecord?
    /// The estimate these versions belong to. With it, an older version of a sent or declined
    /// estimate offers "Restore this version" to people who can revise estimates.
    var estimate: EstimateRecord? = nil
    /// The estimate as the server returned it after a restore was saved.
    var onRestored: (EstimateRecord) -> Void = { _ in }
    @EnvironmentObject private var session: SessionController
    @State private var tab = ""
    @State private var restoring = false
    @State private var restored = false

    /// The estimate to revise, when this older version can be restored: the estimate is sent or
    /// declined (an approved one needs a change order, a draft is already a replacement), this
    /// screen compared against its current version, and the person may revise estimates.
    private var restoreTarget: EstimateRecord? {
        guard let estimate, let current, revision.revisionNumber < current.revisionNumber,
              estimate.status == "sent" || estimate.status == "declined",
              estimate.currentRevisionNumber == current.revisionNumber,
              session.can("estimate.create", feature: "estimates") else { return nil }
        return estimate
    }

    private static let asSent = "As sent"

    /// "Changes vs Rev 2"; nil when there is nothing to compare with, or when either version uses
    /// option packages (their lines live inside each option).
    private var changesTab: String? {
        guard let current, (revision.options ?? []).isEmpty, (current.options ?? []).isEmpty else { return nil }
        return "Changes vs Rev \(current.revisionNumber)"
    }

    private var showsChanges: Bool { changesTab != nil && tab != Self.asSent }

    private var tabBinding: Binding<String> {
        Binding(get: { showsChanges ? (changesTab ?? Self.asSent) : Self.asSent }, set: { tab = $0 })
    }

    /// "Jul 17, 8:50 a.m. · read-only".
    private var subtitle: String {
        let sent: String? = JobFiltering.date(revision.issuedAt).map { $0.stampLabel(year: false) }
        let parts: [String?] = [sent, "read-only"]
        return parts.compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    private var card: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(reference) \u{00B7} \(customerName)").font(Theme.font(14, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Revision \(revision.revisionNumber)").font(Theme.heading()).tracking(-0.56)
                        .foregroundStyle(Theme.foreground)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle).font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.gutter).padding(.top, 14)
                if let changesTab {
                    PaperTabs(options: [changesTab, Self.asSent], selection: tabBinding)
                        .padding(.top, 16)
                }
                VStack(alignment: .leading, spacing: 12) {
                    if showsChanges, let current {
                        changesCard(against: current)
                    } else {
                        sentCards
                    }
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.top, changesTab == nil ? 16 : 12)
            }
            .padding(.bottom, 28)
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { restoreBar }
        .sheet(isPresented: $restoring) { SheetSurface {
            if let target = restoreTarget {
                EstimateRevisionEditorView(estimate: target, restoring: revision) { saved in
                    restored = true
                    onRestored(saved)
                }
            }
        } }
    }

    /// Paper 35E's foot: what restoring does (13 muted, centred) over the brand commit. Saving in
    /// the editor makes a replacement draft, which becomes the next revision when it is sent.
    @ViewBuilder private var restoreBar: some View {
        if restored {
            Text("Restored as a new draft. Send it from the estimate.")
                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, PaperCardMetrics.margin).padding(.vertical, 12)
                .background(Theme.canvas)
        } else if restoreTarget != nil, let current {
            VStack(spacing: 10) {
                Text("Restoring makes this the Rev \(current.revisionNumber + 1) draft. Rev \(current.revisionNumber) stays in history.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                Button { restoring = true } label: {
                    Text("Restore this version").inkCommit()
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("estimate-revision-restore")
            }
            .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 10).padding(.bottom, 8)
            .background(Theme.canvas)
        }
    }

    /// The version as it went out: the estimate detail's lines card, one per option when it had
    /// options. The total is the one the server froze with the version.
    @ViewBuilder private var sentCards: some View {
        let options = revision.options ?? []
        let ownTotal: Int? = options.isEmpty ? revision.totalAmount : paperLinesTotal(revision.lines)
        if !revision.lines.isEmpty || options.isEmpty {
            EstimateDetailView.LinesCard(label: options.isEmpty ? nil : "Estimate line items",
                                         lines: revision.lines, totalLabel: "Rev \(revision.revisionNumber) total",
                                         total: ownTotal, currency: revision.currency)
        }
        ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
            EstimateDetailView.LinesCard(label: "Option \(index + 1) \u{00B7} \(option.title)", note: option.description,
                                         lines: option.lines, totalLabel: "Option total",
                                         total: option.totalAmount, currency: option.currency)
        }
    }

    /// Paper 35E's compare card: this version's lines with what the current one did to each, then
    /// this version's total over what the estimate comes to now.
    private func changesCard(against current: EstimateRevisionRecord) -> some View {
        let changes = EstimateRevisionChange.compare(revision.lines, with: current.lines)
        return VStack(spacing: 0) {
            ForEach(Array(changes.enumerated()), id: \.element.id) { index, change in
                changeRow(change, in: current, divided: index > 0)
            }
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Rev \(revision.revisionNumber) total").font(Theme.font(16, weight: .bold))
                        .foregroundStyle(Theme.foreground)
                    Text("Current (Rev \(current.revisionNumber)) is \(money(current.totalAmount, currency: current.currency))")
                        .font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(money(revision.totalAmount, currency: revision.currency)).font(Theme.monoFont(16, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 13)
            .overlay(alignment: .top) { Rectangle().fill(Theme.muted.opacity(0.5)).frame(height: 1) }
            .accessibilityElement(children: .combine)
        }
        .background(Theme.card, in: card)
        .clipShape(card)
    }

    private func changeRow(_ change: EstimateRevisionChange, in current: EstimateRevisionRecord, divided: Bool) -> some View {
        let rev = "Rev \(current.revisionNumber)"
        let note: String
        let tone: Color
        let surface: Color
        let bar: Color
        switch change.kind {
        case .same:
            note = "No change"
            tone = Theme.muted
            surface = Color.clear
            bar = Color.clear
        case .repriced:
            let nowCents = change.otherAmount ?? change.amount
            let now = money(nowCents, currency: current.currency)
            note = nowCents < change.amount ? "Price lowered to \(now) in \(rev)" : "Price raised to \(now) in \(rev)"
            tone = Theme.warning
            surface = Theme.warningSurface
            bar = Theme.statusInProgress
        case .removed:
            note = "Removed in \(rev)"
            tone = Theme.destructive
            surface = Theme.destructiveSurface
            bar = Theme.statusAttention
        case .added:
            note = "Added in \(rev)"
            tone = Theme.success
            surface = Theme.successSurface
            bar = Theme.statusDone
        }
        let struck = change.kind == .removed
        let quiet = struck || change.kind == .added
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(change.name).font(Theme.font(15)).strikethrough(struck)
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(note).font(Theme.font(13, weight: change.kind == .same ? .regular : .medium)).monospacedDigit()
                    .foregroundStyle(tone)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(money(change.amount, currency: revision.currency)).font(Theme.monoFont(15)).strikethrough(struck)
                .foregroundStyle(quiet ? Theme.muted : Theme.foreground)
                .lineLimit(1).fixedSize()
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface)
        .overlay(alignment: .leading) { Rectangle().fill(bar).frame(width: 3).accessibilityHidden(true) }
        .overlay(alignment: .top) { if divided { WellDivider(leading: 0) } }
        .accessibilityElement(children: .combine)
    }
}
