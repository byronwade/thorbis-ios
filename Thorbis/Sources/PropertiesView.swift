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
    @State private var opened: PropertyRow?
    /// Paper 87A's segments: All, With open work, Commercial.
    @State private var filter = PropertiesView.allFilter
    /// Customers the server marks commercial, and how many pieces of equipment sit at each
    /// address. Both fill in after the list; either stays empty when this person can't read it.
    @State private var commercialIDs: Set<String> = []
    @State private var units: [String: Int] = [:]

    private static let allFilter = "All"
    private static let openFilter = "With open work"
    private static let commercialFilter = "Commercial"

    /// Addresses with a job that is not finished or cancelled.
    private var openLocations: Set<String> {
        Set(store.jobs.filter { !["completed", "canceled"].contains($0.status) }.compactMap(\.locationId))
    }

    private func passes(_ row: PropertyRow, open: Set<String>) -> Bool {
        if filter == PropertiesView.openFilter { return open.contains(row.location.id) }
        if filter == PropertiesView.commercialFilter { return commercialIDs.contains(row.customer.id) }
        return true
    }

    /// "Marlowe · 2 units · gate code on file": whose it is, what is installed there, and the
    /// first thing a tech should know at the door.
    private func subtitle(_ row: PropertyRow) -> String {
        var parts: [String] = [row.customer.name]
        if row.location.kind == "billing" { parts.append("Billing") }
        if let count = units[row.location.id], count > 0 { parts.append(count == 1 ? "1 unit" : "\(count) units") }
        parts.append(accessHint(row.location))
        return parts.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }

    private func accessHint(_ location: ServiceLocationRecord) -> String {
        if let gate = location.gateCode, !gate.isEmpty { return "gate code on file" }
        if let dogs = location.dogOnSite, !dogs.isEmpty { return "dog on site" }
        if let parking = location.parking, !parking.isEmpty { return parking }
        if let notes = location.notes, !notes.isEmpty { return notes }
        return "no notes"
    }

    /// The address search on the card (46 tall, radius 14); it narrows this list.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.muted).accessibilityHidden(true)
            TextField("", text: $query, prompt: .placeholder("Address, place or customer"))
                .font(Theme.font(16)).foregroundStyle(Theme.foreground)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .frame(minHeight: 46)
                .accessibilityLabel("Search properties")
                .accessibilityIdentifier("properties-search")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                        .frame(width: 32, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 46)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, PaperCardMetrics.margin)
    }

    /// One card of addresses: the address (16 Medium) over whose it is (14 muted), "Open job" in
    /// the warning ink trailing when work is open there.
    private func addressSection(_ title: String, _ list: [PropertyRow], open: Set<String>) -> some View {
        PaperSection(title, count: list.count) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(list) { row in
                    if row.id != list.first?.id { WellDivider() }
                    // Web parity: a property opens its own page (property-detail.tsx), not the customer.
                    Button { opened = row } label: {
                        PaperListRow(title: row.location.address, subtitle: subtitle(row), subtitleLines: 2) {
                            if open.contains(row.location.id) {
                                Text("Open job").font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.warning).fixedSize()
                            }
                        }
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Opens the property")
                }
            }
        }
        .paperCardMargin().padding(.top, 8)
    }

    var body: some View {
        let open = openLocations
        let shown = rows.filter { $0.matches(query) && passes($0, open: open) }
        let commercial = shown.filter { commercialIDs.contains($0.customer.id) }
        let others = shown.filter { !commercialIDs.contains($0.customer.id) }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Paper 87A: the place header, then the addresses on one card 16 from the edges.
                PaperHeader(title: "Properties",
                            subtitle: loaded ? (rows.count == 1 ? "1 address" : "\(rows.count) addresses") : "Every service address, across customers")
                // Paper 87A: the search on the card, then All / With open work / Commercial.
                searchField.padding(.top, 14)
                ThorbisSegmented(options: [(PropertiesView.allFilter, PropertiesView.allFilter),
                                           (PropertiesView.openFilter, PropertiesView.openFilter),
                                           (PropertiesView.commercialFilter, PropertiesView.commercialFilter)],
                                 selection: $filter)
                    .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 12)
                if let error { ErrorBanner(message: error) { await load() } }
                if !loaded && error == nil && rows.isEmpty { SkeletonRows(count: 6, leading: true) }
                if loaded && rows.isEmpty && error == nil {
                    PaperEmptyState(symbol: "house", title: "No properties yet",
                                    message: "Service addresses added on a customer show here, across your whole book.")
                } else if loaded && shown.isEmpty && !query.isEmpty {
                    PaperEmptyState(symbol: "magnifyingglass", title: "No matches",
                                    message: "No address, place name or customer matches “\(query)”.",
                                    actionTitle: "Clear search") { query = "" }
                } else if loaded && shown.isEmpty {
                    PaperEmptyState(symbol: "house",
                                    title: filter == PropertiesView.openFilter ? "No open work" : "No commercial addresses",
                                    message: filter == PropertiesView.openFilter
                                        ? "Addresses with a job that isn’t finished show here."
                                        : "Addresses of customers marked commercial show here.",
                                    actionTitle: "Show all") { filter = PropertiesView.allFilter }
                }
                // Paper 87A: the addresses on a card, commercial places on their own under them.
                if !others.isEmpty {
                    addressSection(query.isEmpty ? "Addresses" : "Matches", others, open: open)
                }
                if !commercial.isEmpty {
                    addressSection("Commercial", commercial, open: open)
                }
                if loaded && (capped || failedCustomers > 0) {
                    Text(footnote)
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.gutter).padding(.top, 16)
                }
            }
            .padding(.bottom, 24)
        }
        .thorbisDestination(item: $opened) { PropertyDetailView(row: $0) }
        .scrollDismissesKeyboard(.interactively)
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
        #if DEBUG
        // `--paper-preview-screen property-detail`: open the first property once the list has loaded.
        if PaperPreview.enabled, PaperPreview.screen == "property-detail", opened == nil { opened = rows.first }
        #endif
        capped = isCapped
        failedCustomers = failures
        loaded = true
        error = (pairs.isEmpty && failures > 0) ? lastError?.localizedDescription : nil
        // Who is commercial, and what is installed where: one read each, after the list shows.
        if let records = try? await api.fieldCustomers() {
            guard session.generation == generation, !Task.isCancelled else { return }
            commercialIDs = Set(records.filter { $0.accountType == "commercial" }.map(\.id))
        }
        if let equipment = try? await api.allEquipment() {
            guard session.generation == generation, !Task.isCancelled else { return }
            var counts: [String: Int] = [:]
            for item in equipment {
                if let place = item.locationId { counts[place, default: 0] += 1 }
            }
            units = counts
        }
    }
}


/// One "Access" fact on a property page.
private struct PropertyFact: Identifiable {
    let label: String
    let value: String?
    var id: String { label }
}

/// Web parity (property-detail.tsx): one address on its own. What kind of place it is and whose,
/// the facts a tech needs at the door, who to reach, the equipment on site and the jobs booked there.
/// Paper 87: Directions on the place card, Edit beside Access, Call and Text on each contact,
/// open work apart from past jobs, and New job here as the page's one commit.
struct PropertyDetailView: View {
    let row: PropertyRow
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @Environment(\.openURL) private var openURL
    @Environment(\.inboxText) private var inboxText
    @State private var openCustomer: Customer?
    /// The place as last saved from Edit; nil until it is edited here.
    @State private var saved: ServiceLocationRecord?
    @State private var editing = false
    @State private var showNewJob = false
    @State private var contacts: [CustomerContactRecord] = []

    private var location: ServiceLocationRecord { saved ?? row.location }
    private var canEdit: Bool { session.can("customer.edit", feature: "core_crm") }
    private var canCreateJob: Bool { session.can("job.create", feature: "jobs") }
    private var mapsURL: URL? { Directions.url(address: location.address, coordinates: location.coordinates) }
    private var openJobs: [Job] { jobs.filter { !["completed", "canceled"].contains($0.status) } }
    private var pastJobs: [Job] { jobs.filter { ["completed", "canceled"].contains($0.status) } }
    private var jobs: [Job] {
        store.jobs.filter { $0.locationId == location.id }
            .sorted { (JobFiltering.date($0.scheduledFor) ?? .distantPast) > (JobFiltering.date($1.scheduledFor) ?? .distantPast) }
    }
    /// Paper 87 "Access": what a tech needs at the door, each fact as a label and value.
    private var facts: [PropertyFact] {
        let all = [PropertyFact(label: "Gate code", value: location.gateCode), PropertyFact(label: "Alarm", value: location.alarmCode),
                   PropertyFact(label: "Pets", value: location.dogOnSite), PropertyFact(label: "Parking", value: location.parking),
                   PropertyFact(label: "Notes", value: location.notes)]
        return all.filter { !($0.value ?? "").isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Paper 87: the address as the 34 Bold title, then the place and whose it is.
                VStack(alignment: .leading, spacing: 4) {
                    Text(location.address).font(Theme.font(34, weight: .bold)).tracking(-0.85)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Button { openCustomer = row.customer } label: {
                        HStack(spacing: 4) {
                            Text([location.label, row.kindLabel, row.customer.name].filter { !$0.isEmpty }
                                    .joined(separator: " \u{00B7} "))
                                .fixedSize(horizontal: false, vertical: true)
                            Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .medium)).accessibilityHidden(true)
                        }
                        .font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Customer, \(row.customer.name)")
                    .accessibilityHint("Opens the customer")
                }
                .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
                if let mapsURL { placeCard(mapsURL) }
                if !facts.isEmpty || canEdit {
                    PaperSection(title: "Access") {
                        if facts.isEmpty {
                            Text("No gate code or access notes yet.").font(Theme.font(15)).foregroundStyle(Theme.muted)
                                .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 14)
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(facts) { fact in
                                    if fact.id != facts.first?.id { WellDivider() }
                                    PaperDetailRow(label: fact.label) { Text(fact.value ?? "") }
                                        .padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 52)
                                }
                            }
                        }
                    } accessory: {
                        // Paper 87: "Edit" in the brand ink beside the section label.
                        if canEdit {
                            Button { editing = true } label: {
                                Text("Edit").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.brandText)
                                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing).contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityLabel("Edit property")
                            .accessibilityIdentifier("property-edit")
                        }
                    }
                }
                if !contacts.isEmpty {
                    PaperSection("Contacts", count: contacts.count) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(contacts) { contact in
                                if contact.id != contacts.first?.id { WellDivider() }
                                contactRow(contact)
                            }
                        }
                    }
                }
                CustomerEquipmentSection(customerID: row.customer.id, locations: [location],
                                         onlyLocationID: location.id, editable: false)
                if !openJobs.isEmpty { jobsSection("Open work", openJobs) }
                if !pastJobs.isEmpty { jobsSection("Past jobs", pastJobs) }
                if jobs.isEmpty {
                    PaperSection("Open work") {
                        Text("No jobs at this address yet.").font(Theme.font(15)).foregroundStyle(Theme.muted)
                            .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 14)
                    }
                }
                if canCreateJob {
                    Button { showNewJob = true } label: { Text("New job here").inkCommit() }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("property-new-job")
                }
            }
            .paperCardMargin().padding(.top, 8).padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ThorbisToolbarItem(placement: .topBarTrailing) {
                ThorbisMenu(items: menuItems, accessibilityLabel: "Property actions") {
                    PaperCircleLabel(symbol: "ellipsis", size: 44, fill: Theme.card)
                }
            }
        }
        .task(id: row.customer.id) {
            guard session.can("customer.view", feature: "core_crm") else { return }
            if let loaded = try? await api.fieldContacts(row.customer.id) { contacts = loaded }
        }
        .sheet(isPresented: $editing) { SheetSurface {
            ServiceLocationSheet(customerID: row.customer.id, location: location) { record in saved = record }
        } }
        .sheet(isPresented: $showNewJob) { SheetSurface { NewJobSheet(preselected: row.customer, locationID: location.id) } }
        .thorbisDestination(item: $openCustomer) { CustomerDetailView(customer: $0) }
    }

    /// Paper 87: the place card (140 tall, radius 20) with Directions on a brand-surface pill.
    private func placeCard(_ url: URL) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "mappin.and.ellipse").font(.system(size: 26, weight: .regular))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
            Button { openURL(url) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold))
                    Text("Directions").font(Theme.font(14, weight: .semibold))
                }
                .foregroundStyle(Theme.brandText)
                .padding(.leading, 12).padding(.trailing, 14).frame(minHeight: 44)
                .background(Theme.brandSurface, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .accessibilityHint("Opens Maps")
            .accessibilityIdentifier("property-directions")
            .padding(12)
        }
        .frame(maxWidth: .infinity).frame(height: 140)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    /// Paper 87 "Contacts": the name over the role, then Call and Text on quiet 58 × 44 pills.
    private func contactRow(_ contact: CustomerContactRecord) -> some View {
        let digits = (contact.phone ?? "").filter { $0.isNumber || $0 == "+" }
        let callURL: URL? = digits.count >= 7 ? URL(string: "tel:\(digits)") : nil
        let textURL: URL? = digits.count >= 7 ? URL(string: "sms:\(digits)") : nil
        let role = [contact.role ?? "", contact.primary ? "Primary" : ""].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        return HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(contact.name).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if !role.isEmpty {
                    Text(role).font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if let callURL {
                reachPill("Call", spoken: "Call \(contact.name)") { openURL(callURL) }
            }
            if let textURL {
                reachPill("Text", spoken: "Text \(contact.name)") { inboxText(textURL, name: contact.name, openURL: openURL) }
            }
        }
        .padding(.leading, PaperCardMetrics.inset).padding(.trailing, 12).padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
    }

    private func reachPill(_ title: String, spoken: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.foreground)
                .frame(minWidth: 58, minHeight: 44)
                .background(Theme.fill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(spoken)
    }

    private func jobsSection(_ title: String, _ list: [Job]) -> some View {
        PaperSection(title, count: list.count) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(list) { job in
                    if job.id != list.first?.id { WellDivider() }
                    NavigationLink(value: PaperRoute.job(job.id)) {
                        JobRoomRow(job: job, when: JobFiltering.date(job.scheduledFor).map {
                            $0.formatted(.dateTime.month(.abbreviated).day().year())
                        }, inset: PaperCardMetrics.inset)
                    }
                    .buttonStyle(RowPressStyle())
                }
            }
        }
    }

    /// The page's ••• (Paper 87): Directions, the customer, and Edit for those who can.
    private var menuItems: [ThorbisMenuItem] {
        var items: [ThorbisMenuItem] = []
        if let mapsURL {
            items.append(ThorbisMenuItem("Directions", icon: "arrow.triangle.turn.up.right.diamond") { openURL(mapsURL) })
        }
        items.append(ThorbisMenuItem("Open customer", icon: "person") { openCustomer = row.customer })
        if canEdit {
            items.append(ThorbisMenuItem("Edit property", icon: "pencil") { editing = true })
        }
        return items
    }
}
