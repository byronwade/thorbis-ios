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
            // v2 List room, as on Invoices and Estimates: the header, a 13 Medium label per status,
            // then plain rows on the canvas with the amount over the status word.
            LazyVStack(alignment: .leading, spacing: 0) {
                PaperHeader(title: "Billing", subtitle: "Progress billing and deposits by job")
                    .environment(\.paperMenuButton, false)
                if let error { ErrorBanner(message: error) { await load() } }
                if loading && schedules.isEmpty { ListRoomSkeleton(count: 4, threeLines: false) }
                let groups = paperDocumentGroups(schedules, status: \.status, order: ["open", "closed"])
                ForEach(Array(groups.enumerated()), id: \.element.0) { index, pair in
                    ListGroupLabel(title: pair.0 == "open" ? "Open" : "Closed", count: pair.1.count, first: index == 0)
                    ForEach(pair.1) { schedule in
                        NavigationLink(value: PaperRoute.billingSchedule(schedule.id)) {
                            MoneyListRow(title: store.customerName(schedule.customerId),
                                         subtitle: "SOV-\(schedule.id.suffix(4).uppercased())\(schedule.retainageRateBps > 0 ? " · \(schedule.retainageRateBps / 100)% retainage" : "")",
                                         status: schedule.status == "open" ? DocumentStatus(tone: .scheduled, word: "Open")
                                                                           : DocumentStatus(tone: .done, word: "Closed"),
                                         amount: money(schedule.total, currency: "USD"))
                        }
                        .buttonStyle(RowPressStyle())
                    }
                }
                if !loading && schedules.isEmpty && error == nil {
                    ListRoomEmpty(title: "No billing schedules.",
                                  message: "A schedule starts when a job is billed in stages or takes a deposit.")
                }
            }
            .environment(\.paperRowInset, ListRoom.gutter)
            .padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.canvas)
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
                    // Paper 89A: "Billing schedule" at 34 Bold, the job and its total in 15 muted under
                    // it, the progress card, then the stages on one card. The schedule's number and
                    // whether it is open stay as one quiet word under the subtitle.
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Billing schedule").font(Theme.font(34, weight: .bold)).tracking(-0.85)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        // The schedule's number and whether it is open ride the same quiet line.
                        Text("\(scheduleName(progress.schedule)) \u{00B7} \(money(progress.schedule.total, currency: "USD")) \u{00B7} SOV-\(progress.schedule.id.suffix(4).uppercased())\(progress.schedule.status == "open" ? "" : " \u{00B7} Closed")")
                            .font(Theme.font(15)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 14).padding(.bottom, 20)
                    VStack(alignment: .leading, spacing: 20) {
                        billedCard(progress)
                        PaperSection("Stages") {
                            VStack(spacing: 0) {
                                let lines = progress.schedule.lines.sorted { $0.position < $1.position }
                                ForEach(lines) { line in
                                    stageRow(line, progress: progress, divider: line.id != lines.first?.id)
                                }
                            }
                        }
                        // Paper 89A shows the progress and the stages; what was taken up front or held back
                        // follows them.
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
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let progress, progress.schedule.status == "open", progress.remaining > 0, canBill {
                PaperActionBar(title: "Bill \(money(progress.remaining, currency: "USD")) now", busy: busy) {
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

    /// The job's title when this phone has the job; otherwise who the schedule is for.
    private func scheduleName(_ schedule: BillingSchedule) -> String {
        store.jobs.first { $0.id == schedule.jobId }?.title ?? store.customerName(schedule.customerId)
    }

    /// A Paper 89A stage: the name and its share of the total in 16 Medium over the amount in 14
    /// muted, and where it stands as a word at the trailing edge. A hairline above every row but the first.
    private func stageRow(_ line: BillingSchedule.Line, progress: BillingScheduleProgress, divider: Bool) -> some View {
        let lineProgress = progress.lines.first { $0.lineId == line.id }
        let amount = line.scheduledAmount.amount
        let total = progress.schedule.total
        let share = total > 0 ? " \u{00B7} \(Int((Double(amount) / Double(total) * 100).rounded()))%" : ""
        let billed = lineProgress?.billedToDate ?? 0
        let remaining = lineProgress?.remaining ?? amount
        let partly = billed > 0 && remaining > 0
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(line.description)\(share)")
                    .font(Theme.font(16, weight: .medium)).monospacedDigit().foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(partly ? "\(money(amount, currency: "USD")) \u{00B7} \(money(billed, currency: "USD"))\u{00A0}billed"
                            : money(amount, currency: "USD"))
                    .font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            stageWord(billed: billed, remaining: remaining, known: lineProgress != nil)
        }
        .padding(.vertical, 14)
        .padding(.trailing, PaperCardMetrics.inset)
        .overlay(alignment: .top) {
            if divider { WellDivider(leading: 0) }
        }
        .padding(.leading, PaperCardMetrics.inset)
        .accessibilityElement(children: .combine)
    }

    /// Billed in the success colour, what's left of a part-billed stage, or "Not yet": 15 at the
    /// row's trailing edge. The server says what was billed, not what was paid, so the word is Billed.
    @ViewBuilder private func stageWord(billed: Int, remaining: Int, known: Bool) -> some View {
        if !known {
            EmptyView()
        } else if remaining <= 0 {
            Text("Billed").font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.success)
        } else if billed > 0 {
            Text("\(money(remaining, currency: "USD"))\u{00A0}left")
                .font(Theme.font(15)).monospacedDigit().foregroundStyle(Theme.muted)
        } else {
            Text("Not yet").font(Theme.font(15)).foregroundStyle(Theme.muted)
        }
    }

    /// Paper 89A's progress card: "$1,455.00 of $4,850.00 billed", the percent, and a brand bar.
    private func billedCard(_ progress: BillingScheduleProgress) -> some View {
        let total = progress.billedToDate + progress.remaining
        let fraction = total > 0 ? min(1, max(0, Double(progress.billedToDate) / Double(total))) : 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(money(progress.billedToDate, currency: "USD")) of \(money(total, currency: "USD")) billed")
                    .font(Theme.font(16, weight: .medium)).monospacedDigit().foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text("\(Int((fraction * 100).rounded()))%").font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.fill)
                    Capsule().fill(Theme.brand).frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 16).padding(.vertical, 16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(money(progress.billedToDate, currency: "USD")) billed, \(money(progress.remaining, currency: "USD")) remaining")
    }

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
    /// The approved estimate's total in cents (USD), when the job screen has it loaded. With it the
    /// sheet offers Paper 89's 25% and 50% chips and the balance left on completion; without it the
    /// amount is typed, as before.
    var estimateTotalCents: Int? = nil
    /// Paper 89's second line ("EST-1042 · Danielle Marlowe"); the job's number when not given.
    var subtitle: String? = nil
    var onCreated: (InvoiceRecord) -> Void = { _ in }
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var key = UUID().uuidString
    @State private var busy = false
    @State private var error: String?
    /// What's missing in the amount, under the field (design.thorbis.com "Help under the field").
    @State private var amountError: String?
    @FocusState private var amountFocused: Bool

    private var cents: Int? { MoneyInput.cents(amount).flatMap { $0 > 0 ? $0 : nil } }

    /// The estimate's total, only when a share of it is a real amount.
    private var estimateTotal: Int? { estimateTotalCents.flatMap { $0 > 0 ? $0 : nil } }

    /// A share of the estimate, rounded to the cent.
    private func share(_ percent: Int) -> Int? {
        guard let total = estimateTotal else { return nil }
        let (product, overflow) = total.multipliedReportingOverflow(by: percent)
        guard !overflow else { return nil }
        let part = (product + 50) / 100
        return part > 0 ? part : nil
    }

    var body: some View {
        NavigationStack {
            // Paper 89: "Request a deposit" at 34 Bold with what it is for under it, the amount at
            // 52 Bold centred on the canvas over the 25%, 50% and Custom chips, the estimate's
            // arithmetic in one card, then what happens to it in 13 muted above the commit.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Request a deposit").font(Theme.font(34, weight: .bold)).tracking(-0.85)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text(subtitle ?? "JOB-\(jobID.suffix(4).uppercased())").font(Theme.font(15)).monospacedDigit()
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Theme.gutter).padding(.top, 14)
                    VStack(spacing: 16) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("$").font(Theme.paymentAmountFont()).tracking(Theme.paymentAmountTracking)
                                .foregroundStyle(Theme.muted)
                                .accessibilityHidden(true)
                            TextField("150.00", text: $amount, prompt: .placeholder("150.00")).keyboardType(.decimalPad)
                                .font(Theme.paymentAmountFont())
                                .fixedSize()
                                .focused($amountFocused)
                                .onChange(of: amount) { _, _ in key = UUID().uuidString; amountError = nil }
                                .accessibilityLabel("Deposit amount")
                        }
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        if estimateTotal != nil { shareChips }
                        if let amountError { FieldProblem(message: amountError) }
                    }
                    .padding(.horizontal, Theme.gutter).padding(.top, 32)
                    if let total = estimateTotal { arithmeticCard(total).padding(.horizontal, 16).padding(.top, 28) }
                    if let error { ErrorBanner(message: error).padding(.top, 12) }
                }
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .foregroundStyle(Theme.foreground)
            .background(Theme.canvas)
            .paperPageGround()
            .navigationBarTitleDisplayMode(.inline)
            // Paper 89: the 44 back circle on the card tone at top left closes the sheet.
            .toolbar {
                ThorbisToolbarItem(placement: .topBarLeading) {
                    PaperCircleButton(symbol: "chevron.left", label: "Cancel", size: 44, fill: Theme.card) { dismiss() }
                        .disabled(busy)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 2) {
                    Text("The deposit is taken off the final invoice.")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, Theme.gutter)
                    // Never pre-disabled: pressing it with no amount says what's missing under the field.
                    PaperActionBar(title: cents.map { "Request \(money($0, currency: "USD")) deposit" } ?? "Request deposit",
                                   busy: busy) { Task { await create() } }
                }
                .background(Theme.canvas)
            }
            .interactiveDismissDisabled(busy)
        }
        .presentationDetents(estimateTotal == nil ? [.medium] : [.large])
    }

    /// Paper 89: 25%, 50% and Custom as 40pt pills (44pt targets). The one in use sits on the
    /// brand surface in brand text; a share fills the amount, Custom puts the cursor in it.
    private var shareChips: some View {
        let quarter = share(25)
        let half = share(50)
        let custom = cents == nil || (cents != quarter && cents != half)
        return HStack(spacing: 8) {
            if let quarter { shareChip("25%", spoken: "25 percent of the estimate", isOn: cents == quarter) { choose(quarter) } }
            if let half { shareChip("50%", spoken: "50 percent of the estimate", isOn: cents == half) { choose(half) } }
            shareChip("Custom", spoken: "Custom amount", isOn: custom) { amountFocused = true }
        }
    }

    private func choose(_ cents: Int) {
        amountFocused = false
        amount = paymentAmountText(cents)
    }

    private func shareChip(_ title: String, spoken: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.font(14, weight: .semibold)).monospacedDigit()
                .foregroundStyle(isOn ? Theme.brandText : Theme.foreground)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .background(isOn ? Theme.brandSurface : Theme.fill, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(busy)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("deposit-share-\(title.lowercased().replacingOccurrences(of: "%", with: ""))")
    }

    /// Paper 89's card: the estimate's total, the deposit, a hairline, then what is left on
    /// completion at 22 Bold. The last two rows wait for an amount that fits inside the total.
    private func arithmeticCard(_ total: Int) -> some View {
        let deposit = cents.flatMap { $0 <= total ? $0 : nil }
        return VStack(alignment: .leading, spacing: 8) {
            arithmeticRow("Estimate total", money(total, currency: "USD"))
            arithmeticRow("Deposit", deposit.map { money($0, currency: "USD") } ?? "\u{2014}")
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Balance on completion").font(Theme.font(16, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(deposit.map { money(total - $0, currency: "USD") } ?? "\u{2014}")
                    .font(Theme.font(22, weight: .bold)).tracking(-0.44).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.top, 8)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            .accessibilityElement(children: .combine)
        }
        .foregroundStyle(Theme.foreground)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func arithmeticRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(Theme.font(15)).foregroundStyle(Theme.muted)
            Spacer(minLength: 8)
            Text(value).font(Theme.font(15)).monospacedDigit().foregroundStyle(Theme.foreground)
        }
        .accessibilityElement(children: .combine)
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
