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
                    Text("Inbox").font(Theme.font(30, weight: .medium)).tracking(-0.6).accessibilityAddTraits(.isHeader)
                    Text(subtitle).font(Theme.font(15)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, Theme.gutter).padding(.bottom, 12)
                if !available {
                    PaperEmptyState(symbol: "bell.slash", title: "Inbox is off for your role",
                                    message: "Job notices need the notices permission. An owner can turn it on in Team.")
                } else {
                    PaperTabs(options: ["All", "Unread"], selection: $filter)
                    if let error { ErrorBanner(message: error) { await refresh() } }
                    if loading && items.isEmpty && error == nil { SkeletonRows(count: 5) }
                    ForEach(visible) { notice in
                        // Each notice opens the job it is about.
                        NavigationLink(value: PaperRoute.job(notice.jobId)) {
                        // MA-11: what and when, with the unread state as a shape (dot) and weight, not a tinted tile.
                        HStack(alignment: .top, spacing: 12) {
                            Circle().fill(notice.read ? Color.clear : Theme.brand).frame(width: 8, height: 8).padding(.top, 7)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(notice.title).font(Theme.font(15, weight: notice.read ? .regular : .medium))
                                    .foregroundStyle(notice.read ? Theme.muted : Theme.foreground)
                                Text([notice.meta, timeLabel(notice.at)].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(Theme.font(13)).foregroundStyle(Theme.muted).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.muted).padding(.top, 4).accessibilityHidden(true)
                        }
                        .padding(.horizontal, Theme.gutter).padding(.vertical, 10)
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(notice.read ? "" : "Unread")
                        .accessibilityHint("Opens the job")
                    }
                    if nextCursor != nil {
                        Button("Load older notices") { Task { await loadMore() } }
                            .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.brandText)
                            .frame(maxWidth: .infinity, minHeight: 44).disabled(loading)
                    }
                    if visible.isEmpty && !loading && error == nil {
                        if filter == "Unread" && !items.isEmpty {
                            PaperEmptyState(symbol: "checkmark.circle", title: "All caught up",
                                            message: "You have read every notice.", actionTitle: "Show all notices") { filter = "All" }
                        } else {
                            PaperEmptyState(symbol: "tray", title: "No notices yet",
                                            message: "Assignments and job changes for you land here.")
                        }
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
                    Text("Money").font(Theme.font(30, weight: .medium)).tracking(-0.6).accessibilityAddTraits(.isHeader)
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
                    SkeletonRows(count: 4, leading: false, inset: 0)
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
                    .moneyStyle(.hero)
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
            // Month and what was invoiced on the left, what came in on the right: one amount per side.
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(monthName(month.month, long: true)).font(Theme.font(15, weight: .medium))
                    Text("Invoiced \(money(month.revenue, currency: "USD"))")
                        .font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 12)
                Text(money(month.collected, currency: "USD")).moneyStyle(.row)
            }
            .padding(.vertical, 8)
            .frame(minHeight: 56)
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
            Text(value).moneyStyle(.total)
            Text(detail).font(Theme.font(12, weight: alert == nil ? .regular : .medium)).foregroundStyle(alert ?? Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border))
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
                PaperEmptyState(symbol: "book.closed", title: "Price book is off for your role",
                                message: "Viewing prices needs the price book permission. An owner can turn it on in Team.")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Price book").font(Theme.font(30, weight: .medium)).tracking(-0.6).foregroundStyle(Theme.foreground)
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
                                    .font(Theme.font(13, weight: .medium))
                                    .foregroundStyle(category == option ? Theme.foreground : Theme.muted)
                                    .padding(.horizontal, 14).frame(height: Theme.chipHeight)
                                    .background(category == option ? Theme.fill : .clear, in: Capsule())
                                    .overlay(Capsule().stroke(category == option ? Theme.border : .clear))
                                    .frame(minHeight: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityAddTraits(category == option ? .isSelected : [])
                            .sensoryFeedback(.selection, trigger: category)
                        }
                    }.padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let error { ErrorBanner(message: error) { await refresh() }.padding(.horizontal, -Theme.gutter) }
                        if loading && items.isEmpty && error == nil { SkeletonRows(count: 6, leading: false, inset: 0) }
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
                                .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                                .frame(maxWidth: .infinity).frame(minHeight: 44)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.border))
                                .buttonStyle(PressStyle())
                                .disabled(loading)
                        }
                        if visibleItems.isEmpty && !loading && error == nil {
                            if items.isEmpty {
                                PaperEmptyState(symbol: "book.closed", title: "No price book items yet",
                                                message: "Services, parts and fees you add here show up when building estimates and invoices.",
                                                actionTitle: canEdit ? "Add an item" : nil,
                                                action: canEdit ? { creating = true } : nil)
                            } else {
                                PaperEmptyState(symbol: "magnifyingglass", title: "No matching items",
                                                message: "Nothing in \(category == "All" ? "the price book" : category.lowercased()) matches that search.",
                                                actionTitle: "Clear filters") { search = ""; category = "All" }
                            }
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
                Text(([item.kind.capitalized, item.unit] + (item.archivedAt == nil ? [] : ["Archived"])).joined(separator: " · "))
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 6)
            Text(money(item.sellPrice.amount, currency: item.sellPrice.currency))
                .moneyStyle(.row).foregroundStyle(Theme.foreground)
        }
        .frame(minHeight: 50)
        .contentShape(Rectangle())
        // MA-12: the quick copies people reach for while quoting on the phone.
        .contextMenu {
            Button { UIPasteboard.general.string = money(item.sellPrice.amount, currency: item.sellPrice.currency) } label: {
                Label("Copy price", systemImage: "dollarsign")
            }
            Button { UIPasteboard.general.string = item.description } label: { Label("Copy name", systemImage: "doc.on.doc") }
        }
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
        } catch { self.error = PriceBookLoadError.message(for: error) }
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
        } catch { self.error = PriceBookLoadError.message(for: error) }
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
                LabeledContent("Price") { Text(money(detail.revision.sellPrice.amount, currency: detail.revision.sellPrice.currency)).moneyStyle(.total) }
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
        .thorbisConfirm("Remove this item from the price book?", isPresented: $confirmArchive,
                        actions: [ThorbisConfirmAction("Remove", role: .destructive) { Task { await archive() } }])
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
                    ThorbisSelect(options: PriceBookContent.kinds.map { ($0, $0.capitalized) },
                                  selection: $content.kind, label: "Kind")
                    ThorbisSelect(options: [("taxable", "Taxable"), ("non_taxable", "Not taxable")],
                                  selection: $content.taxClassification, label: "Tax")
                }
                if let error { Section { ListErrorRow(message: error) } }
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
