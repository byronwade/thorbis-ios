import SwiftUI

/// The job's customer as one link to their profile, with the account at a glance.
struct JobCustomerSection: View {
    let customer: Customer
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperGroupHeader(title: "Customer")
            NavigationLink(value: customer) {
                PaperMenuRow(customer.name, symbol: "person", subtitle: detail)
            }
            .buttonStyle(RowPressStyle())
            .accessibilityIdentifier("job-customer-section")
            .accessibilityHint("Opens the customer's profile")
        }
    }

    /// "Residential · 3 jobs": the same job count the customer's profile shows.
    static func detail(accountType: String?, jobCount: Int?) -> String? {
        let parts = [accountType.map(\.statusLabel),
                     jobCount.map { "\($0) \($0 == 1 ? "job" : "jobs")" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Every address on the customer's account. The job carries no service address, so no row is
/// presented as the job site; each opens its own record and offers its own directions.
struct JobServiceAddressesSection: View {
    let customerID: String
    let places: [ServiceLocationRecord]
    let loaded: Bool
    let failed: Bool
    let retry: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperGroupHeader(title: "Service addresses", count: places.count)
            if failed && places.isEmpty {
                HStack(spacing: 8) {
                    ListErrorRow(message: "Addresses didn't load.")
                    Spacer(minLength: 8)
                    Button("Try again") { Task { await retry() } }
                        .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                        .frame(minHeight: 44)
                }
            } else if !loaded {
                SkeletonRows(count: 1, leading: false, inset: 0)
            } else if places.isEmpty {
                Text("No addresses on file for this customer.")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .frame(minHeight: 44, alignment: .leading)
            } else {
                Text(places.count == 1
                     ? "The customer's only address on file. The job doesn't record a site."
                     : "The customer's addresses. The job doesn't record which one it's at.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
                ForEach(Self.ordered(places)) { place in
                    JobServiceAddressRow(customerID: customerID, place: place)
                }
                if places.count == 1, let only = places.first,
                   Self.accessSummary(only) != nil || !(only.notes ?? "").isEmpty {
                    // With one address there is no choice to make: its access facts are shown in full.
                    JobSiteSection(place: only, showsLabel: true, showsAddress: false).padding(.top, 8)
                }
            }
        }
    }

    /// Service addresses before billing ones, each group in the account's own order.
    static func ordered(_ places: [ServiceLocationRecord]) -> [ServiceLocationRecord] {
        places.filter { $0.kind != "billing" } + places.filter { $0.kind == "billing" }
    }

    /// "Gate code · Alarm code · Dog on site · Parking notes": what's recorded, never the codes themselves.
    static func accessSummary(_ place: ServiceLocationRecord) -> String? {
        func has(_ value: String?) -> Bool { !(value ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
        let parts = [has(place.gateCode) ? "Gate code" : nil,
                     has(place.alarmCode) ? "Alarm code" : nil,
                     has(place.dogOnSite) ? "Dog on site" : nil,
                     has(place.parking) ? "Parking notes" : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct JobServiceAddressRow: View {
    let customerID: String
    let place: ServiceLocationRecord
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 8) {
            NavigationLink(value: PaperRoute.location(customerID: customerID, locationID: place.id)) {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.label).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                        Text("\(place.kind == "billing" ? "Billing" : "Service") · \(place.address)")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        if let access = JobServiceAddressesSection.accessSummary(place) {
                            Text(access).font(Theme.font(13)).foregroundStyle(Theme.muted)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    PaperDisclosure()
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the address")
            if let url = Directions.url(address: place.address, coordinates: place.coordinates) {
                Button { openURL(url) } label: {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond")
                        .font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.foreground)
                        .frame(width: 44, height: 44)
                        .background(Theme.fill, in: Circle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Directions to \(place.label)")
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 56)
    }
}

/// The customer an estimate or invoice is for, as a link to their profile. Staff screens only:
/// customer mode never shows it, and without customer access it isn't offered.
struct DocumentCustomerLink: View {
    let customerID: String
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController

    var body: some View {
        if session.can("customer.view", feature: "core_crm"),
           let customer = store.customers.first(where: { $0.id == customerID }) {
            NavigationLink(value: customer) {
                PaperMenuRow(customer.name, symbol: "person", subtitle: "Customer")
            }
            .buttonStyle(RowPressStyle())
            .accessibilityIdentifier("document-customer-link")
            .accessibilityHint("Opens the customer's profile")
        }
    }
}
