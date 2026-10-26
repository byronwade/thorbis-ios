import SwiftUI
import ThorbisCore

/// Estimates and invoices for real-world service work. No Thorbis plan purchase,
/// pricing or external checkout exists in this binary (ADR-0018, apps/mobile AGENTS.md).
struct MoneyView: View {
    @Environment(AppModel.self) private var model
    @SceneStorage("thorbis.money.kind") private var kind: Kind = .estimates

    enum Kind: String, CaseIterable, Identifiable {
        case estimates, invoices
        var id: String { rawValue }
        var title: String { self == .estimates ? "Estimates" : "Invoices" }
    }

    /// Outstanding totals per currency; amounts in different currencies are never added together.
    private var openBalances: [(currency: String, cents: Int)] {
        let issued = model.invoices.filter { $0.status == .issued && $0.balance > 0 }
        return Dictionary(grouping: issued, by: \.currency)
            .map { (currency: $0.key, cents: $0.value.reduce(0) { $0 + $1.balance }) }
            .sorted { $0.currency < $1.currency }
    }

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("money-kind")
            }
            if let error = model.refreshError {
                InlineError(message: error) { await model.refreshAll() }.sheetRow()
            }
            switch kind {
            case .estimates: estimates
            case .invoices: invoices
            }
        }
        .thorbisList()
        .navigationTitle("Money")
        .refreshable { await model.refreshAll() }
        .toolbar { AccountToolbarItem() }
    }

    @ViewBuilder
    private var estimates: some View {
        if model.estimates.isEmpty {
            Text(model.isRefreshing ? "Loading…" : "No estimates yet.").foregroundStyle(Theme.inkSecondary).sheetRow()
        }
        estimateSection("Drafts", .draft)
        estimateSection("Waiting on customer", .sent)
        estimateSection("Approved", .approved)
        estimateSection("Declined", .declined)
    }

    @ViewBuilder
    private func estimateSection(_ title: String, _ status: EstimateStatus) -> some View {
        let items = model.estimates.filter { $0.status == status }
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { estimate in
                    NavigationLink(value: Route.estimate(estimate.id)) { EstimateRow(estimate: estimate) }.sheetRow()
                }
            }
        }
    }

    @ViewBuilder
    private var invoices: some View {
        if !openBalances.isEmpty {
            Section {
                ForEach(openBalances, id: \.currency) { balance in
                    LabeledContent(openBalances.count > 1 ? "Open balance (\(balance.currency))" : "Open balance") {
                        MoneyText(cents: balance.cents, currency: balance.currency)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(Theme.ink)
                    }
                    .sheetRow()
                }
            }
        }
        if model.invoices.isEmpty {
            Text(model.isRefreshing ? "Loading…" : "No invoices yet.").foregroundStyle(Theme.inkSecondary).sheetRow()
        }
        invoiceSection("Drafts", .draft)
        invoiceSection("Issued", .issued)
        invoiceSection("Paid", .paid)
        invoiceSection("Void", .void)
    }

    @ViewBuilder
    private func invoiceSection(_ title: String, _ status: InvoiceStatus) -> some View {
        let items = model.invoices.filter { $0.status == status }
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { invoice in
                    NavigationLink(value: Route.invoice(invoice.id)) { InvoiceRow(invoice: invoice) }.sheetRow()
                }
            }
        }
    }
}

struct EstimateRow: View {
    @Environment(AppModel.self) private var model
    let estimate: Estimate

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(estimate.title).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                Text("\(estimate.reference) · \(model.customerName(estimate.customerId))")
                    .font(.subheadline).foregroundStyle(Theme.inkSecondary).lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s)
            VStack(alignment: .trailing, spacing: 2) {
                MoneyText(cents: estimate.total).font(.body).foregroundStyle(Theme.ink)
                StatusBadge(estimate.status)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct InvoiceRow: View {
    @Environment(AppModel.self) private var model
    let invoice: Invoice

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.customerName(invoice.customerId)).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                Text(invoice.reference).font(.subheadline.monospaced()).foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: Theme.Space.s)
            VStack(alignment: .trailing, spacing: 2) {
                MoneyText(cents: invoice.status == .issued ? invoice.balance : invoice.total, currency: invoice.currency)
                    .font(.body).foregroundStyle(Theme.ink)
                StatusBadge(invoice.status)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Line items with tabular money, then the total.
struct LinesSection: View {
    let lines: [DocumentLine]
    let currency: String

    var body: some View {
        Section("Line items") {
            ForEach(lines) { line in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.description).foregroundStyle(Theme.ink)
                        if line.quantity != 1 {
                            HStack(spacing: 4) {
                                Text("\(line.quantity) ×")
                                MoneyText(cents: line.unitPrice.amount, currency: currency)
                            }
                            .font(.subheadline).foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    Spacer()
                    MoneyText(cents: line.total, currency: currency).foregroundStyle(Theme.ink)
                }
                .sheetRow()
            }
        }
    }
}

struct EstimateDetailView: View {
    @Environment(AppModel.self) private var model
    let estimateId: String
    @State private var estimate: Estimate?
    @State private var error: String?
    @State private var busy: String?
    @State private var confirmingDecline = false
    @State private var succeeded = 0

    private var current: Estimate? { estimate ?? model.estimates.first { $0.id == estimateId } }

    var body: some View {
        Group {
            if let estimate = current {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            StatusBadge(estimate.status)
                            Text(estimate.title).font(.title2.weight(.medium)).foregroundStyle(Theme.ink)
                            NavigationLink(value: Route.customer(estimate.customerId)) {
                                Text(model.customerName(estimate.customerId)).foregroundStyle(Theme.inkSecondary)
                            }
                        }
                        .sheetRow()
                        actions(estimate)
                    }
                    if let error { Section { InlineError(message: error).sheetRow() } }
                    LinesSection(lines: estimate.lines, currency: "USD")
                    Section {
                        LabeledContent("Total") { MoneyText(cents: estimate.total).font(.headline.weight(.medium)) }.sheetRow()
                    }
                    if let options = estimate.options, !options.isEmpty {
                        Section("Options") {
                            ForEach(options) { option in
                                LabeledContent(option.title) { MoneyText(cents: option.totalAmount) }.sheetRow()
                            }
                        }
                    }
                    Section("History") {
                        if let at = Timestamp.parse(estimate.sentAt) { DetailRow(label: "Sent", value: Format.relative(at)).sheetRow() }
                        if let at = Timestamp.parse(estimate.approvedAt) { DetailRow(label: "Approved", value: Format.relative(at)).sheetRow() }
                        if let at = Timestamp.parse(estimate.declinedAt) { DetailRow(label: "Declined", value: Format.relative(at)).sheetRow() }
                        DetailRow(label: "Created", value: Format.relative(Timestamp.parse(estimate.createdAt))).sheetRow()
                    }
                }
                .thorbisList()
            } else if let error {
                ContentUnavailableView("Couldn't open this estimate", systemImage: "doc.text", description: Text(error))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.canvas)
        .navigationTitle(current?.reference ?? "Estimate")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: estimateId) { await load() }
        .refreshable { await load() }
        .sensoryFeedback(.success, trigger: succeeded)
        .confirmationDialog("Mark this estimate declined?", isPresented: $confirmingDecline, titleVisibility: .visible) {
            Button("Decline estimate", role: .destructive) { run("decline") }
            Button("Keep estimate", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func actions(_ estimate: Estimate) -> some View {
        switch estimate.status {
        case .draft:
            CommitButton(title: "Send to customer", symbol: "paperplane", busy: busy == "send") { run("send") }.sheetRow()
        case .sent:
            VStack(spacing: Theme.Space.m) {
                CommitButton(title: "Customer approved", symbol: "checkmark.seal", busy: busy == "approve") { run("approve") }
                Button("Customer declined") { confirmingDecline = true }.buttonStyle(.rim)
            }
            .sheetRow()
        default:
            EmptyView()
        }
    }

    private func run(_ action: String) {
        guard let estimate = current else { return }
        busy = action
        error = nil
        Task {
            defer { busy = nil }
            do {
                let updated: Estimate
                switch action {
                case "send": updated = try await model.api.sendEstimate(estimate)
                case "approve": updated = try await model.api.approveEstimate(estimate)
                default: updated = try await model.api.declineEstimate(estimate)
                }
                self.estimate = updated
                model.store(updated)
                succeeded += 1
            } catch {
                self.error = model.message(for: error)
                if (error as? APIError)?.isConflict == true { await load() }
            }
        }
    }

    private func load() async {
        do {
            let fresh = try await model.api.estimate(estimateId)
            estimate = fresh
            model.store(fresh)
        } catch {
            self.error = model.message(for: error)
        }
    }
}

struct InvoiceDetailView: View {
    @Environment(AppModel.self) private var model
    let invoiceId: String
    @State private var invoice: Invoice?
    @State private var payments: [Payment] = []
    @State private var error: String?
    @State private var issuing = false
    @State private var confirmingIssue = false

    private var current: Invoice? { invoice ?? model.invoices.first { $0.id == invoiceId } }

    var body: some View {
        Group {
            if let invoice = current {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            StatusBadge(invoice.status)
                            NavigationLink(value: Route.customer(invoice.customerId)) {
                                Text(model.customerName(invoice.customerId)).font(.title2.weight(.medium)).foregroundStyle(Theme.ink)
                            }
                            if let jobId = invoice.jobId {
                                NavigationLink(value: Route.job(jobId)) {
                                    Text(model.cached(job: jobId)?.title ?? "View job").foregroundStyle(Theme.inkSecondary)
                                }
                            }
                        }
                        .sheetRow()
                        if invoice.status == .draft {
                            CommitButton(title: "Issue invoice", symbol: "paperplane", busy: issuing) { confirmingIssue = true }.sheetRow()
                        }
                    }
                    if let error { Section { InlineError(message: error).sheetRow() } }
                    LinesSection(lines: invoice.lines, currency: invoice.currency)
                    Section {
                        LabeledContent("Total") { MoneyText(cents: invoice.total, currency: invoice.currency) }.sheetRow()
                        LabeledContent("Paid") { MoneyText(cents: invoice.amountPaid, currency: invoice.currency) }.sheetRow()
                        LabeledContent("Balance") {
                            MoneyText(cents: invoice.balance, currency: invoice.currency).font(.headline.weight(.medium))
                        }
                        .sheetRow()
                    }
                    if !payments.isEmpty {
                        Section("Payments") {
                            ForEach(payments) { payment in
                                LabeledContent {
                                    MoneyText(cents: payment.amount.amount, currency: payment.amount.currency)
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(payment.method.capitalized)
                                        Text(Format.relative(Timestamp.parse(payment.recordedAt))).font(.footnote).foregroundStyle(Theme.inkQuiet)
                                    }
                                }
                                .sheetRow()
                            }
                        }
                    }
                }
                .thorbisList()
            } else if let error {
                ContentUnavailableView("Couldn't open this invoice", systemImage: "doc.text", description: Text(error))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.canvas)
        .navigationTitle(current?.reference ?? "Invoice")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: invoiceId) { await load() }
        .refreshable { await load() }
        .confirmationDialog("Issue this invoice?", isPresented: $confirmingIssue, titleVisibility: .visible) {
            Button("Issue invoice") { issue() }
            Button("Not yet", role: .cancel) {}
        } message: {
            Text("Issued invoices are locked. Line items can't change afterwards.")
        }
    }

    private func issue() {
        guard let invoice = current else { return }
        issuing = true
        error = nil
        Task {
            defer { issuing = false }
            do {
                let updated = try await model.api.issueInvoice(invoice)
                self.invoice = updated
                model.store(updated)
            } catch {
                self.error = model.message(for: error)
                if (error as? APIError)?.isConflict == true { await load() }
            }
        }
    }

    private func load() async {
        do {
            let fresh = try await model.api.invoice(invoiceId)
            invoice = fresh
            model.store(fresh)
            payments = (try? await model.api.payments(invoice: invoiceId)) ?? []
        } catch {
            self.error = model.message(for: error)
        }
    }
}
