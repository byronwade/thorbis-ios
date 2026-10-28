import SwiftUI

struct WorkspaceNoticesView: View {
    @ObservedObject var api: APIClient
    let available: Bool

    @State private var items: [StaffNotice] = []
    @State private var nextCursor: String?
    @State private var readCursor: String?
    @State private var unreadState: StaffUnreadState = .unknown
    @State private var loading = false
    @State private var error: String?

    @State private var filter = "All"

    private var visible: [StaffNotice] { filter == "Unread" ? items.filter { !$0.read } : items }

    /// Paper 77: large title, All/Unread, unread dot, quiet rows.
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Inbox").font(Theme.font(34, weight: .bold)).tracking(-0.68).accessibilityAddTraits(.isHeader)
                    Text(subtitle).font(Theme.font(15)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, Theme.gutter).padding(.bottom, 12)
                if !available {
                    PaperEmptyState(symbol: "bell.slash", title: "Inbox unavailable", message: "This account cannot view job notices.")
                } else {
                    PaperTabs(options: ["All", "Unread"], selection: $filter)
                    if let error { ErrorBanner(message: error) }
                    ForEach(visible) { notice in
                        HStack(alignment: .top, spacing: 12) {
                            Circle().fill(notice.read ? Color.clear : Theme.brand).frame(width: 7, height: 7).padding(.top, 7)
                                .accessibilityHidden(true)
                            Image(systemName: "bell").font(.system(size: 14)).foregroundStyle(notice.read ? Theme.muted : Theme.brandText)
                                .frame(width: 32, height: 32).background(notice.read ? Theme.fill : Theme.brandSurface, in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(notice.title).font(Theme.font(15, weight: notice.read ? .regular : .semibold))
                                    .foregroundStyle(notice.read ? Theme.muted : Theme.foreground)
                                Text([notice.meta, timeLabel(notice.at)].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(Theme.font(13)).foregroundStyle(Theme.muted).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Theme.gutter).padding(.vertical, 10)
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(notice.read ? "" : "Unread")
                    }
                    if nextCursor != nil {
                        Button("Load more") { Task { await loadMore() } }
                            .font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.brandText)
                            .frame(maxWidth: .infinity, minHeight: 44).disabled(loading)
                    }
                    if visible.isEmpty && !loading && error == nil {
                        PaperEmptyState(symbol: "tray", title: filter == "Unread" ? "All caught up" : "No notices yet",
                                        message: "Assignments and job changes for you land here.")
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if available && (unreadState == .present || readCursor != nil) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await markReadBatch() } } label: { Image(systemName: "checkmark.circle") }
                        .accessibilityLabel(readCursor == nil ? "Mark all read" : "Continue marking read")
                        .disabled(loading)
                }
            }
        }
        .refreshable { await refresh() }
        .task { await refresh() }
    }

    private var subtitle: String {
        if !available { return "Job notices" }
        switch unreadState {
        case .present: return "Unread notices waiting"
        case .unknown: return loading ? "Checking for new notices…" : "Job notices"
        default: return "All caught up"
        }
    }

    private func timeLabel(_ raw: String) -> String {
        guard let date = JobFiltering.date(raw) else { return raw }
        return date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }

    private func refresh() async {
        guard available, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await api.staffNotices()
            items = page.items
            nextCursor = page.nextCursor
            unreadState = page.unreadState
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func loadMore() async {
        guard available, !loading, let cursor = nextCursor else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await api.staffNotices(cursor: cursor)
            guard page.nextCursor != cursor else {
                throw Problem(title: "Notice pagination stopped", status: nil, detail: "The server repeated its cursor.")
            }
            items.append(contentsOf: page.items)
            nextCursor = page.nextCursor
            unreadState = page.unreadState
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func markReadBatch() async {
        guard available, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let result = try await api.markStaffNoticesRead(cursor: readCursor)
            guard result.nextCursor != readCursor || result.nextCursor == nil else {
                throw Problem(title: "Notice acknowledgement stopped", status: nil, detail: "The server repeated its cursor.")
            }
            readCursor = result.nextCursor
            let page = try await api.staffNotices()
            items = page.items
            nextCursor = page.nextCursor
            unreadState = page.unreadState
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct WorkspaceRevenueView: View {
    @ObservedObject var api: APIClient
    let available: Bool

    @State private var report: RevenueReport?
    @State private var error: String?

    /// Paper 59/60: the month's number large, receivables beside it, six months as bars.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Money").font(Theme.font(34, weight: .bold)).tracking(-0.68).accessibilityAddTraits(.isHeader)
                    Text("Revenue and receivables · live").font(Theme.font(15)).foregroundStyle(Theme.muted)
                }
                .padding(.bottom, 16)
                if !available {
                    PaperEmptyState(symbol: "chart.bar.xaxis", title: "Money unavailable", message: "This account cannot view invoice and payment reports.")
                } else if let error {
                    ErrorBanner(message: error).padding(.horizontal, -Theme.gutter)
                } else if let report {
                    if report.truncated {
                        PaperEmptyState(symbol: "exclamationmark.triangle", title: "Report incomplete",
                                        message: "The server reached its scan limit, so these totals would understate the ledger. Open the full report on the web.")
                    } else {
                        content(report)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    @ViewBuilder private func content(_ report: RevenueReport) -> some View {
        let months = Array(report.months.suffix(6))
        let current = months.last
        let previous = months.dropLast().last
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Collected · \(current.map { monthName($0.month, long: true) } ?? "this month")")
                    .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(money(current?.collected ?? 0, currency: "USD"))
                    .font(Theme.monoFont(34, weight: .semibold)).minimumScaleFactor(0.6).lineLimit(1)
                if let current, let previous, previous.collected > 0 {
                    let change = Double(current.collected - previous.collected) / Double(previous.collected) * 100
                    Label("\(abs(Int(change.rounded())))% vs \(monthName(previous.month, long: false))", systemImage: change >= 0 ? "arrow.up" : "arrow.down")
                        .font(Theme.font(12, weight: .medium))
                        .foregroundStyle(change >= 0 ? Theme.success : Theme.destructive)
                }
            }
            bars(months)
                .padding(.top, 8)
        }
        .padding(.bottom, 18)

        // The tiles open the invoices behind the numbers, so nobody has to go looking for them.
        NavigationLink(value: PaperRoute.invoices) {
        HStack(spacing: 10) {
            tile("Outstanding", money(report.receivable.balance, currency: "USD"),
                 detail: "\(report.receivable.openInvoices) open invoice\(report.receivable.openInvoices == 1 ? "" : "s")", alert: nil)
            tile("Overdue", money(report.receivable.overdueBalance, currency: "USD"),
                 detail: "\(report.receivable.overdueInvoices) invoice\(report.receivable.overdueInvoices == 1 ? "" : "s")",
                 alert: report.receivable.overdueInvoices > 0 ? Theme.destructive : nil)
        }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens invoices")
        .padding(.bottom, 18)

        PaperGroupHeader(title: "By month", count: months.count)
        ForEach(months.reversed()) { month in
            HStack {
                Text(monthName(month.month, long: true)).font(Theme.font(15, weight: .medium))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(money(month.collected, currency: "USD")).font(Theme.monoFont(13, weight: .semibold))
                    Text("Invoiced \(money(month.revenue, currency: "USD"))").font(Theme.font(12)).foregroundStyle(Theme.muted)
                }
            }
            .frame(minHeight: 48)
            .accessibilityElement(children: .combine)
        }
    }

    private func bars(_ months: [RevenueReport.Month]) -> some View {
        let peak = max(months.map(\.collected).max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(months.enumerated()), id: \.element.id) { index, month in
                VStack(spacing: 6) {
                    Capsule()
                        .fill(index == months.count - 1 ? Theme.brand : Theme.muted.opacity(0.45))
                        .frame(width: 6, height: max(4, 44 * CGFloat(month.collected) / CGFloat(peak)))
                    Text(monthName(month.month, long: false).uppercased()).font(Theme.monoFont(12, weight: .medium))
                        .lineLimit(1).minimumScaleFactor(0.85)
                        .foregroundStyle(index == months.count - 1 ? Theme.foreground : Theme.muted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 70, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Collected by month: " + months.map { "\(monthName($0.month, long: true)) \(money($0.collected, currency: "USD"))" }.joined(separator: ", "))
    }

    private func tile(_ title: String, _ value: String, detail: String, alert: Color?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.font(13)).foregroundStyle(Theme.muted)
            Text(value).font(Theme.monoFont(19, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(detail).font(Theme.font(12, weight: alert == nil ? .regular : .medium)).foregroundStyle(alert ?? Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .accessibilityElement(children: .combine)
    }

    private func monthName(_ raw: String, long: Bool) -> String {
        let parts = raw.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]),
              let date = Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: .gmt, year: year, month: month, day: 15)) else { return raw }
        return long ? date.formatted(.dateTime.month(.wide).year()) : date.formatted(.dateTime.month(.abbreviated))
    }

    private func load() async {
        guard available else { return }
        do { report = try await api.revenueReport(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct WorkspacePriceBookView: View {
    @ObservedObject var api: APIClient
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    let canList: Bool
    let canViewDetail: Bool

    @State private var items: [PriceBookListItem] = []
    @State private var nextCursor: String?
    @State private var loading = false
    @State private var error: String?
    @State private var search = ""
    @State private var category = "All"
    @State private var creating = false
    /// pricebook.edit is the server's capability for Price Book changes; organization.settings.edit
    /// covers servers that predate it.
    private var canEdit: Bool {
        session.can("pricebook.edit", feature: "price_book") || session.can("organization.settings.edit", feature: "price_book")
    }

    private var categories: [String] {
        ["All"] + Array(Set(items.map { $0.kind.capitalized })).sorted()
    }

    private var visibleItems: [PriceBookListItem] {
        items.filter { item in
            (category == "All" || item.kind.capitalized == category) &&
            (search.isEmpty || item.description.localizedCaseInsensitiveContains(search) ||
             item.kind.localizedCaseInsensitiveContains(search) ||
             item.unit.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !canList {
                ContentUnavailableView("Price Book unavailable", systemImage: "book.closed",
                                       description: Text("This account cannot view Price Book items."))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Price book").font(Theme.font(34, weight: .bold)).tracking(-0.68).foregroundStyle(Theme.foreground)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(items.count) item\(items.count == 1 ? "" : "s")\(nextCursor == nil ? "" : " loaded")")
                        .font(Theme.font(15)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.gutter).padding(.bottom, 12)
                PaperSearchField(text: $search, prompt: "Search price book")
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(categories, id: \.self) { option in
                            Button { category = option } label: {
                                Text(option == "All" ? "All · \(items.count)" : option)
                                    .font(Theme.font(13, weight: category == option ? .semibold : .medium))
                                    .foregroundStyle(category == option ? Theme.foreground : Theme.muted)
                                    .padding(.horizontal, 14).padding(.vertical, 6)
                                    .background(category == option ? Theme.fill : .clear, in: Capsule())
                                    .frame(minHeight: 44)
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let error { ErrorBanner(message: error) }
                        if loading { ProgressView("Loading Price Book…") }
                        ForEach(categories.filter { $0 != "All" && (category == "All" || category == $0) }, id: \.self) { groupName in
                            let grouped = visibleItems.filter { $0.kind.capitalized == groupName }
                            if !grouped.isEmpty {
                                HStack(spacing: 8) {
                                    Text(groupName).font(Theme.font(13, weight: .medium))
                                    Text("\(grouped.count)").font(Theme.monoFont(12))
                                    Spacer()
                                }.foregroundStyle(Theme.muted)
                                VStack(spacing: 0) {
                                    ForEach(grouped) { item in
                                        if canViewDetail {
                                            NavigationLink {
                                                WorkspacePriceBookDetailView(api: api, id: item.id, canEdit: canEdit)
                                            } label: { row(item) }
                                            .buttonStyle(.plain)
                                        } else { row(item) }
                                    }
                                }
                            }
                        }
                        if nextCursor != nil {
                            Button("Load more items") { Task { await loadMore() } }
                                .font(Theme.font(14, weight: .medium))
                                .frame(maxWidth: .infinity).frame(minHeight: 44)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                                .disabled(loading)
                        }
                        if visibleItems.isEmpty && !loading && error == nil {
                            ContentUnavailableView(items.isEmpty ? "No Price Book items" : "No matching items",
                                systemImage: "book.closed")
                        }
                    }
                    .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 100)
                }
                .refreshable { await refresh() }
                .task { await refresh() }
                .toolbar {
                    if canEdit {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { creating = true } label: { Image(systemName: "plus") }.accessibilityLabel("New price book item")
                        }
                    }
                }
                .sheet(isPresented: $creating) { PriceBookItemEditor(api: api) { Task { await refresh() } } }
            }
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ item: PriceBookListItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.description).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                Text("\(item.kind.capitalized) · \(item.unit)")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                if item.archivedAt != nil { Text("Archived").font(Theme.font(11)).foregroundStyle(Theme.warning) }
            }
            Spacer(minLength: 6)
            Text(money(item.sellPrice.amount, currency: item.sellPrice.currency))
                .font(Theme.monoFont(13, weight: .medium)).foregroundStyle(Theme.foreground)
        }
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }

    private func refresh() async {
        guard canList, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await api.priceBookItems()
            items = page.items
            nextCursor = page.nextCursor
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func loadMore() async {
        guard canList, !loading, let cursor = nextCursor else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await api.priceBookItems(cursor: cursor)
            guard page.nextCursor != cursor else {
                throw Problem(title: "Price Book pagination stopped", status: nil, detail: "The server repeated its cursor.")
            }
            items.append(contentsOf: page.items)
            nextCursor = page.nextCursor
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

private struct WorkspacePriceBookDetailView: View {
    @ObservedObject var api: APIClient
    let id: String
    var canEdit = false
    @Environment(\.dismiss) private var dismiss
    @State private var detail: PriceBookDetail?
    @State private var error: String?
    @State private var editing = false
    @State private var confirmArchive = false

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(Theme.destructive) }
            if let detail {
                LabeledContent("Price", value: money(detail.revision.sellPrice.amount, currency: detail.revision.sellPrice.currency))
                LabeledContent("Unit", value: detail.revision.unit)
                LabeledContent("Kind", value: detail.revision.kind.capitalized)
                LabeledContent("Tax", value: detail.revision.taxClassification.replacingOccurrences(of: "_", with: " ").capitalized)
                if detail.item.status != "active" { LabeledContent("Status", value: detail.item.status.capitalized) }
                if canEdit && detail.item.status == "active" {
                    Section {
                        Button("Remove from price book", role: .destructive) { confirmArchive = true }
                    } footer: {
                        Text("Estimates and invoices that already use it keep their prices.")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(detail?.revision.description ?? "Price Book item")
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if canEdit, detail?.item.status == "active" {
                ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } }
            }
        }
        .sheet(isPresented: $editing) {
            if let detail {
                PriceBookItemEditor(api: api, existing: detail) { Task { await load() } }
            }
        }
        .confirmationDialog("Remove this item from the price book?", isPresented: $confirmArchive, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await archive() } }
        }
        .task { await load() }
    }

    private func load() async {
        do { detail = try await api.priceBookItem(id); error = nil }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }

    private func archive() async {
        guard let detail else { return }
        do {
            _ = try await api.archivePriceBookItem(id, expectedRevision: detail.item.currentRevision)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// Add or change a Price Book item. Prices are entered in dollars; a save writes a new revision,
/// so nothing already on an estimate or invoice changes.
struct PriceBookItemEditor: View {
    @ObservedObject var api: APIClient
    var existing: PriceBookDetail?
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var content = PriceBookContent(description: "", unit: "each", sellPrice: FieldMoney(amount: 0, currency: "USD"),
                                                  taxClassification: "taxable", kind: "service")
    @State private var priceText = ""
    @State private var busy = false
    @State private var error: String?
    @State private var createKey = UUID().uuidString

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name customers see", text: $content.description, axis: .vertical).lineLimit(1...3)
                    HStack {
                        Text("Price")
                        Spacer()
                        TextField("0.00", text: $priceText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .font(Theme.monoFont(15, weight: .medium))
                    }
                    TextField("Unit (each, hour, foot…)", text: $content.unit)
                }
                Section {
                    Picker("Kind", selection: $content.kind) {
                        ForEach(PriceBookContent.kinds, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    Picker("Tax", selection: $content.taxClassification) {
                        Text("Taxable").tag("taxable")
                        Text("Not taxable").tag("non_taxable")
                    }
                }
                if let error { Section { Text(error).foregroundStyle(Theme.destructive) } }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(existing == nil ? "New price book item" : "Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .topBarTrailing) { Button("Save") { Task { await save() } }.disabled(!valid || busy) }
            }
            .onAppear {
                guard let existing, content.description.isEmpty else { return }
                let r = existing.revision
                content = PriceBookContent(description: r.description, unit: r.unit, sellPrice: r.sellPrice,
                                           taxClassification: r.taxClassification, kind: r.kind)
                priceText = paymentAmountText(r.sellPrice.amount)
            }
        }
    }

    private var cents: Int? { MoneyInput.cents(priceText, maximumCents: 100_000_000) }
    private var valid: Bool {
        !content.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !content.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && cents != nil
    }

    private func save() async {
        guard let cents else { return }
        var body = content
        body.description = body.description.trimmingCharacters(in: .whitespacesAndNewlines)
        body.unit = body.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        body.sellPrice = FieldMoney(amount: cents, currency: "USD")
        busy = true
        defer { busy = false }
        do {
            if let existing {
                _ = try await api.revisePriceBookItem(existing.item.id, expectedRevision: existing.item.currentRevision, content: body)
            } else {
                _ = try await api.createPriceBookItem(body, idempotencyKey: createKey)
            }
            onSaved()
            dismiss()
        } catch is CancellationError {
        } catch {
            self.error = error.isConnectivityFailure ? "Saving needs a connection." : error.localizedDescription
        }
    }
}
