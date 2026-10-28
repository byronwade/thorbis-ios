import SwiftUI

/// Web Properties (apps/web properties.tsx): every service and billing address across customers.
/// There is no locations collection on the server, so like the web page this is the union of
/// `GET /v1/customers/{id}/locations` for a bounded set of customers, and it says when it is capped.
struct PropertyRow: Identifiable, Hashable {
    let location: ServiceLocationRecord
    let customer: Customer
    var id: String { location.id }

    var kindLabel: String { location.kind == "billing" ? "Billing" : "Service" }

    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return [location.address, location.label, customer.name].contains { $0.localizedCaseInsensitiveContains(needle) }
    }
}

enum PropertiesUnion {
    /// Same request budget as the web page (PROPERTY_UNION_CUSTOMER_CAP).
    static let customerCap = 50

    static func customers(from all: [Customer]) -> (included: [Customer], capped: Bool) {
        let active = all.filter { $0.archived != true }
        return (Array(active.prefix(customerCap)), active.count > customerCap)
    }

    static func rows(_ pairs: [(Customer, [ServiceLocationRecord])]) -> [PropertyRow] {
        pairs.flatMap { customer, locations in locations.map { PropertyRow(location: $0, customer: customer) } }
            .sorted { lhs, rhs in
                lhs.location.address.localizedCaseInsensitiveCompare(rhs.location.address) == .orderedAscending
            }
    }
}

struct PropertiesView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @State private var rows: [PropertyRow] = []
    @State private var loaded = false
    @State private var capped = false
    @State private var failedCustomers = 0
    @State private var error: String?
    @State private var query = ""

    var body: some View {
        let shown = rows.filter { $0.matches(query) }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Properties").font(Theme.font(30, weight: .medium)).tracking(-0.6).accessibilityAddTraits(.isHeader)
                    Text(loaded ? (rows.count == 1 ? "1 address" : "\(rows.count) addresses") : "Every service address, across customers")
                        .font(Theme.font(15)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, Theme.gutter).padding(.bottom, 12)
                if let error { ErrorBanner(message: error) { await load() } }
                if !loaded && error == nil && rows.isEmpty { SkeletonRows(count: 6, leading: true) }
                if loaded && rows.isEmpty && error == nil {
                    PaperEmptyState(symbol: "house", title: "No properties yet",
                                    message: "Service addresses added on a customer show here, across your whole book.")
                } else if loaded && shown.isEmpty {
                    PaperEmptyState(symbol: "magnifyingglass", title: "No matches",
                                    message: "No address, place name or customer matches “\(query)”.",
                                    actionTitle: "Clear search") { query = "" }
                }
                ForEach(shown) { row in
                    NavigationLink(value: row.customer) {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: row.location.kind == "billing" ? "envelope" : "house")
                                .font(.system(size: 17)).foregroundStyle(Theme.markOlive)
                                .frame(width: 22).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.location.address).font(Theme.font(15, weight: .medium)).lineLimit(2)
                                Text([row.customer.name, row.location.label, row.kindLabel]
                                    .filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(Theme.font(13)).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            PaperDisclosure()
                        }
                        .padding(.horizontal, Theme.gutter).padding(.vertical, 10)
                        .frame(minHeight: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityElement(children: .combine)
                    Divider().padding(.leading, Theme.gutter + 36)
                }
                if loaded && (capped || failedCustomers > 0) {
                    Text(footnote)
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, Theme.gutter).padding(.top, 16)
                }
            }
            .padding(.bottom, 24)
        }
        .searchable(text: $query, prompt: "Address, place or customer")
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            if store.customers.isEmpty || store.error != nil { _ = await store.refresh(api) }
            await load()
        }
        // Runs again when the customer list arrives or changes, so opening this before it loads is fine.
        .task(id: store.customers.map(\.id).joined(separator: ",") + (store.loading ? "+loading" : "")) { await load() }
    }

    private var footnote: String {
        var parts: [String] = []
        if capped { parts.append("Showing addresses for the first \(PropertiesUnion.customerCap) customers. Search a customer to see the rest.") }
        if failedCustomers > 0 { parts.append(failedCustomers == 1 ? "1 customer’s addresses did not load. Pull to try again." : "\(failedCustomers) customers’ addresses did not load. Pull to try again.") }
        return parts.joined(separator: " ")
    }

    private func load() async {
        let generation = session.generation
        if store.customers.isEmpty {
            // Not loaded yet, or the customer list failed: never call that "no properties".
            if store.loading { return }
            if let storeError = store.error { error = storeError; return }
        }
        let (customers, isCapped) = PropertiesUnion.customers(from: store.customers)
        var pairs: [(Customer, [ServiceLocationRecord])] = []
        var failures = 0
        var lastError: Error?
        // One customer at a time, like the web page's bounded fan-out; the list fills as it goes.
        for (index, customer) in customers.enumerated() {
            do {
                pairs.append((customer, try await api.fieldLocations(customer.id)))
            } catch is CancellationError {
                return
            } catch {
                failures += 1
                lastError = error
            }
            guard session.generation == generation, !Task.isCancelled else { return }
            if index % 8 == 7, !loaded { rows = PropertiesUnion.rows(pairs) }
        }
        rows = PropertiesUnion.rows(pairs)
        capped = isCapped
        failedCustomers = failures
        loaded = true
        error = (pairs.isEmpty && failures > 0) ? lastError?.localizedDescription : nil
    }
}
