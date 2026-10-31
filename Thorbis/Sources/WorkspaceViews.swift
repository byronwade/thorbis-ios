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
    /// The job a row's swipe opened.
    @State private var openingJob: String?
    /// One open row at a time; scrolling closes it.
    @StateObject private var swipes = RowSwipeState()
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
                    // A place's title, Medium on the root-title step like the tab roots.
                    Text("Inbox").font(Theme.font(34, weight: .medium)).tracking(-0.8).accessibilityAddTraits(.isHeader)
                    Text(subtitle).font(Theme.font(15)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, Theme.gutter).padding(.bottom, 12)
                if !available {
                    // Permission names what is missing (design.thorbis.com States).
                    ListRoomEmpty(title: "Your role can\u{2019}t see notices.", message: "Ask your office for access to the Inbox.")
                } else {
                    // v2 List room: All / Unread as text tabs on the view bar.
                    ListViewBar(options: ["All", "Unread"], selection: $filter)
                    if let error { ErrorBanner(message: error) { await refresh() } }
                    if loading && items.isEmpty && error == nil { ListRoomSkeleton(count: 6, threeLines: false) }
                    let notices = visible
                    let displayCalendar = calendarWithTimeZone
                    ForEach(Array(notices.enumerated()), id: \.element.id) { index, notice in
                        let heading = InboxNoticeDay.header(notice.at, after: index > 0 ? notices[index - 1].at : nil,
                                                            hasPrevious: index > 0, calendar: displayCalendar, locale: locale)
                        // Day groups on the canvas: a 13 Medium label, space above it, no lines.
                        if let heading {
                            ListGroupLabel(title: dayLabel(heading, raw: notice.at, calendar: displayCalendar), first: index == 0)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("inbox-day-heading")
                        }
                        // Each notice opens the job it is about. Swipe right offers the same, as a
                        // shortcut. Read/Unread is not a swipe: the notices API only marks the whole
                        // inbox read (POST /v1/staff/notices/read), not one notice.
                        let open = RowSwipeAction(id: "row-swipe-open-\(notice.id)", title: "Open job",
                                                  symbol: "arrow.up.right", tone: .ink, spokenName: "Open job") {
                            openingJob = notice.jobId
                        }
                        RowSwipeContainer(id: notice.id, leading: [open], state: swipes) {
                            NavigationLink(value: PaperRoute.job(notice.jobId)) {
                                // What happened, then the job; the time trails. Unread is Medium and the dot.
                                InboxRoomRow(title: notice.title, detail: notice.meta, time: timeLabel(notice.at), unread: !notice.read)
                            }
                            .buttonStyle(RowPressStyle())
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel([notice.title, notice.meta, spokenTime(notice.at), notice.read ? "Read" : "Unread"]
                                .filter { !$0.isEmpty }.joined(separator: ", "))
                            .accessibilityHint("Opens the job")
                            .accessibilityIdentifier("inbox-row-\(notice.id)")
                            .rowSwipeAccessibility([open])
                        }
                    }
                    if nextCursor != nil {
                        Button { Task { await loadMore() } } label: {
                            Text(loading ? "Loading…" : "Load older notices").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                                .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .disabled(loading)
                        .padding(.top, 12)
                    }
                    if visible.isEmpty && !loading && error == nil {
                        if filter == "Unread" && !items.isEmpty {
                            ListRoomEmpty(title: "No unread notices.", message: "All shows every notice.")
                        } else {
                            ListRoomEmpty(title: "No notices yet.", message: "New assignments and job changes land here.")
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
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
        .onScrollPhaseChange { _, phase in if phase != .idle { swipes.close() } }
        .thorbisDestination(item: $openingJob) { JobDetailView(jobId: $0).tabletReadable() }
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

    /// The time of day ("7:40 a.m."), tabular at the row's end; the day is the group's label.
    private func timeLabel(_ raw: String?) -> String {
        guard let raw, let date = JobFiltering.date(raw) else { return "" }
        return date.tradeTime
    }

    /// How long ago, for VoiceOver ("5 min. ago"), so the day is not lost when a row is read alone.
    private func spokenTime(_ raw: String?) -> String {
        guard let raw, let date = JobFiltering.date(raw) else { return "" }
        return date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }

    /// "Today" and "Yesterday" read faster than a date for the newest groups; older days keep theirs.
    private func dayLabel(_ heading: String, raw: String?, calendar: Calendar) -> String {
        guard let date = JobFiltering.date(raw) else { return heading }
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return heading
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
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await load() }
            .task { await load() }
        }
    }

    @ViewBuilder private var sections: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !available {
                PaperEmptyState(symbol: "chart.bar.xaxis", title: "You can't see money reports", message: "Your role doesn't include invoices and payments. Ask an owner for access.")
            } else if let error {
                ErrorBanner(message: error).padding(.horizontal, -Theme.gutter)
            } else if let report {
                if report.truncated {
                    PaperEmptyState(symbol: "exclamationmark.triangle", title: "This report is too big for the phone",
                                    message: "These totals would come up short. Open the full report on the web.")
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
                    .font(Theme.moneyHeroFont).tracking(-0.6)
                    .lineLimit(1).minimumScaleFactor(0.6)
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

        // v2: what's due as two quiet rows, not a pair of equal tiles. Each opens the invoices behind it.
        PaperSection("Due") {
            VStack(spacing: 0) {
                NavigationLink(value: PaperRoute.invoices) {
                    dueRow(word: "Outstanding", tone: .scheduled,
                           detail: "\(report.receivable.openInvoices) open invoice\(report.receivable.openInvoices == 1 ? "" : "s")",
                           amount: money(report.receivable.balance, currency: "USD"))
                }
                .buttonStyle(RowPressStyle())
                NavigationLink(value: PaperRoute.invoices) {
                    dueRow(word: "Overdue", tone: report.receivable.overdueInvoices > 0 ? .attention : .done,
                           detail: "\(report.receivable.overdueInvoices) invoice\(report.receivable.overdueInvoices == 1 ? "" : "s")",
                           amount: money(report.receivable.overdueBalance, currency: "USD"))
                }
                .buttonStyle(RowPressStyle())
            }
            .padding(.vertical, PaperCardMetrics.edge)
        }
        .accessibilityHint("Opens invoices")
        .padding(.bottom, 24)

        // design 2026-10-30: plain rows on one panel, no calendar tiles.
        PaperSection("By month", count: months.count) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(months.reversed())) { month in
                    // Month and what was invoiced on the left, what came in on the right: one amount per side.
                    PaperListRow(title: monthName(month.month, long: true),
                                 subtitle: "Invoiced \(money(month.revenue, currency: "USD"))",
                                 amount: money(month.collected, currency: "USD"))
                        .accessibilityElement(children: .combine)
                }
            }
            .padding(.vertical, PaperCardMetrics.edge)
        }
    }

    /// A receivable as a row: its word with its mark, how many invoices, the amount in the tabular column.
    private func dueRow(word: String, tone: StatusTone, detail: String, amount: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                StatusLabel(tone: tone, word: word, size: 15)
                Text(detail).font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            Text(amount).font(Theme.rowAmountFont(15)).foregroundStyle(Theme.foreground)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 10)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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

    /// The first group with rows on screen; its label sits closer to the search field.
    private var firstVisibleGroup: String? {
        categories.first { name in
            name != "All" && (category == "All" || category == name) && visibleItems.contains { $0.kind.capitalized == name }
        }
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
                PaperEmptyState(symbol: "book.closed", title: "You can't see the price book",
                                message: "Your role doesn't have the price book permission. An owner can turn it on in Team.")
            } else {
                // design 2026-10-30: one selector per screen — the category chips moved behind the
                // header's filter circle; the count and the chosen category read in the subtitle.
                PaperHeader(title: "Price book",
                            subtitle: "\(currentItems.count) item\(currentItems.count == 1 ? "" : "s")\(currentCursor == nil ? "" : " loaded")\(category == "All" ? "" : " · showing \(category.lowercased())")",
                            filterMenu: categories.map { option in
                                ThorbisMenuItem(option == "All" ? "All · \(currentItems.count)\(currentCursor == nil ? "" : " loaded")" : option,
                                                isSelected: category == option) {
                                    category = option
                                    if option == "All" { collapsedGroups.removeAll() }
                                    else { collapsedGroups.remove(option) }
                                }
                            },
                            filterActive: category != "All")
                    .environment(\.paperMenuButton, false)
                PaperSearchField(text: $search, prompt: "Search price book")
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if hasCurrentOwner, let error { ErrorBanner(message: error) { await refresh() } }
                        if showingPreviousItems {
                            HStack {
                                Text("Showing previously loaded items. Refresh to update.")
                                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                                Spacer()
                                Button("Refresh") { Task { await refresh() } }
                                    .disabled(loading)
                            }.frame(minHeight: 44).padding(.horizontal, ListRoom.gutter)
                        }
                        if (loading || !hasCurrentOwner) && currentItems.isEmpty && error == nil { ListRoomSkeleton(count: 6, threeLines: false) }
                        ForEach(categories.filter { $0 != "All" && (category == "All" || category == $0) }, id: \.self) { groupName in
                            let grouped = visibleItems.filter { $0.kind.capitalized == groupName }
                            if !grouped.isEmpty {
                                // v2 List room, like Jobs and Customers: the group's 13 Medium label with
                                // its count on the canvas (it folds the group), then the rows, no panel.
                                Button {
                                    if collapsedGroups.contains(groupName) { collapsedGroups.remove(groupName) }
                                    else { collapsedGroups.insert(groupName) }
                                } label: {
                                    ListGroupLabel(title: groupName, count: grouped.count, first: groupName == firstVisibleGroup) {
                                        Image(systemName: collapsedGroups.contains(groupName) ? "chevron.right" : "chevron.down")
                                            .font(.system(size: 10, weight: .medium))
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(groupName), \(grouped.count)\(currentCursor == nil ? "" : " loaded")")
                                .accessibilityValue(collapsedGroups.contains(groupName) ? "Collapsed" : "Expanded")
                                if !collapsedGroups.contains(groupName) {
                                    // Redesign phase 3: the group's items on one well, hairlines between rows.
                                    LazyVStack(spacing: 0) {
                                        ForEach(Array(grouped.enumerated()), id: \.element.id) { index, item in
                                            Group {
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
                                            .environment(\.paperRowInset, ListRoom.gutter)
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
                                .panelBackground(cornerRadius: Theme.controlRadius)
                                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.border))
                                .buttonStyle(PressStyle())
                                .disabled(loading)
                                .padding(.horizontal, ListRoom.gutter).padding(.top, 16)
                        }
                        if hasCurrentOwner && visibleItems.isEmpty && !loading && error == nil {
                            if currentItems.isEmpty {
                                ListRoomEmpty(title: "No price book items.",
                                              message: canEdit ? "Services, parts and fees you add here fill estimates and invoices." : "Services, parts and fees your office adds show up here.",
                                              actionTitle: canEdit ? "Add an item" : nil, action: { creating = true })
                            } else {
                                PaperEmptyState(symbol: "magnifyingglass", title: "No matching items",
                                                message: showingPreviousItems ? "No previously loaded items match. Refresh to search the current price book." : (currentCursor == nil ? "Nothing in \(category == "All" ? "the price book" : category.lowercased()) matches that search." : "No loaded items match. Load more items to search the rest."),
                                                actionTitle: "Clear filters") { search = ""; category = "All" }
                            }
                        }
                    }
                    .padding(.top, 0).padding(.bottom, 100)
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
                        .background(Theme.canvas)
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
                .sheet(isPresented: $creating) { SheetSurface { PriceBookItemEditor(api: api) { Task { await refresh() } } } }
                .sheet(item: $localDetail) { selection in SheetSurface {
                    if localScope == selection.scope {
                        PriceBookLocalDetail(item: selection.item)
                    } else {
                        Text("Price book access changed.")
                    }
                } }
            }
        }
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ item: PriceBookListItem, showFullDescription: Bool = false) -> some View {
        // design 2026-10-30: the list row — name, unit, the price on the right; no kind tile
        // (the group label above already says the kind).
        let unit = ([item.unit] + (item.archivedAt == nil ? [] : ["Archived"])).joined(separator: " · ")
        return Group {
            if showFullDescription {
                // Stale rows keep their full description, unclipped.
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        itemTitle(item, showFullDescription: true)
                        Text(unit).font(Theme.font(15)).foregroundStyle(Theme.muted)
                    }
                    itemPrice(item).fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, ListRoom.gutter).padding(.vertical, 12)
            } else {
                PaperListRow(title: PriceBookPresentation.title(item.description), subtitle: unit) {
                    itemPrice(item).fixedSize(horizontal: true, vertical: false)
                }
            }
        }
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

    private func itemPrice(_ item: PriceBookListItem) -> some View {
        Text(money(item.sellPrice.amount, currency: item.sellPrice.currency))
            .font(Theme.rowAmountFont(15)).lineLimit(1).minimumScaleFactor(0.7)
            .foregroundStyle(Theme.foreground)
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
            ScrollView {
                PriceBookItemSummary(description: item.description,
                                     price: money(item.sellPrice.amount, currency: item.sellPrice.currency),
                                     facts: [("Unit", item.unit), ("Kind", item.kind.capitalized)]
                                        + (item.archivedAt != nil ? [("Status", "Archived")] : []))
                    .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 8).padding(.bottom, 24)
            }
            .background(Theme.canvas)
            .navigationTitle("Price book item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ThorbisToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

/// A price book item read top-down: the price, the name and full description, then its facts.
private struct PriceBookItemSummary: View {
    let description: String
    let price: String
    let facts: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(price).font(Theme.font(34, weight: .medium)).monospacedDigit()
                Text(PriceBookPresentation.title(description)).font(Theme.font(20, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
            PaperSection("Description") {
                Text(PriceBookPresentation.readableDescription(description)).font(Theme.font(16))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(PaperCardMetrics.inset)
            }
            PaperSection("Details") {
                VStack(spacing: 0) {
                    ForEach(facts, id: \.0) { fact in PaperDetailRow(fact.0, value: fact.1).cardRow() }
                }
                .padding(.vertical, PaperCardMetrics.edge)
            }
        }
        // Medium headers over grouped wells (v2: 500 is the heaviest weight).
        .environment(\.paperGroupedWells, true)
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
        // design 2026-10-30: price first, the full description, the facts on one panel.
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let error { Text(error).font(Theme.font(15)).foregroundStyle(Theme.destructive) }
                if let detail {
                    PriceBookItemSummary(description: detail.revision.description,
                                         price: money(detail.revision.sellPrice.amount, currency: detail.revision.sellPrice.currency),
                                         facts: [("Unit", detail.revision.unit), ("Kind", detail.revision.kind.capitalized),
                                                 ("Tax", detail.revision.taxClassification.replacingOccurrences(of: "_", with: " ").capitalized)]
                                            + (detail.item.status != "active" ? [("Status", detail.item.status.capitalized)] : []))
                    if canEdit && detail.item.status == "active" {
                        VStack(alignment: .leading, spacing: 6) {
                            Button { confirmArchive = true } label: {
                                Text("Remove from price book").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.destructive)
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(PressStyle())
                            Text("Estimates and invoices that already use it keep their prices.")
                                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        }
                        .padding(.horizontal, 4)
                    }
                } else if error == nil {
                    SkeletonRows(count: 3, leading: false, inset: 0)
                }
            }
            .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 8).padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .navigationTitle("Price book item")
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if canEdit, detail?.item.status == "active" {
                ThorbisToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } }
            }
        }
        .sheet(isPresented: $editing) { SheetSurface {
            if let detail {
                PriceBookItemEditor(api: api, existing: detail) { Task { await load() } }
            }
        } }
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
            // design 2026-10-30: one column, labels above, field wells; Save is the ink commit.
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PaperFormField("Name customers see") {
                        TextField("Replace capacitor", text: $content.description, axis: .vertical).lineLimit(1...3)
                            .font(Theme.font(16)).fieldWell()
                    }
                    PaperFormField("Price") {
                        TextField("0.00", text: $priceText).keyboardType(.decimalPad)
                            .font(Theme.font(16, weight: .medium)).monospacedDigit().fieldWell()
                    }
                    PaperFormField("Unit") {
                        TextField("each, hour, foot…", text: $content.unit).font(Theme.font(16)).fieldWell()
                    }
                    PaperFormField("Kind") {
                        ThorbisSelect(options: PriceBookContent.kinds.map { ($0, $0.capitalized) },
                                      selection: $content.kind, label: "Kind").fieldWell()
                    }
                    PaperFormField("Tax") {
                        ThorbisSelect(options: [("taxable", "Taxable"), ("non_taxable", "Not taxable")],
                                      selection: $content.taxClassification, label: "Tax").fieldWell()
                    }
                    if let error { ListErrorRow(message: error) }
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.canvas)
            .safeAreaInset(edge: .bottom) {
                PaperActionBar(title: existing == nil ? "Add to price book" : "Save item", busy: busy, disabled: !valid) {
                    Task { await save() }
                }
            }
            .navigationTitle(existing == nil ? "New price book item" : "Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ThorbisToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() }.disabled(busy) }
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
