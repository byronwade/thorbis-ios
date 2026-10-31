import SwiftUI

/// `GET /v1/billing-schedules` item (invoicing billingScheduleSchema).
struct BillingSchedule: Codable, Identifiable, Hashable {
    struct Line: Codable, Hashable, Identifiable {
        let id: String
        let position: Int
        let description: String
        let scheduledAmount: FieldMoney
    }
    let id: String
    let customerId: String
    let jobId: String
    let retainageRateBps: Int
    let status: String
    let lines: [Line]
    let createdAt: String
    var total: Int { lines.reduce(0) { $0 + $1.scheduledAmount.amount } }
}

/// `GET /v1/billing-schedules/{id}` (ScheduleProgress).
struct BillingScheduleProgress: Decodable {
    struct LineProgress: Decodable { let lineId: String; let billedToDate: Int; let remaining: Int }
    let schedule: BillingSchedule
    let lines: [LineProgress]
    let invoiceIds: [String]
    let retainedToDate: Int
    let releasedToDate: Int
    let retainageOutstanding: Int
    let depositsBilled: Int
    let depositCredited: Int
    let depositOutstanding: Int
    let readyToBill: Bool?
    var billedToDate: Int { lines.reduce(0) { $0 + $1.billedToDate } }
    var remaining: Int { lines.reduce(0) { $0 + $1.remaining } }
}

/// Schedule commands answer with the schedule and the draft invoice they created.
struct BillingScheduleCommandResult: Decodable {
    let schedule: BillingSchedule
    let invoice: InvoiceRecord
}

extension APIClient {
    func billingSchedules() async throws -> [BillingSchedule] {
        var items: [BillingSchedule] = []
        var cursor: String?
        repeat {
            let page: Items<BillingSchedule> = try await send("GET", "/v1/billing-schedules", cursor: cursor)
            items += page.items
            guard page.nextCursor != cursor else { break }
            cursor = page.nextCursor
        } while cursor != nil && items.count < 2_000
        return items
    }

    func billingSchedule(_ id: String) async throws -> BillingScheduleProgress {
        guard UUID(uuidString: id) != nil else { throw Problem(title: "Invalid record ID", status: nil, detail: id) }
        return try await send("GET", "/v1/billing-schedules/\(id)")
    }

    /// Deposit on a job born from an approved estimate; the server derives the schedule.
    func requestJobDeposit(jobID: String, amountCents: Int, idempotencyKey: String) async throws -> BillingScheduleCommandResult {
        struct Body: Encodable { let jobId: String; let idempotencyKey: String; let amount: FieldMoney }
        return try await send("POST", "/v1/billing-schedules/deposit-requests",
                              body: Body(jobId: jobID, idempotencyKey: idempotencyKey, amount: .init(amount: amountCents, currency: "USD")))
    }

    /// `bill-remainder` or `release-retainage`, each with its own idempotency key.
    func billingScheduleCommand(_ id: String, _ command: String, idempotencyKey: String) async throws -> BillingScheduleCommandResult {
        guard UUID(uuidString: id) != nil, ["bill-remainder", "release-retainage"].contains(command) else {
            throw Problem(title: "Invalid billing command", status: nil, detail: command)
        }
        struct Body: Encodable { let idempotencyKey: String }
        return try await send("POST", "/v1/billing-schedules/\(id)/\(command)", body: Body(idempotencyKey: idempotencyKey))
    }
}

/// Web billing: every schedule of values with what's billed and what's left.
struct BillingSchedulesView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @State private var schedules: [BillingSchedule] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Billing").font(Theme.font(30, weight: .medium)).tracking(-0.6).accessibilityAddTraits(.isHeader)
                    Text("Progress billing and deposits by job").font(Theme.font(15)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
                .padding(.bottom, 12)
                if let error { ErrorBanner(message: error).padding(.horizontal, -PaperCardMetrics.margin) }
                if loading && schedules.isEmpty { SkeletonRows(count: 4, leading: false, inset: 0) }
                ForEach(paperDocumentGroups(schedules, status: \.status, order: ["open", "closed"]), id: \.0) { status, group in
                    PaperGroupHeader(title: status == "open" ? "Open" : "Closed", count: group.count).padding(.top, 10)
                        .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
                    PaperCardList(data: group) { schedule in
                        NavigationLink(value: PaperRoute.billingSchedule(schedule.id)) {
                            PaperDocumentRow(kind: .billingSchedule, reference: "SOV-\(schedule.id.suffix(4).uppercased())",
                                             title: store.customerName(schedule.customerId),
                                             subtitle: "\(schedule.lines.count) line\(schedule.lines.count == 1 ? "" : "s")\(schedule.retainageRateBps > 0 ? " · \(schedule.retainageRateBps / 100)% retainage" : "")",
                                             status: schedule.status, amount: money(schedule.total, currency: "USD"))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !loading && schedules.isEmpty && error == nil {
                    PaperEmptyState(symbol: "list.bullet.rectangle", title: "No billing schedules yet",
                                    message: "A schedule starts when a job is billed in stages or takes a deposit.")
                }
            }
            .paperCardMargin().padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        let generation = session.generation
        loading = true
        defer { loading = false }
        do {
            let loaded = try await api.billingSchedules()
            guard session.generation == generation else { return }
            schedules = loaded.sorted { $0.createdAt > $1.createdAt }
            error = nil
        } catch is CancellationError {} catch {
            guard session.generation == generation else { return }
            self.error = error.localizedDescription
        }
    }
}

struct BillingScheduleDetailView: View {
    let scheduleID: String
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @State private var progress: BillingScheduleProgress?
    @State private var error: String?
    @State private var busy = false
    @State private var confirm: String?
    /// One key per intended command, kept until the server answers, so a retry never bills twice.
    @State private var pendingKeys: [String: String] = [:]
    @State private var createdInvoiceID: String?

    var body: some View {
        // Captured so dismissing the confirm (which clears `confirm`) can't blank the command
        // before the action runs it.
        let pendingConfirm = confirm
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let progress {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SOV-\(progress.schedule.id.suffix(4).uppercased()) · \(store.customerName(progress.schedule.customerId))")
                            .font(Theme.monoFont(12, weight: .medium)).foregroundStyle(Theme.muted)
                        Text("Billing schedule").font(Theme.font(24, weight: .medium)).tracking(-0.36).accessibilityAddTraits(.isHeader)
                        StatusWord(text: progress.schedule.status == "open" ? "Open" : "Closed",
                                   tint: progress.schedule.status == "open" ? Theme.warning : nil)
                    }
                    .padding(.bottom, 14)
                    // design 2026-10-30: figures on one panel, every group on its own panel, no rules.
                    VStack(alignment: .leading, spacing: 22) {
                        PaperStatRow(stats: [
                            .init(label: "Billed", value: money(progress.billedToDate, currency: "USD")),
                            .init(label: "Remaining", value: money(progress.remaining, currency: "USD")),
                        ])
                        if progress.depositsBilled > 0 || progress.retainedToDate > 0 {
                            PaperSection("Deposits and retainage") {
                                VStack(spacing: 0) {
                                    if progress.depositsBilled > 0 {
                                        PaperDetailRow("Deposits billed", money: money(progress.depositsBilled, currency: "USD")).cardRow()
                                        PaperDetailRow("Not yet applied", money: money(progress.depositOutstanding, currency: "USD")).cardRow()
                                    }
                                    if progress.retainedToDate > 0 {
                                        PaperDetailRow("Retained", money: money(progress.retainedToDate, currency: "USD")).cardRow()
                                        PaperDetailRow("Releasable now", money: money(progress.retainageOutstanding, currency: "USD")).cardRow()
                                    }
                                }
                                .padding(.vertical, PaperCardMetrics.edge)
                            }
                        }
                        PaperSection("Schedule of values", count: progress.schedule.lines.count) {
                            VStack(spacing: 0) {
                                ForEach(progress.schedule.lines.sorted { $0.position < $1.position }) { line in
                                    let lineProgress = progress.lines.first { $0.lineId == line.id }
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(line.description).font(Theme.font(16, weight: .medium))
                                            Spacer(minLength: 8)
                                            Text(money(line.scheduledAmount.amount, currency: "USD")).moneyStyle(.row)
                                        }
                                        if let lineProgress {
                                            ProgressView(value: Double(lineProgress.billedToDate), total: Double(max(line.scheduledAmount.amount, 1)))
                                                .tint(Theme.foreground)
                                            Text("\(money(lineProgress.billedToDate, currency: "USD"))\u{00A0}billed · \(money(lineProgress.remaining, currency: "USD"))\u{00A0}left")
                                                .font(Theme.font(15)).monospacedDigit().foregroundStyle(Theme.muted)
                                        }
                                    }
                                    .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
                                    .accessibilityElement(children: .combine)
                                }
                            }
                            .padding(.vertical, PaperCardMetrics.edge)
                        }
                    }
                    .padding(.horizontal, PaperCardMetrics.margin - Theme.gutter)
                    if let createdInvoiceID {
                        NavigationLink { InvoiceDetailView(id: createdInvoiceID).thorbisBackButton() } label: {
                            PaperMenuRow("Open the new draft invoice", symbol: "doc.plaintext")
                        }
                        .buttonStyle(.plain).padding(.top, 8)
                    }
                    if progress.retainageOutstanding > 0, canBill {
                        Button("Release retainage · \(money(progress.retainageOutstanding, currency: "USD"))") { confirm = "release-retainage" }
                            .font(Theme.font(15, weight: .medium)).monospacedDigit().foregroundStyle(Theme.foreground)
                            .frame(minHeight: 44).padding(.top, 8).disabled(busy)
                    }
                } else if error == nil {
                    SkeletonRows(count: 4, leading: false, inset: 0)
                }
                if let error { ErrorBanner(message: error).padding(.horizontal, -Theme.gutter).padding(.top, 8) }
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 4).padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let progress, progress.schedule.status == "open", progress.remaining > 0, canBill {
                PaperActionBar(title: "Bill the remainder · \(money(progress.remaining, currency: "USD"))", symbol: "doc.badge.plus", busy: busy) {
                    confirm = "bill-remainder"
                }
            }
        }
        .thorbisConfirm(pendingConfirm == "release-retainage" ? "Release the withheld retainage as a draft invoice?" : "Bill every remaining line as a final draft invoice?",
                        isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                        actions: [ThorbisConfirmAction(pendingConfirm == "release-retainage" ? "Release retainage" : "Bill the remainder") {
            if let command = pendingConfirm { Task { await run(command) } }
        }])
        .refreshable { await load() }
        .task { await load() }
    }

    private var canBill: Bool { session.can("invoice.create", feature: "progress_billing") }

    private func load() async {
        let generation = session.generation
        do {
            let loaded = try await api.billingSchedule(scheduleID)
            guard session.generation == generation else { return }
            progress = loaded
            error = nil
        } catch is CancellationError {} catch {
            guard session.generation == generation else { return }
            self.error = error.localizedDescription
        }
    }

    private func run(_ command: String) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let key = pendingKeys[command] ?? UUID().uuidString
        pendingKeys[command] = key
        do {
            let result = try await api.billingScheduleCommand(scheduleID, command, idempotencyKey: key)
            pendingKeys[command] = nil
            createdInvoiceID = result.invoice.id
            await load()
        } catch is CancellationError {} catch {
            // The key is kept: retrying after a timeout reuses it, so the server answers with the same invoice.
            self.error = error.localizedDescription
        }
    }
}

/// Paper 22 style deposit sheet on a job that came from an approved estimate.
struct JobDepositSheet: View {
    let jobID: String
    var onCreated: (InvoiceRecord) -> Void = { _ in }
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var key = UUID().uuidString
    @State private var busy = false
    @State private var error: String?
    /// What's missing in the amount, under the field (design.thorbis.com "Help under the field").
    @State private var amountError: String?

    private var cents: Int? { MoneyInput.cents(amount).flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Request a deposit").font(Theme.font(24, weight: .medium)).tracking(-0.36)
                Text("Creates a deposit invoice from the job's approved estimate. It's credited against later bills.")
                    .font(Theme.font(14)).foregroundStyle(Theme.muted)
                VStack(alignment: .leading, spacing: 6) {
                    // The affix lives inside the well (design.thorbis.com "Affixes in the well").
                    HStack(spacing: 8) {
                        Text("$").font(Theme.monoFont(28)).foregroundStyle(Theme.muted)
                        TextField("150.00", text: $amount).keyboardType(.decimalPad).font(Theme.monoFont(28))
                            .onChange(of: amount) { _, _ in key = UUID().uuidString; amountError = nil }
                            .accessibilityLabel("Deposit amount")
                    }
                    .fieldWell()
                    if let amountError { FieldProblem(message: amountError) }
                }
                if let error { ErrorBanner(message: error).padding(.horizontal, -Theme.gutter) }
                Spacer()
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 8)
            .foregroundStyle(Theme.foreground)
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ThorbisToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
            .safeAreaInset(edge: .bottom) {
                // Never pre-disabled: pressing it with no amount says what's missing under the field.
                PaperActionBar(title: cents.map { "Create \(money($0, currency: "USD")) deposit invoice" } ?? "Create deposit invoice",
                               symbol: "banknote", busy: busy) { Task { await create() } }
            }
            .interactiveDismissDisabled(busy)
        }
        .presentationDetents([.medium])
    }

    private func create() async {
        guard !busy else { return }
        guard let cents else { amountError = "Add the deposit amount, like 150.00."; return }
        busy = true
        defer { busy = false }
        do {
            let result = try await api.requestJobDeposit(jobID: jobID, amountCents: cents, idempotencyKey: key)
            onCreated(result.invoice)
            dismiss()
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}
