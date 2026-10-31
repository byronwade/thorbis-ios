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
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @Environment(\.dynamicTypeSize) private var typeSize

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
                                    message: "The Inbox needs the notices permission. An owner can turn it on in Team.")
                } else {
                    PaperTabs(options: ["All", "Unread"], selection: $filter)
                    if let error { ErrorBanner(message: error) { await refresh() } }
                    if loading && items.isEmpty && error == nil { SkeletonRows(count: 5) }
                    let notices = visible
                    let displayCalendar = calendarWithTimeZone
                    ForEach(Array(notices.enumerated()), id: \.element.id) { index, notice in
                        let heading = InboxNoticeDay.header(notice.at, after: index > 0 ? notices[index - 1].at : nil,
                                                            hasPrevious: index > 0, calendar: displayCalendar, locale: locale)
                        // One card per day: a run ends where the next notice starts a new day.
                        let endsRun = index == notices.count - 1 || InboxNoticeDay.header(notices[index + 1].at, after: notice.at,
                                                                                         hasPrevious: true, calendar: displayCalendar, locale: locale) != nil
                        if let heading {
                            PaperGroupHeader(title: heading)
                                .padding(.horizontal, Theme.gutter).padding(.top, 10)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("inbox-day-heading")
                        }
                        // Each notice opens the job it is about.
                        NavigationLink(value: PaperRoute.job(notice.jobId)) {
                        // At accessibility sizes "Unread" goes under the notice so the words keep the width.
                        let rowLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                                                                     : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                        rowLayout {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(notice.title).font(Theme.font(15, weight: notice.read ? .regular : .medium))
                                    .foregroundStyle(notice.read ? Theme.muted : Theme.foreground)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text([notice.meta, timeLabel(notice.at)].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                            // Unread as a word with the accent dot; read notices need no word.
                            if !notice.read { StatusWord(text: "Unread", tint: Theme.brandText).padding(.top, 2) }
                        }
                        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                        .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel([notice.title, notice.meta, timeLabel(notice.at), notice.read ? "Read" : "Unread"]
                            .filter { !$0.isEmpty }.joined(separator: ", "))
                        .accessibilityHint("Opens the job")
                        .paperCardSlot(first: heading != nil || index == 0, last: endsRun)
                        .paperCardMargin()
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
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    PaperCircleButton(symbol: "checkmark.circle", label: readCursor == nil ? "Mark all read" : "Continue marking read",
                                      fill: Theme.card, bordered: true) { Task { await markReadBatch() } }
                        .disabled(loading)
                }
            }
        }
        .refreshable { await refresh() }
        .task { await refresh() }
    }

    private var subtitle: String {
        if !available { return "Job updates" }
        switch unreadState {
        case .present: return "Unread notices waiting"
        case .unknown: return loading ? "Checking for new notices…" : "Job updates"
        default: return "All caught up"
        }
    }

    private var calendarWithTimeZone: Calendar {
        var result = calendar
        result.timeZone = timeZone
        return result
    }

    private func timeLabel(_ raw: String?) -> String {
        guard let raw, let date = JobFiltering.date(raw) else { return "" }
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
    /// Shown as the Revenue section of Money, under Money's own header and scroll.
    var embedded = false

    @State private var report: RevenueReport?
    @State private var error: String?

    /// Paper 59/60: the month's number large, receivables beside it, six months as bars.
    var body: some View {
        if embedded {
            sections.task { await load() }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Money").font(Theme.font(30, weight: .medium)).tracking(-0.6).accessibilityAddTraits(.isHeader)
                        Text("Revenue and receivables · live").font(Theme.font(15)).foregroundStyle(Theme.muted)
                    }
                    .padding(.bottom, 16)
                    sections
                }
                .padding(.horizontal, Theme.gutter).padding(.bottom, 24)
            }
            .foregroundStyle(Theme.foreground)
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await load() }
            .task { await load() }
        }
    }

    @ViewBuilder private var sections: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            PaperStatRow(stats: [
                .init(label: "Outstanding", value: money(report.receivable.balance, currency: "USD"),
                      detail: "\(report.receivable.openInvoices) open invoice\(report.receivable.openInvoices == 1 ? "" : "s")"),
                .init(label: "Overdue", value: money(report.receivable.overdueBalance, currency: "USD"),
                      detail: "\(report.receivable.overdueInvoices) invoice\(report.receivable.overdueInvoices == 1 ? "" : "s")",
                      detailTint: report.receivable.overdueInvoices > 0 ? Theme.destructive : Theme.muted),
            ])
        }
        .buttonStyle(RowPressStyle())
        .accessibilityHint("Opens invoices")
        .padding(.bottom, 18)

        PaperGroupHeader(title: "By month", count: months.count)
        PaperCardList(data: Array(months.reversed())) { month in
            // Month and what was invoiced on the left, what came in on the right: one amount per side.
            HStack(alignment: .center, spacing: 12) {
                IconTile(symbol: "calendar")
                VStack(alignment: .leading, spacing: 2) {
                    Text(monthName(month.month, long: true)).font(Theme.font(15, weight: .medium))
                    Text("Invoiced \(money(month.revenue, currency: "USD"))")
                        .font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 12)
                Text(money(month.collected, currency: "USD")).moneyStyle(.row)
            }
            .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 8)
            .frame(minHeight: 60)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let canList: Bool
    let canViewDetail: Bool

    @State private var items: [PriceBookListItem] = []
    @State private var nextCursor: String?
    @State private var loading = false
    @State private var error: String?
    @State private var search = ""
    @State private var category = "All"
    @State private var creating = false
    @State private var collapsedGroups: Set<String> = []
    @State private var localDetail: PriceBookLocalSelection?
    @State private var displayedScope: PriceBookLocalScope?
    @State private var requestEpoch = UUID()
    /// pricebook.edit is the server's capability for Price Book changes; organization.settings.edit
    /// covers servers that predate it.
    private var canEdit: Bool {
        session.can("pricebook.edit", feature: "price_book") || session.can("organization.settings.edit", feature: "price_book")
    }

    private var localScope: PriceBookLocalScope? {
        guard canList, session.can("pricebook.view", feature: "price_book"),
              let actor = session.user?.id, let organization = session.activeOrganization?.id,
              let origin = api.normalizedOrigin else { return nil }
        return PriceBookLocalScope(actor: actor, organization: organization, origin: origin,
                                   generation: session.generation, authorityRevision: session.authorityRevision)
    }

    private var hasCurrentOwner: Bool {
        guard let displayedScope, let localScope else { return false }
        return displayedScope.sameOwner(as: localScope)
    }
    private var showingPreviousItems: Bool { hasCurrentOwner && displayedScope != localScope }
    private var currentItems: [PriceBookListItem] { hasCurrentOwner ? items : [] }
    private var currentCursor: String? { hasCurrentOwner ? nextCursor : nil }

    private var categories: [String] {
        ["All"] + Array(Set(currentItems.map { $0.kind.capitalized })).sorted()
    }

    private var visibleItems: [PriceBookListItem] {
        currentItems.filter { item in
            (category == "All" || item.kind.capitalized == category) &&
            (search.isEmpty || item.description.localizedCaseInsensitiveContains(search) ||
             item.kind.localizedCaseInsensitiveContains(search) ||
             item.unit.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !canList || localScope == nil {
                PaperEmptyState(symbol: "book.closed", title: "Price book is off for your role",
                                message: "Viewing prices needs the price book permission. An owner can turn it on in Team.")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Price book").font(Theme.font(30, weight: .medium)).tracking(-0.6).foregroundStyle(Theme.foreground)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(currentItems.count) item\(currentItems.count == 1 ? "" : "s")\(currentCursor == nil ? "" : " loaded")")
                        .font(Theme.font(15)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.gutter).padding(.bottom, 12)
                PaperSearchField(text: $search, prompt: "Search price book")
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(categories, id: \.self) { option in
                            Button {
                                category = option
                                if option == "All" { collapsedGroups.removeAll() }
                                else { collapsedGroups.remove(option) }
                            } label: {
                                Text(option == "All" ? "All · \(currentItems.count)\(currentCursor == nil ? "" : " loaded")" : option)
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
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if hasCurrentOwner, let error { ErrorBanner(message: error) { await refresh() }.padding(.horizontal, -PaperCardMetrics.margin) }
                        if showingPreviousItems {
                            HStack {
                                Text("Showing previously loaded items. Refresh to update.")
                                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                                Spacer()
                                Button("Refresh") { Task { await refresh() } }
                                    .disabled(loading)
                            }.frame(minHeight: 44).padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
                        }
                        if (loading || !hasCurrentOwner) && currentItems.isEmpty && error == nil { SkeletonRows(count: 6, leading: false, inset: 0) }
                        ForEach(categories.filter { $0 != "All" && (category == "All" || category == $0) }, id: \.self) { groupName in
                            let grouped = visibleItems.filter { $0.kind.capitalized == groupName }
                            if !grouped.isEmpty {
                                Button {
                                    if collapsedGroups.contains(groupName) { collapsedGroups.remove(groupName) }
                                    else { collapsedGroups.insert(groupName) }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: collapsedGroups.contains(groupName) ? "chevron.right" : "chevron.down")
                                            .frame(width: 16)
                                        Text(groupName).font(Theme.font(13, weight: .medium))
                                        Spacer()
                                        Text("\(grouped.count)\(currentCursor == nil ? "" : " loaded")").font(Theme.monoFont(12))
                                    }
                                    .foregroundStyle(Theme.muted).frame(minHeight: 44).contentShape(Rectangle())
                                    .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(groupName), \(grouped.count)\(currentCursor == nil ? "" : " loaded")")
                                .accessibilityValue(collapsedGroups.contains(groupName) ? "Collapsed" : "Expanded")
                                if !collapsedGroups.contains(groupName) {
                                    LazyVStack(spacing: 0) {
                                        PaperCardList(data: grouped) { item in
                                            if canViewDetail {
                                                NavigationLink {
                                                    WorkspacePriceBookDetailView(api: api, id: item.id, canEdit: canEdit).thorbisBackButton()
                                                } label: { row(item, showFullDescription: showingPreviousItems) }
                                                .buttonStyle(RowPressStyle())
                                            } else if showingPreviousItems {
                                                // Preserve the previously visible description without opening new detail under stale authority.
                                                row(item, showFullDescription: true)
                                            } else {
                                                Button {
                                                    if let scope = localScope { localDetail = PriceBookLocalSelection(item: item, scope: scope) }
                                                } label: { row(item) }.buttonStyle(RowPressStyle())
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        if currentCursor != nil {
                            Button("Load more items") {
                                Task { await loadMore() }
                            }
                                .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                                .frame(maxWidth: .infinity).frame(minHeight: 44)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.border))
                                .buttonStyle(PressStyle())
                                .disabled(loading)
                        }
                        if hasCurrentOwner && visibleItems.isEmpty && !loading && error == nil {
                            if currentItems.isEmpty {
                                PaperEmptyState(symbol: "book.closed", title: "No price book items yet",
                                                message: "Services, parts and fees you add here show up when building estimates and invoices.",
                                                actionTitle: canEdit ? "Add an item" : nil,
                                                action: canEdit ? { creating = true } : nil)
                            } else {
                                PaperEmptyState(symbol: "magnifyingglass", title: "No matching items",
                                                message: showingPreviousItems ? "No previously loaded items match. Refresh to search the current price book." : (currentCursor == nil ? "Nothing in \(category == "All" ? "the price book" : category.lowercased()) matches that search." : "No loaded items match. Load more items to search the rest."),
                                                actionTitle: "Clear filters") { search = ""; category = "All" }
                            }
                        }
                    }
                    .paperCardMargin().padding(.top, 8).padding(.bottom, 100)
                }
                .refreshable { await refresh() }
                .task(id: localScope) {
                    guard let scope = localScope else { return }
                    await activate(scope: scope)
                }
                .onChange(of: search) { _, _ in collapsedGroups.removeAll() }
                .onChange(of: localScope) { _, _ in localDetail = nil }
                .safeAreaInset(edge: .bottom) {
                    if canEdit {
                        Button { creating = true } label: {
                            Label("Add price book item", systemImage: "plus").inkCommit()
                        }
                        .buttonStyle(PressStyle()).padding(.horizontal, Theme.gutter).padding(.vertical, 10)
                        .background(Theme.background)
                    }
                }
                #if DEBUG
                .toolbar {
                    if ProcessInfo.processInfo.arguments.contains("--paper-preview-pricebook-authority") {
                        ThorbisToolbarItem(placement: .topBarTrailing) {
                            Button("Change sample access shortly") {
                                Task { @MainActor in
                                    try? await Task.sleep(for: .seconds(5))
                                    guard !Task.isCancelled else { return }
                                    if ProcessInfo.processInfo.arguments.contains("--paper-preview-pricebook-switch") {
                                        PaperPreviewProtocol.switchSavedWorkWorkspace()
                                    } else if !ProcessInfo.processInfo.arguments.contains("--paper-preview-pricebook-renew") {
                                        PaperPreviewProtocol.revokePriceBookView()
                                    }
                                    if ProcessInfo.processInfo.arguments.contains("--paper-preview-pricebook-refresh-failure") {
                                        PaperPreviewProtocol.failPriceBookQuery()
                                    }
                                    await session.revalidate()
                                }
                            }
                        }
                    }
                }
                #endif
                .sheet(isPresented: $creating) { PriceBookItemEditor(api: api) { Task { await refresh() } } }
                .sheet(item: $localDetail) { selection in
                    if localScope == selection.scope {
                        PriceBookLocalDetail(item: selection.item)
                    } else {
                        Text("Price book access changed.")
                    }
                }
            }
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ item: PriceBookListItem, showFullDescription: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: priceBookSymbol(for: item.kind), tint: Theme.brandText, fill: Theme.brandSurface)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    itemTitle(item, showFullDescription: showFullDescription)
                    itemUnit(item)
                    itemPrice(item)
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    itemTitle(item, showFullDescription: showFullDescription)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        itemUnit(item)
                        Spacer(minLength: 6)
                        itemPrice(item).fixedSize(horizontal: true, vertical: false)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 10).frame(minHeight: 60)
        .contentShape(Rectangle())
        // MA-12: the quick copies people reach for while quoting on the phone.
        .contextMenu {
            Button { UIPasteboard.general.string = money(item.sellPrice.amount, currency: item.sellPrice.currency) } label: {
                Label("Copy price", systemImage: "dollarsign")
            }
            Button { UIPasteboard.general.string = PriceBookPresentation.title(item.description) } label: { Label("Copy name", systemImage: "doc.on.doc") }
            Button { UIPasteboard.general.string = PriceBookPresentation.readableDescription(item.description) } label: { Label("Copy full description", systemImage: "doc.text") }
            Button { UIPasteboard.general.string = item.description } label: { Label("Copy stored text", systemImage: "doc.on.doc") }
        }
    }

    private func itemTitle(_ item: PriceBookListItem, showFullDescription: Bool) -> some View {
        Text(showFullDescription ? PriceBookPresentation.readableDescription(item.description) : PriceBookPresentation.title(item.description))
            .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
            .lineLimit(showFullDescription || dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func itemUnit(_ item: PriceBookListItem) -> some View {
        Text(([item.unit] + (item.archivedAt == nil ? [] : ["Archived"])).joined(separator: " · "))
            .font(Theme.font(13)).foregroundStyle(Theme.muted)
    }

    private func itemPrice(_ item: PriceBookListItem) -> some View {
        Text(money(item.sellPrice.amount, currency: item.sellPrice.currency))
            .moneyStyle(.row).foregroundStyle(Theme.foreground)
    }

    private func priceBookSymbol(for kind: String) -> String {
        switch kind.lowercased() {
        case "service": "wrench.and.screwdriver"
        case "material": "shippingbox"
        case "labor": "person"
        case "assembly": "square.stack.3d.up"
        default: "tag"
        }
    }

    private func activate(scope: PriceBookLocalScope) async {
        guard localScope == scope else { return }
        requestEpoch = UUID()
        if let displayedScope, displayedScope.sameOwner(as: scope), !items.isEmpty {
            // The existing screen allowed these already-loaded rows offline. Keep them
            // clearly stale and fully readable, but require a fresh fetch for local detail.
            loading = false
            error = nil
            return
        }
        displayedScope = scope
        items = []
        nextCursor = nil
        error = nil
        loading = false
        await refresh()
    }

    private func refresh() async {
        guard let scope = localScope, let oldScope = displayedScope, oldScope.sameOwner(as: scope), !loading else { return }
        let epoch = UUID()
        requestEpoch = epoch
        loading = true
        defer { if requestEpoch == epoch { loading = false } }
        do {
            let page = try await api.priceBookItems(requireFresh: oldScope != scope)
            guard localScope == scope, displayedScope == oldScope, requestEpoch == epoch else { return }
            items = page.items
            nextCursor = page.nextCursor
            displayedScope = scope
            error = nil
        } catch {
            guard localScope == scope, displayedScope == oldScope, requestEpoch == epoch else { return }
            self.error = PriceBookLoadError.message(for: error)
        }
    }

    private func loadMore() async {
        guard let scope = localScope, let oldScope = displayedScope, oldScope.sameOwner(as: scope), !loading, let cursor = currentCursor else { return }
        let epoch = UUID()
        requestEpoch = epoch
        loading = true
        defer { if requestEpoch == epoch { loading = false } }
        do {
            let page = try await api.priceBookItems(cursor: cursor)
            guard localScope == scope, displayedScope == oldScope, requestEpoch == epoch else { return }
            guard page.nextCursor != cursor else {
                throw Problem(title: "Price Book pagination stopped", status: nil, detail: "The server repeated its cursor.")
            }
            items.append(contentsOf: page.items)
            nextCursor = page.nextCursor
            error = nil
        } catch {
            guard localScope == scope, displayedScope == oldScope, requestEpoch == epoch else { return }
            self.error = PriceBookLoadError.message(for: error)
        }
    }
}

private struct PriceBookLocalScope: Equatable {
    let actor: String
    let organization: String
    let origin: String
    let generation: UUID
    let authorityRevision: UUID

    func sameOwner(as other: Self) -> Bool {
        actor == other.actor && organization == other.organization && origin == other.origin && generation == other.generation
    }
}

private struct PriceBookLocalSelection: Identifiable {
    let item: PriceBookListItem
    let scope: PriceBookLocalScope
    var id: String { item.id }
}

/// Uses only data already returned by the list when the role cannot open the server detail.
private struct PriceBookLocalDetail: View {
    let item: PriceBookListItem
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Description") { Text(PriceBookPresentation.readableDescription(item.description)).textSelection(.enabled) }
                LabeledContent("Price") { Text(money(item.sellPrice.amount, currency: item.sellPrice.currency)) }
                LabeledContent("Unit", value: item.unit)
                LabeledContent("Kind", value: item.kind.capitalized)
                if item.archivedAt != nil { LabeledContent("Status", value: "Archived") }
            }
            .navigationTitle("Price book item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ThorbisToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
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
                Section("Description") {
                    Text(PriceBookPresentation.readableDescription(detail.revision.description))
                        .textSelection(.enabled)
                }
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
        .navigationTitle("Price book item")
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if canEdit, detail?.item.status == "active" {
                ThorbisToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } }
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
                ThorbisToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() }.disabled(busy) }
                ThorbisToolbarItem(placement: .topBarTrailing) { Button("Save") { Task { await save() } }.disabled(!valid || busy) }
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

// Presentation-only grouping of an already-ordered notice feed.
enum InboxNoticeDay {
    static func header(_ raw: String?, after previous: String?, hasPrevious: Bool, calendar: Calendar, locale: Locale) -> String? {
        let date = JobFiltering.date(raw)
        let prior = JobFiltering.date(previous)
        if hasPrevious {
            if let date, let prior, calendar.isDate(date, inSameDayAs: prior) { return nil }
            if date == nil && prior == nil { return nil }
        }
        guard let date else { return "Date unavailable" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
