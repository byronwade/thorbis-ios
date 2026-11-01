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
    /// The street the job's header already shows; a row doesn't say it again.
    var headerStreet: String? = nil
    /// The place whose access facts "At this address" already lists; its row doesn't repeat them.
    var factsShownFor: String? = nil
    let retry: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            JobPanelLabel(title: "Service addresses", count: places.isEmpty ? nil : "\(places.count)")
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
                    .padding(.horizontal, 4)
            } else {
                JobPanel {
                    Text(places.count == 1
                         ? "The customer's only address on file. The job doesn't record a site."
                         : "The customer's addresses. The job doesn't record which one it's at.")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16).padding(.top, 10)
                        .jobPanelJoinsNext()
                    ForEach(Self.ordered(places)) { place in
                        JobServiceAddressRow(customerID: customerID, place: place,
                                             where: Self.whereLine(place, headerStreet: headerStreet),
                                             access: place.id == factsShownFor ? nil : Self.accessSummary(place))
                            .padding(.horizontal, 16)
                    }
                }
                // Access facts are shown once, in "Before you go in" above (JobPropertyHistorySection).
            }
        }
    }

    /// Service addresses before billing ones, each group in the account's own order.
    static func ordered(_ places: [ServiceLocationRecord]) -> [ServiceLocationRecord] {
        places.filter { $0.kind != "billing" } + places.filter { $0.kind == "billing" }
    }

    /// "Service · 412 Birchwood Ln, Sacramento": the kind, then the address. When the header already
    /// leads with this street, only the rest of the address (the town) follows the kind, so the
    /// street is said once.
    static func whereLine(_ place: ServiceLocationRecord, headerStreet: String?) -> String {
        let kind = place.kind == "billing" ? "Billing" : "Service"
        var address = place.address.trimmingCharacters(in: .whitespacesAndNewlines)
        if let headerStreet, !headerStreet.isEmpty {
            let parts = address.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.first?.caseInsensitiveCompare(headerStreet) == .orderedSame {
                address = parts.count > 1 ? parts[1] : ""
            }
        }
        return address.isEmpty ? kind : "\(kind) · \(address)"
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
    let `where`: String
    let access: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 8) {
            NavigationLink(value: PaperRoute.location(customerID: customerID, locationID: place.id)) {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.label).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                        Text(`where`)
                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        if let access {
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
