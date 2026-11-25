import SwiftUI

struct WorkspaceRevenueView: View {
    @ObservedObject var api: APIClient
    let available: Bool
    /// Shown as the Revenue section of Money, under Money's own header and scroll.
    var embedded = false

    @State private var report: RevenueReport?
    @State private var error: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Paper 59/60: the month's number large, receivables beside it, six months as bars.
    var body: some View {
        if embedded {
            sections.task { await load() }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PaperHeader(title: "Money", subtitle: "Revenue and receivables · live")
                        .environment(\.paperMenuButton, false)
                        .padding(.horizontal, -PaperCardMetrics.margin)
                    sections
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.bottom, 40)
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
        // Paper 59's lead card: the month's figure large, how it compares, the months as bars.
        VStack(alignment: .leading, spacing: 4) {
            Text("Collected in \(current.map { monthName($0.month, long: true) } ?? "this month")")
                .font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
            Text(money(current?.collected ?? 0, currency: "USD"))
                // Paper 59: the lead figure in 44 Bold; it shrinks on one line before it would clip.
                .font(Theme.display()).tracking(Theme.displayTracking())
                .lineLimit(1).minimumScaleFactor(0.5)
            if let current, let previous, previous.collected > 0 {
                let change = Double(current.collected - previous.collected) / Double(previous.collected) * 100
                HStack(spacing: 5) {
                    Image(systemName: change >= 0 ? "arrow.up" : "arrow.down").font(.system(size: 11, weight: .semibold))
                        .accessibilityHidden(true)
                    Text("\(abs(Int(change.rounded())))%").font(Theme.font(14, weight: .semibold)).monospacedDigit()
                    Text("vs \(monthName(previous.month, long: false))").font(Theme.font(14)).foregroundStyle(Theme.muted)
                }
                .foregroundStyle(change >= 0 ? Theme.success : Theme.destructive)
                .accessibilityElement(children: .combine)
            }
            bars(months)
                .padding(.top, 12)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.bottom, 10)

        // Paper 59's two receivable cards. Each opens the invoices behind it.
        let tiles = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        tiles {
            NavigationLink(value: PaperRoute.invoices) {
                receivableTile(label: "Outstanding", value: money(report.receivable.balance, currency: "USD"),
                               detail: "\(report.receivable.openInvoices) open invoice\(report.receivable.openInvoices == 1 ? "" : "s")",
                               alert: false)
            }
            .buttonStyle(PressStyle())
            NavigationLink(value: PaperRoute.invoices) {
                receivableTile(label: "Overdue", value: money(report.receivable.overdueBalance, currency: "USD"),
                               detail: "\(report.receivable.overdueInvoices) invoice\(report.receivable.overdueInvoices == 1 ? "" : "s")",
                               alert: report.receivable.overdueInvoices > 0)
            }
            .buttonStyle(PressStyle())
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityHint("Opens invoices")
        .padding(.bottom, 20)

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

    /// A receivable as Paper 59's card: 13 Semibold label, the amount in bold tabular, one line
    /// under it (in the destructive word colour while something is overdue).
    private func receivableTile(label: String, value: String, detail: String, alert: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
            Text(value).font(Theme.monoFont(24, weight: .bold)).foregroundStyle(Theme.foreground)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(detail).font(Theme.font(14)).monospacedDigit()
                .foregroundStyle(alert ? Theme.destructive : Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Paper 59: 14 above and under, 16 at the sides.
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
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
                    // Paper 60's trend labels: "Feb", "Mar" in 13 Medium, this month in Semibold ink.
                    Text(monthName(month.month, long: false))
                        .font(Theme.font(13, weight: index == months.count - 1 ? .semibold : .medium))
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
                // Paper 34: the title and count, the search field on the card, then one segment per
                // kind ("All · 212" first). The chosen kind also reads in the subtitle.
                PaperHeader(title: "Price book",
                            subtitle: "\(currentItems.count) item\(currentItems.count == 1 ? "" : "s")\(currentCursor == nil ? "" : " loaded")\(category == "All" ? "" : " · showing \(category.lowercased())")")
                    .environment(\.paperMenuButton, false)
                searchBar.padding(.top, 2)
                if categories.count > 1 {
                    PaperTabs(options: categories.map { $0 == "All" ? allLabel : $0 }, selection: categorySelection)
                        .padding(.top, 12)
                }
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
                                    // Paper 34: the fold chevron leads, the label in 13 Semibold, the count
                                    // trails; 22 above (16 under the segments) and 8 above the card.
                                    HStack(alignment: .center, spacing: 6) {
                                        PaperIcon(.chevronDown, size: 12, color: Theme.muted)
                                            .rotationEffect(.degrees(collapsedGroups.contains(groupName) ? -90 : 0))
                                        Text(groupName).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text("\(grouped.count)").font(Theme.font(13)).foregroundStyle(Theme.muted)
                                    }
                                    .padding(.horizontal, PaperCardMetrics.margin + 4)
                                    .padding(.top, groupName == firstVisibleGroup ? 16 : 22).padding(.bottom, 8)
                                    .frame(minHeight: 44, alignment: .bottom)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(groupName), \(grouped.count)\(currentCursor == nil ? "" : " loaded")")
                                .accessibilityValue(collapsedGroups.contains(groupName) ? "Collapsed" : "Expanded")
                                if !collapsedGroups.contains(groupName) {
                                    // Paper 34: the group's items on one card (radius 20, 16 from the
                                    // edges), a hairline between rows.
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
                                            .environment(\.paperRowInset, PaperCardMetrics.inset)
                                            .overlay(alignment: .top) { if index > 0 { WellDivider() } }
                                        }
                                    }
                                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                                    .padding(.horizontal, PaperCardMetrics.margin)
                                }
                            }
                        }
                        if currentCursor != nil {
                            // Paper v2: the quiet pill (fill, 50 tall, 16 Semibold), 16 from the edges.
                            Button { Task { await loadMore() } } label: {
                                Text("Load more items").paperButton(.commit, tone: .quiet, fills: true)
                            }
                            .buttonStyle(PressStyle())
                            .disabled(loading)
                            .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 16)
                        }
                        if hasCurrentOwner && visibleItems.isEmpty && !loading && error == nil {
                            if currentItems.isEmpty {
                                ListRoomEmpty(glyph: .priceBook, title: "No price book items",
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
                // A list that failed (offline, a server error) reads again after an answered check;
                // a loaded list stays as it is.
                .onChange(of: session.verificationRevision) { _, _ in
                    if hasCurrentOwner, items.isEmpty, error != nil { Task { await refresh() } }
                }
                .safeAreaInset(edge: .bottom) {
                    if canEdit {
                        // Paper 34: the brand pill, 50 tall, 16 from the edges.
                        Button { creating = true } label: {
                            PaperPillLabel(title: "Add price book item", height: 50)
                        }
                        .buttonStyle(PressStyle())
                        .paperActionBarGround(Theme.canvas)
                    }
                }
                #if DEBUG
                .task { if PaperPreview.opensSheet("price-book-new"), canEdit { creating = true } }
                .toolbar {
                    if ProcessInfo.processInfo.arguments.contains("--paper-preview-pricebook-authority") {
                        ThorbisToolbarItem(placement: .topBarTrailing) {
                            Button("Change sample access shortly") {
                                Task { @MainActor in
                                    if ProcessInfo.processInfo.arguments.contains("--paper-preview-pricebook-from-detail") {
                                        // Count from the open item, as CustomerJobDocumentBook does from an open
                                        // Description: on a slow simulator the tap that opens it can't use up the delay.
                                        for _ in 0..<600 where !PaperPreview.priceBookDetailOpened {
                                            try? await Task.sleep(for: .milliseconds(100))
                                        }
                                    }
                                    try? await Task.sleep(for: .seconds(5))
                                    guard !Task.isCancelled else { return }
                                    if ProcessInfo.processInfo.arguments.contains("--paper-preview-pricebook-switch") {
                                        PaperPreviewProtocol.switchSavedWorkWorkspace()
                                    } else if ProcessInfo.processInfo.arguments.contains("--paper-preview-pricebook-renew") {
                                        // Renewed authority: a real change with the same access. An identical
                                        // answer would leave the list as it is.
                                        PaperPreviewProtocol.reviseSampleAuthority()
                                    } else if !ProcessInfo.processInfo.arguments.contains("--paper-preview-pricebook-recheck") {
                                        PaperPreviewProtocol.revokePriceBookView()
                                    }
                                    // `-recheck`: the server answers exactly what the session holds.
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

    /// Paper 34's first segment: "All" with the number of items on the phone.
    private var allLabel: String { "All · \(currentItems.count)" }

    /// The segments choose the kind; choosing one opens its group if it was folded.
    private var categorySelection: Binding<String> {
        Binding(get: { category == "All" ? allLabel : category },
                set: { option in
                    let chosen = option == allLabel ? "All" : option
                    category = chosen
                    if chosen == "All" { collapsedGroups.removeAll() } else { collapsedGroups.remove(chosen) }
                })
    }

    /// Paper 34: the search field on the card (46 tall, radius 14), under the title. It narrows the
    /// items already on the phone, so it says what it searches.
    private var searchBar: some View {
        HStack(spacing: 8) {
            PaperIcon(.search, size: 18, color: Theme.muted).accessibilityHidden(true)
            TextField("Search price book", text: $search, prompt: .placeholder("Search or ask"))
                .font(Theme.font(16)).foregroundStyle(Theme.foreground)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search)
                .frame(minHeight: 46)
                .accessibilityIdentifier("price-book-list-search")
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                        .frame(width: 32, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Clear search")
            }
            // Paper 34: the 40pt filter circle at the field's trailing edge chooses the kind, the
            // same choice the segments under it make.
            if categories.count > 1 {
                ThorbisMenu(items: categories.map { name in
                    ThorbisMenuItem(name == "All" ? "All items" : name, isSelected: category == name) {
                        category = name
                        if name == "All" { collapsedGroups.removeAll() } else { collapsedGroups.remove(name) }
                    }
                }, title: "Show", accessibilityLabel: "Filter by kind") {
                    PaperFilterCircle(active: category != "All")
                }
            }
        }
        .padding(.leading, 12).padding(.trailing, 4)
        .frame(minHeight: 46)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, PaperCardMetrics.margin)
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
                        Text(unit).font(Theme.font(14)).foregroundStyle(Theme.muted)
                    }
                    itemPrice(item).fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 11)
            } else {
                let details = PriceBookPresentation.supportingDetails(item.description)
                PaperListRow(title: PriceBookPresentation.title(item.description),
                             subtitle: details ?? unit,
                             meta: details == nil ? nil : unit,
                             subtitleLines: 2,
                             limitsSubtitleAtAccessibility: true) {
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
            .font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
            .lineLimit(showFullDescription || dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Paper 34: the price in 16 Medium, tabular.
    private func itemPrice(_ item: PriceBookListItem) -> some View {
        Text(money(item.sellPrice.amount, currency: item.sellPrice.currency))
            .font(Theme.monoFont(16, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
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
            // A short read-only sheet: the shared sheet title row, Done on the close circle.
            .safeAreaInset(edge: .top, spacing: 0) {
                ThorbisSheetHeader(title: "Price book item", closeLabel: "Done", onClose: { dismiss() }).background(Theme.canvas)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        #if DEBUG
        // `--paper-preview-pricebook-from-detail` counts the sample access change from here.
        .task { PaperPreview.priceBookDetailOpened = true }
        #endif
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
    /// Problems shown under their fields after the commit is pressed (design.thorbis.com Forms:
    /// validate on commit). Each clears as soon as its field changes.
    @State private var nameProblem: String?
    @State private var priceProblem: String?
    @State private var unitProblem: String?
    @FocusState private var focus: Field?
    private enum Field: Hashable { case name, price, unit }

    var body: some View {
        VStack(spacing: 0) {
            // Paper 34A: Cancel pill, the centred title and the brand Save pill in one row; then the
            // name on its own card, price, unit and Taxable on one card, the kind on another, and
            // what a change does under them.
            // Never pre-disabled: pressed with something missing, it says what under the field.
            ThorbisSheetHeader(title: existing == nil ? "New price book item" : "Edit item",
                               closeLabel: "Cancel", onClose: { if !busy { dismiss() } },
                               closeStyle: .headerPill,
                               trailing: ThorbisSheetHeaderAction(title: existing == nil ? "Add" : "Save", busy: busy,
                                                                  identifier: "price-book-item-commit") {
                                   if valid { Task { await save() } } else { showProblems() }
                               })
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Name").font(Theme.font(13)).foregroundStyle(Theme.muted)
                                .accessibilityHidden(true)
                            TextField("Replace capacitor", text: $content.description, prompt: .placeholder("Replace capacitor"), axis: .vertical).lineLimit(1...3)
                                .font(Theme.font(17, weight: .medium))
                                .focused($focus, equals: .name)
                                .accessibilityLabel("Name customers see")
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                        if let nameProblem { FieldProblem(message: nameProblem).padding(.horizontal, 4) }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        VStack(spacing: 0) {
                            editorRow("Price") {
                                TextField("0.00", text: $priceText, prompt: .placeholder("0.00")).keyboardType(.decimalPad)
                                    .font(Theme.font(16, weight: .semibold)).monospacedDigit()
                                    .multilineTextAlignment(.trailing)
                                    .focused($focus, equals: .price)
                                    .accessibilityLabel("Price")
                            }
                            editorRow("Unit") {
                                TextField("each, hour, foot…", text: $content.unit, prompt: .placeholder("each, hour, foot…"))
                                    .font(Theme.font(16)).multilineTextAlignment(.trailing)
                                    .focused($focus, equals: .unit)
                                    .accessibilityLabel("Unit")
                            }
                            .overlay(alignment: .top) { WellDivider(leading: 0) }
                            // Paper 34A: Taxable is a switch, on in the brand blue.
                            Toggle(isOn: taxable) {
                                Text("Taxable").font(Theme.font(16)).foregroundStyle(Theme.foreground)
                            }
                            .tint(Theme.brand)
                            .frame(minHeight: 56)
                            .overlay(alignment: .top) { WellDivider(leading: 0) }
                            .accessibilityIdentifier("price-book-item-taxable")
                        }
                        .padding(.horizontal, 16)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                        if let priceProblem { FieldProblem(message: priceProblem).padding(.horizontal, 4) }
                        if let unitProblem { FieldProblem(message: unitProblem).padding(.horizontal, 4) }
                    }
                    ThorbisSelect(options: PriceBookContent.kinds.map { ($0, $0.capitalized) },
                                  selection: $content.kind, label: "Kind")
                        .frame(minHeight: 56)
                        .padding(.horizontal, 16)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    Text("Changes apply to new estimates and invoices. Ones already sent keep their price.")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                    if let error { ListErrorRow(message: error) }
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 14).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.canvas)
        .paperPageGround()
        .onChange(of: content.description) { _, _ in nameProblem = nil }
        .onChange(of: priceText) { _, _ in priceProblem = nil }
        .onChange(of: content.unit) { _, _ in unitProblem = nil }
        .onAppear {
            guard let existing, content.description.isEmpty else { return }
            let r = existing.revision
            content = PriceBookContent(description: r.description, unit: r.unit, sellPrice: r.sellPrice,
                                       taxClassification: r.taxClassification, kind: r.kind)
            priceText = paymentAmountText(r.sellPrice.amount)
        }
        #if DEBUG
        // `--paper-preview-form-errors`: the commit pressed with the form blank, so the errors show.
        .task {
            guard PaperPreview.enabled, ProcessInfo.processInfo.arguments.contains("--paper-preview-form-errors") else { return }
            try? await Task.sleep(for: .milliseconds(600))
            showProblems()
        }
        #endif
    }

    /// On means "taxable"; turning it off writes the server's "non_taxable".
    private var taxable: Binding<Bool> {
        Binding(get: { content.taxClassification == "taxable" },
                set: { content.taxClassification = $0 ? "taxable" : "non_taxable" })
    }

    /// One row of a Paper 34A card: the label on the left (16), the answer on the right.
    private func editorRow<Field: View>(_ label: String, @ViewBuilder field: () -> Field) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label).font(Theme.font(16)).foregroundStyle(Theme.foreground)
                .accessibilityHidden(true)
            field()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minHeight: 56)
    }

    /// Says what's missing under each field, and moves to the first one.
    private func showProblems() {
        nameProblem = content.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Add the name customers see, like \u{201C}Replace capacitor.\u{201D}" : nil
        let price = priceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if price.isEmpty {
            priceProblem = "Add a price, like 125.00."
        } else if MoneyInput.cents(price, maximumCents: .max) != nil, cents == nil {
            priceProblem = "Keep the price to $1,000,000.00 or less."
        } else {
            priceProblem = cents == nil ? "Enter the price in dollars, like 125.00." : nil
        }
        unitProblem = content.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Add a unit, like each or hour." : nil
        if nameProblem != nil { focus = .name } else if priceProblem != nil { focus = .price } else if unitProblem != nil { focus = .unit }
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

