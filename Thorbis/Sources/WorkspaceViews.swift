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

    var body: some View {
        Group {
            if !available {
                ContentUnavailableView("Notices unavailable", systemImage: "bell.slash",
                                       description: Text("This account cannot view job notices."))
            } else {
                List {
                    if let error { Text(error).foregroundStyle(.red) }
                    if unreadState == .unknown {
                        Text("Unread status is still being checked.").font(.footnote).foregroundStyle(.secondary)
                    }
                    if unreadState == .present || readCursor != nil {
                        Button(readCursor == nil ? "Mark unread batch as read" : "Continue marking read") {
                            Task { await markReadBatch() }
                        }
                        .disabled(loading)
                    }
                    ForEach(items) { notice in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(notice.title).font(.headline)
                            Text(notice.meta).font(.subheadline)
                            Text(notice.at).font(.caption).foregroundStyle(.secondary)
                            if !notice.read { Text("Unread").font(.caption).bold() }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if nextCursor != nil {
                        Button("Load more notices") { Task { await loadMore() } }
                            .disabled(loading)
                    }
                }
                .overlay {
                    if items.isEmpty && !loading && error == nil {
                        ContentUnavailableView("No notices", systemImage: "bell")
                    }
                }
                .refreshable { await refresh() }
                .task { await refresh() }
            }
        }
        .navigationTitle("Staff notices")
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

    var body: some View {
        Group {
            if !available {
                ContentUnavailableView("Revenue unavailable", systemImage: "chart.bar.xaxis",
                                       description: Text("This account cannot view invoice reports."))
            } else {
                List {
                    if let error { Text(error).foregroundStyle(.red) }
                    if let report {
                        if report.truncated {
                            Section {
                                Text("The server reached its report scan limit. Its totals understate the full ledger, so this view does not show them as final values.")
                            } header: { Text("Incomplete report") }
                        } else {
                            Section("Receivables") {
                                LabeledContent("Open invoices", value: String(report.receivable.openInvoices))
                                LabeledContent("Balance", value: money(report.receivable.balance, currency: "USD"))
                                LabeledContent("Overdue invoices", value: String(report.receivable.overdueInvoices))
                                LabeledContent("Overdue balance", value: money(report.receivable.overdueBalance, currency: "USD"))
                            }
                            Section("UTC months") {
                                ForEach(report.months) { month in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(month.month).font(.headline)
                                        Text("Issued revenue: \(money(month.revenue, currency: "USD"))")
                                        Text("Collected: \(money(month.collected, currency: "USD"))")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        Section { Text("Live server report · version \(report.reportVersion) · \(report.generatedAt)")
                            .font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                .refreshable { await load() }
                .task { await load() }
            }
        }
        .navigationTitle("Revenue")
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
                HStack(alignment: .top, spacing: 12) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.foreground)
                            .frame(width: 36, height: 36)
                            .background(Theme.fill, in: Circle())
                    }
                    .accessibilityLabel("Back to More")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Price book").font(Theme.font(28, weight: .bold)).foregroundStyle(Theme.foreground)
                        Text(nextCursor == nil ? "\(items.count) items · Company operations"
                            : "\(items.count) items loaded · Company operations")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                    Text(initials(session.user?.name ?? session.user?.email ?? ""))
                        .font(Theme.font(12, weight: .semibold)).foregroundStyle(Theme.brand)
                        .frame(width: 36, height: 36)
                        .background(Theme.brandSurface, in: Circle())
                }
                .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 12)
                PaperSearchField(text: $search, prompt: nextCursor == nil ? "Search \(items.count) items" : "Search loaded items")
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(categories, id: \.self) { option in
                            Button { category = option } label: {
                                Text(option == "All" ? "All · \(items.count)" : option)
                                    .font(Theme.font(14, weight: category == option ? .semibold : .medium))
                                    .foregroundStyle(category == option ? Theme.foreground : Theme.muted)
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(category == option ? Theme.fill : .clear, in: Capsule())
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
                                                WorkspacePriceBookDetailView(api: api, id: item.id)
                                            } label: { row(item) }
                                            .buttonStyle(.plain)
                                        } else { row(item) }
                                        if item.id != grouped.last?.id {
                                            Rectangle().fill(Theme.border).frame(height: 1)
                                        }
                                    }
                                }
                                .padding(.horizontal, 14)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        if nextCursor != nil {
                            Button("Load more items") { Task { await loadMore() } }
                                .font(Theme.font(14, weight: .medium))
                                .frame(maxWidth: .infinity).frame(height: 42)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                                .disabled(loading)
                        }
                        if visibleItems.isEmpty && !loading && error == nil {
                            ContentUnavailableView(items.isEmpty ? "No Price Book items" : "No matching items",
                                systemImage: "book.closed")
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 100)
                }
                .refreshable { await refresh() }
                .task { await refresh() }
            }
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func row(_ item: PriceBookListItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.description).font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.foreground)
                Text("\(item.kind.capitalized) · \(item.unit)")
                    .font(Theme.font(12)).foregroundStyle(Theme.muted)
                if item.archivedAt != nil { Text("Archived").font(Theme.font(11)).foregroundStyle(Theme.warning) }
            }
            Spacer(minLength: 6)
            Text(money(item.sellPrice.amount, currency: item.sellPrice.currency))
                .font(Theme.monoFont(13, weight: .medium)).foregroundStyle(Theme.foreground)
        }
        .frame(minHeight: 62)
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
    @State private var detail: PriceBookDetail?
    @State private var error: String?

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            if let detail {
                LabeledContent("Unit", value: detail.revision.unit)
                LabeledContent("Kind", value: detail.revision.kind.capitalized)
                LabeledContent("Price", value: money(detail.revision.sellPrice.amount,
                                                       currency: detail.revision.sellPrice.currency))
                LabeledContent("Tax", value: detail.revision.taxClassification.replacingOccurrences(of: "_", with: " ").capitalized)
                LabeledContent("Revision", value: String(detail.revision.revision))
                LabeledContent("Status", value: detail.item.status.capitalized)
            }
        }
        .navigationTitle(detail?.revision.description ?? "Price Book item")
        .toolbar(.visible, for: .navigationBar)
        .task {
            do { detail = try await api.priceBookItem(id); error = nil }
            catch { self.error = error.localizedDescription }
        }
    }
}
