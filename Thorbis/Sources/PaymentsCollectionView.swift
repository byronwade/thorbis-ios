import SwiftUI

/// Online-only ledger. The scope is checked in rendering as well as on every network response,
/// so rows disappear immediately when the actor, workspace or authority changes.
struct PaymentsCollectionView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var loadedScope: ScopedRecordFavorites.Scope?
    @State private var items: [PaymentsCollectionItem] = []
    @State private var nextCursor: String?
    @State private var loading = false
    @State private var error: String?
    @State private var needsRefresh = false
    @State private var request = UUID()

    private var scope: ScopedRecordFavorites.Scope? {
        guard session.can("invoice.view", feature: "invoicing"),
              session.can("invoice.view", feature: "payments"), !session.isOffline else { return nil }
        return ScopedRecordFavorites.currentScope(session: session, api: api)
    }
    private var visible: Bool { scope != nil && scope == loadedScope }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                PaperHeader(title: "Payments", subtitle: "Recorded customer payments")
                    .environment(\.paperMenuButton, false)
                if scope == nil {
                    ContentUnavailableView(session.isOffline ? "Connect to see payments" : "Payments unavailable",
                        systemImage: session.isOffline ? "wifi.slash" : "lock",
                        description: Text(session.isOffline ? "Payment history needs a connection." : "Your current access does not include payments."))
                } else if visible {
                    if let error { ErrorBanner(message: error) { await loadMore(reset: items.isEmpty || needsRefresh) } }
                    if loading && items.isEmpty { ListRoomSkeleton(count: 5, threeLines: false) }
                    if !loading && items.isEmpty && error == nil {
                        ListRoomEmpty(title: "No payments to show.", message: "Payments available to you will appear here.")
                    }
                    ForEach(items) { item in
                        if let loadedScope {
                            NavigationLink {
                                InvoiceDetailView(id: item.invoiceID, paymentsScope: loadedScope).thorbisBackButton()
                            } label: { PaymentsCollectionRow(item: item) }
                            .buttonStyle(RowPressStyle())
                        }
                    }
                    if nextCursor != nil {
                        Button(loading ? "Loading…" : "Load more payments") { Task { await loadMore(reset: false) } }
                            .disabled(loading).frame(maxWidth: .infinity, minHeight: 48)
                    }
                } else { ListRoomSkeleton(count: 5, threeLines: false) }
            }.padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .task(id: scope) { await loadMore(reset: true) }
        .refreshable { await loadMore(reset: true) }
    }

    private func loadMore(reset: Bool) async {
        guard let current = scope else { items = []; loadedScope = nil; request = UUID(); return }
        if !reset && (loading || nextCursor == nil || loadedScope != current) { return }
        let token = UUID(); request = token
        if reset { items = []; nextCursor = nil; loadedScope = current; needsRefresh = false }
        loading = true; error = nil
        let cursor = reset ? nil : nextCursor
        do {
            let page = try await api.paymentsCollectionPage(cursor: cursor) {
                scope == current && request == token
            }
            guard scope == current, request == token, !Task.isCancelled else { return }
            let ids = Set(items.map { $0.id.lowercased() })
            guard page.items.allSatisfy({ !ids.contains($0.id.lowercased()) }) else {
                needsRefresh = true
                throw Problem(title: "Payments changed", status: nil, detail: "Refresh the list to see the latest payments.")
            }
            items.append(contentsOf: page.items); nextCursor = page.nextCursor; loading = false
        } catch is CancellationError { }
        catch {
            guard scope == current, request == token, !Task.isCancelled else { return }
            self.error = needsRefresh ? "Payments changed. Refresh the list to see the latest payments." : "Payments couldn't be loaded. Check your connection and try again."
            loading = false
        }
    }
}

struct PaymentsCollectionRow: View {
    let item: PaymentsCollectionItem
    private var method: String {
        switch item.method { case .card: "Card"; case .ach: "Bank transfer"; case .cash: "Cash"; case .check: "Check"; case .financing: "Financing" }
    }
    var statusLabel: String {
        if item.status == .refunded { return "Refunded" }
        if item.refundedAmount > 0 { return "Partially refunded" }
        return "Recorded"
    }
    private var date: String {
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        guard let value = fractional.date(from: item.recordedAt) ?? plain.date(from: item.recordedAt) else { return item.recordedAt }
        return value.formatted(date: .abbreviated, time: .omitted)
    }
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: item.method == .cash ? "banknote" : "creditcard")
                .foregroundStyle(Theme.markForest).frame(width: 38, height: 38)
                .background(Theme.markForest.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(method).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                Text("\(date) · \(statusLabel)")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                Text("Invoice \(item.invoiceID.uppercased())")
                    .font(Theme.font(12)).foregroundStyle(Theme.muted)
                if item.refundedAmount > 0 {
                    Text("Original \(money(item.amount, currency: "USD")) · Refunded \(money(item.refundedAmount, currency: "USD"))")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(money(item.netAmount, currency: "USD")).font(Theme.font(16, weight: .medium))
                if item.refundedAmount > 0 { Text("Net").font(Theme.font(12)).foregroundStyle(Theme.muted) }
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, Theme.gutter).padding(.vertical, 14).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
