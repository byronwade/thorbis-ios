import SwiftUI
import UIKit

/// "Before you go in": what the technician should know about the place, read from data the app
/// already has (the job, the customer's locations, equipment and the job's visit history).
///
/// Jobs carry an optional `locationId`. When it is set the section is "At this address" and only
/// shows facts tied to that location. When it isn't (BYR-1593 tracks job service locations), the
/// section is "Customer history" and never presents an account address as the job site.
struct JobPropertyHistory: Codable, Hashable {
    enum Scope: String, Codable { case address, customer }

    struct Fact: Codable, Hashable, Identifiable {
        let label: String
        let value: String
        /// Gate and alarm codes read in tabular digits and copy on a long press.
        let isCode: Bool
        var id: String { label }
    }

    struct Unit: Codable, Hashable, Identifiable {
        let id: String
        let name: String
        let detail: String?
    }

    struct Visit: Codable, Hashable, Identifiable {
        let id: String
        let title: String
        let date: Date?
        /// "You" or "Another tech": visit history carries a user id, not a name.
        let technician: String?
        let status: String
    }

    let organizationId: String
    let jobId: String
    let customerId: String
    let scope: Scope
    /// Where the access facts come from, e.g. "Home · 412 Birchwood Ln".
    let place: String?
    let facts: [Fact]
    let equipment: [Unit]
    let visits: [Visit]

    var title: String { scope == .address ? "At this address" : "Customer history" }
    var isEmpty: Bool { facts.isEmpty && equipment.isEmpty && visits.isEmpty }

    static let visitLimit = 3

    /// Builds the section from what is loaded. `listedJobs` (the cached job list) is the only
    /// place a past visit's location is known, so at an address a visit without one is left out.
    static func make(job: JobRecord, locations: [ServiceLocationRecord], equipment: [EquipmentRecord],
                     visits: [JobVisitRecord], listedJobs: [Job], currentUserID: String?,
                     now: Date = .now) -> JobPropertyHistory {
        let ownLocations = locations.filter { $0.customerId == job.customerId && $0.organizationId == job.organizationId }
        let scope: Scope = job.locationId == nil ? .customer : .address
        let place: ServiceLocationRecord?
        if let locationID = job.locationId {
            place = ownLocations.first { $0.id == locationID }
        } else {
            // Without a job site, access facts are shown only when the account has one service address.
            let service = ownLocations.filter { $0.kind != "billing" }
            place = service.count == 1 ? service.first : nil
        }

        let units = equipment
            .filter { $0.customerId == job.customerId }
            .filter { scope == .customer || $0.locationId == job.locationId }
            .map { Unit(id: $0.id, name: $0.name, detail: unitDetail($0, now: now)) }

        let locationByJob = Dictionary(listedJobs.map { ($0.id, $0.locationId) }, uniquingKeysWith: { first, _ in first })
        let shownVisits = visits
            .filter { $0.id != job.id }
            .filter { visit in
                guard scope == .address else { return true }
                return locationByJob[visit.id].flatMap { $0 } == job.locationId
            }
            .sorted { ($0.when ?? .distantPast) > ($1.when ?? .distantPast) }
            .prefix(visitLimit)
            .map { visit in
                Visit(id: visit.id, title: visit.title, date: visit.when,
                      technician: visit.assignedToUserId.map { $0 == currentUserID ? "You" : "Another tech" },
                      status: visit.status)
            }

        return JobPropertyHistory(organizationId: job.organizationId, jobId: job.id, customerId: job.customerId,
                                  scope: scope, place: place.map(placeLine), facts: place.map(facts) ?? [],
                                  equipment: units, visits: Array(shownVisits))
    }

    static func facts(_ place: ServiceLocationRecord) -> [Fact] {
        func clean(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
        return [clean(place.dogOnSite).map { Fact(label: "Dog", value: $0, isCode: false) },
                clean(place.gateCode).map { Fact(label: "Gate code", value: $0, isCode: true) },
                clean(place.alarmCode).map { Fact(label: "Alarm code", value: $0, isCode: true) },
                clean(place.parking).map { Fact(label: "Parking", value: $0, isCode: false) },
                clean(place.notes).map { Fact(label: "Site notes", value: $0, isCode: false) }].compactMap { $0 }
    }

    private static func placeLine(_ place: ServiceLocationRecord) -> String {
        place.label.isEmpty ? place.address : "\(place.label) · \(place.address)"
    }

    /// "Carrier 24ACC636 · Installed 2019 · 7 yrs". Service dates aren't recorded on equipment.
    static func unitDetail(_ unit: EquipmentRecord, now: Date) -> String? {
        var parts: [String] = []
        let make = [unit.brand, unit.model].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        if !make.isEmpty { parts.append(make) }
        if let installed = unit.installedOn.flatMap(EquipmentRecord.day) {
            let calendar = Calendar(identifier: .gregorian)
            parts.append("Installed \(calendar.component(.year, from: installed))")
            let years = calendar.dateComponents([.year], from: installed, to: now).year ?? 0
            parts.append(years < 1 ? "Under a year" : "\(years) \(years == 1 ? "yr" : "yrs")")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Visible rows while collapsed: the access facts always show; equipment and visits share three.
enum JobPropertyHistoryLayout {
    static let collapsedRows = 3

    static func needsShowAll(_ history: JobPropertyHistory) -> Bool {
        history.equipment.count + history.visits.count > collapsedRows + 1
    }

    static func collapsed(_ history: JobPropertyHistory) -> (equipment: ArraySlice<JobPropertyHistory.Unit>, visits: ArraySlice<JobPropertyHistory.Visit>) {
        guard needsShowAll(history) else { return (history.equipment[...], history.visits[...]) }
        let visits = min(history.visits.count, history.equipment.isEmpty ? collapsedRows : 1)
        let equipment = min(history.equipment.count, collapsedRows - visits)
        let moreVisits = min(history.visits.count, collapsedRows - equipment)
        return (history.equipment.prefix(equipment), history.visits.prefix(moreVisits))
    }
}

/// The Overview section. It reads equipment on its own, after the job is on screen, and shows the
/// last copy saved on this phone when a source can't be read (offline). Hidden when there's nothing.
struct JobPropertyHistorySection: View {
    let job: JobRecord
    /// The customer's locations, already checked against the current customer context.
    let locations: [ServiceLocationRecord]
    let locationsLoaded: Bool
    let visits: [JobVisitRecord]
    let visitsLoaded: Bool
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var store: Store
    /// Nil until the read answers; empty when the server doesn't offer equipment to this role.
    @State private var equipment: [EquipmentRecord]?
    @State private var cached: JobDetailCache.SavedHistory?
    @State private var expanded = false
    @State private var editing: EquipmentEditorItem?

    private var canViewCustomer: Bool { session.can("customer.view", feature: "core_crm") }
    private var canEditEquipment: Bool { session.can("customer.edit", feature: "core_crm") }
    private var ready: Bool { visitsLoaded && equipment != nil && (locationsLoaded || !canViewCustomer) }

    private var live: JobPropertyHistory {
        JobPropertyHistory.make(job: job, locations: locations, equipment: equipment ?? [], visits: visits,
                                listedJobs: store.jobs, currentUserID: session.user?.id)
    }

    /// Fresh when every source answered; else the saved copy; else whatever has loaded so far.
    private var shown: (history: JobPropertyHistory, savedAt: Date?) {
        if ready { return (live, nil) }
        if let cached, cached.history.organizationId == session.activeOrganization?.id,
           cached.history.jobId == job.id, cached.history.customerId == job.customerId {
            return (cached.history, cached.savedAt)
        }
        return (live, nil)
    }

    var body: some View {
        let (history, savedAt) = shown
        // A zero-size anchor keeps the load task alive while nothing is shown.
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(width: 0, height: 0)
            if !history.isEmpty { content(history, savedAt: savedAt) }
        }
        .accessibilityIdentifier("job-property-history")
        .task(id: "\(job.customerId)|\(session.generation.uuidString)") {
            cached = JobDetailCache.history(job.id)
            await loadEquipment()
        }
        .task(id: ready ? live : nil) {
            guard ready else { return }
            JobDetailCache.save(history: live)
        }
        .sheet(item: $editing) { item in
            EquipmentEditor(customerID: job.customerId, locations: locations, existing: item.record) { await loadEquipment() }
        }
    }

    @ViewBuilder
    private func content(_ history: JobPropertyHistory, savedAt: Date?) -> some View {
        let rows = expanded ? (history.equipment[...], history.visits[...]) : JobPropertyHistoryLayout.collapsed(history)
        VStack(alignment: .leading, spacing: 0) {
            PaperGroupHeader(title: history.title)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("job-property-history-title")
            if let savedAt {
                Text("Saved on this phone \(savedAt.formatted(.relative(presentation: .named)))")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.bottom, 4)
            }
            if !history.facts.isEmpty { accessFacts(history) }
            ForEach(rows.0) { unit in equipmentRow(unit) }
            ForEach(rows.1) { visit in visitRow(visit) }
            if JobPropertyHistoryLayout.needsShowAll(history) {
                Button { withMotion(.snappy) { expanded.toggle() } } label: {
                    Text(expanded ? "Show less" : "Show all \(history.equipment.count + history.visits.count)")
                        .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.brandText)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("job-property-history-show-all")
            }
        }
    }

    /// Safety first: a warning mark on the heading, each fact on its own row. No card, no border.
    private func accessFacts(_ history: JobPropertyHistory) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.warning)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Before you go in").font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.foreground)
                    if let place = history.place {
                        Text(history.scope == .address ? place : "\(place) · only address on file")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
            ForEach(history.facts) { fact in
                if fact.isCode {
                    PaperDetailRow(label: fact.label) { Text(fact.value).font(Theme.monoFont(15, weight: .medium)) }
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button("Copy \(fact.label.lowercased())", systemImage: "doc.on.doc") { UIPasteboard.general.string = fact.value }
                        }
                        .accessibilityHint("Touch and hold to copy")
                } else {
                    PaperDetailRow(fact.label, value: fact.value)
                }
            }
        }
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func equipmentRow(_ unit: JobPropertyHistory.Unit) -> some View {
        let record = equipment?.first { $0.id == unit.id }
        if canEditEquipment, let record {
            Button { editing = EquipmentEditorItem(record: record) } label: {
                PaperMenuRow(unit.name, symbol: "shippingbox", subtitle: unit.detail)
            }
            .buttonStyle(RowPressStyle())
            .accessibilityHint("Opens the equipment")
        } else {
            PaperMenuRow(title: unit.name, symbol: "shippingbox", subtitle: unit.detail) { EmptyView() }
                .accessibilityElement(children: .combine)
        }
    }

    private func visitRow(_ visit: JobPropertyHistory.Visit) -> some View {
        NavigationLink(value: PaperRoute.job(visit.id)) {
            PaperMenuRow(visit.title, symbol: "clock.arrow.circlepath", subtitle: visitLine(visit))
        }
        .buttonStyle(RowPressStyle())
        .accessibilityIdentifier("job-property-visit-\(visit.id)")
        .accessibilityHint("Opens that job")
    }

    /// "Apr 14, 2026 · You · Completed": status always as a word.
    private func visitLine(_ visit: JobPropertyHistory.Visit) -> String {
        [visit.date?.formatted(.dateTime.month(.abbreviated).day().year()), visit.technician, visit.status.statusLabel]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func loadEquipment() async {
        let generation = session.generation
        do {
            let loaded = try await api.customerEquipment(job.customerId)
            guard session.generation == generation else { return }
            equipment = loaded.filter { $0.customerId == job.customerId }
        } catch is CancellationError {
        } catch {
            guard session.generation == generation else { return }
            // 403 (role can't read equipment) or 404 (older server): nothing to show, not a failure.
            // No signal: leave it unread so the saved copy stays on screen.
            if !error.isConnectivityFailure { equipment = [] }
        }
    }
}
