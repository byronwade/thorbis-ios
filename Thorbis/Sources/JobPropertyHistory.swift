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
        /// What was done, from the visit's own notes, when it has any.
        var notes: String? = nil
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
        let scope: Scope = job.locationId == nil ? .customer : .address
        let place = accessPlace(job: job, locations: locations)

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
                      status: visit.status,
                      notes: visit.notes.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 })
            }

        return JobPropertyHistory(organizationId: job.organizationId, jobId: job.id, customerId: job.customerId,
                                  scope: scope, place: place.map(placeLine), facts: place.map(facts) ?? [],
                                  equipment: units, visits: Array(shownVisits))
    }

    /// The place whose access facts apply: the job's own location, or, without one, the account's
    /// only service address (shown with that caveat). Never a guess between several addresses.
    static func accessPlace(job: JobRecord, locations: [ServiceLocationRecord]) -> ServiceLocationRecord? {
        let ownLocations = locations.filter { $0.customerId == job.customerId && $0.organizationId == job.organizationId }
        if let locationID = job.locationId {
            return ownLocations.first { $0.id == locationID }
        }
        // Without a job site, access facts are shown only when the account has one service address.
        let service = ownLocations.filter { $0.kind != "billing" }
        return service.count == 1 ? service.first : nil
    }

    /// The job's street (the first line of its own location's address), or nil when the job
    /// records no site (BYR-1593). The account's addresses are never promoted to the job site.
    static func street(job: JobRecord, locations: [ServiceLocationRecord]) -> String? {
        guard let locationID = job.locationId,
              let place = locations.first(where: { $0.id == locationID && $0.customerId == job.customerId && $0.organizationId == job.organizationId })
        else { return nil }
        let first = place.address.split(separator: ",", maxSplits: 1).first.map(String.init) ?? place.address
        let street = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return street.isEmpty ? nil : street
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


/// The Overview's history, in two panels (Job.dc.html): "At this address" (access facts and
/// equipment) and "Past visits here". The place part reads equipment on its own, after the job is
/// on screen, and saves the last copy on this phone; both parts show that copy when a source
/// can't be read (offline). Each part is hidden when it has nothing to show.
struct JobPropertyHistorySection: View {
    enum Part { case place, visits }

    let job: JobRecord
    var part: Part = .place
    /// The customer's locations, already checked against the current customer context.
    let locations: [ServiceLocationRecord]
    let locationsLoaded: Bool
    let visits: [JobVisitRecord]
    let visitsLoaded: Bool
    /// False on site, where the "Before you go in" banner already says the access facts: the
    /// panel then lists only the equipment, so each fact shows once.
    var showsFacts = true
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
    private var ready: Bool {
        switch part {
        case .place: visitsLoaded && equipment != nil && (locationsLoaded || !canViewCustomer)
        case .visits: visitsLoaded
        }
    }

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
            switch part {
            case .place:
                if (showsFacts && !history.facts.isEmpty) || !history.equipment.isEmpty { placePanel(history, savedAt: savedAt) }
            case .visits:
                if !history.visits.isEmpty { visitsPanel(history, savedAt: savedAt) }
            }
        }
        .accessibilityIdentifier(part == .place ? "job-property-history" : "job-property-visits")
        .task(id: "\(job.customerId)|\(session.generation.uuidString)|\(part == .place)") {
            cached = JobDetailCache.history(job.id)
            if part == .place { await loadEquipment() }
        }
        .task(id: ready && part == .place ? live : nil) {
            guard ready, part == .place else { return }
            JobDetailCache.save(history: live)
        }
        .sheet(item: $editing) { item in
            EquipmentEditor(customerID: job.customerId, locations: locations, existing: item.record) { await loadEquipment() }
        }
    }

    private func savedLine(_ savedAt: Date?) -> some View {
        Group {
            if let savedAt {
                Text("Saved on this phone \(savedAt.formatted(.relative(presentation: .named)))")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 16).padding(.top, 10)
                    .jobPanelJoinsNext()
            }
        }
    }

    @ViewBuilder
    private func placePanel(_ history: JobPropertyHistory, savedAt: Date?) -> some View {
        let units = expanded || history.equipment.count <= JobPropertyHistoryLayout.collapsedRows + 1
            ? history.equipment[...] : history.equipment.prefix(JobPropertyHistoryLayout.collapsedRows)
        let facts = showsFacts ? history.facts : []
        // Access codes, dogs and parking are what to know before going in: a warning mark leads.
        JobPanelSection(title: facts.isEmpty ? "Equipment" : history.title, mark: facts.isEmpty ? nil : "exclamationmark.triangle.fill",
                        actionTitle: history.equipment.count > JobPropertyHistoryLayout.collapsedRows + 1 ? (expanded ? "Show less" : "Show all \(history.equipment.count)") : nil,
                        actionIdentifier: "job-property-history-show-all",
                        action: { withMotion(.snappy) { expanded.toggle() } }) {
            savedLine(savedAt)
            // The job's own street is the screen's title; the place line shows only when the facts
            // come from somewhere else (the customer's only address on file).
            if let place = history.place, !facts.isEmpty, history.scope != .address {
                Text("\(place) · only address on file")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16).padding(.top, 10)
                    .jobPanelJoinsNext()
            }
            ForEach(facts) { fact in
                if fact.isCode {
                    JobPanelFact(label: fact.label, value: fact.value, mono: true)
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button("Copy \(fact.label.lowercased())", systemImage: "doc.on.doc") { UIPasteboard.general.string = fact.value }
                        }
                        .accessibilityHint("Touch and hold to copy")
                } else {
                    JobPanelFact(label: fact.label, value: fact.value)
                }
            }
            ForEach(units) { unit in equipmentRow(unit) }
        }
        .accessibilityIdentifier("job-property-history-title")
    }

    @ViewBuilder
    private func equipmentRow(_ unit: JobPropertyHistory.Unit) -> some View {
        let record = equipment?.first { $0.id == unit.id }
        if canEditEquipment, let record {
            Button { editing = EquipmentEditorItem(record: record) } label: {
                JobPanelRow(title: unit.name, subtitle: unit.detail, titleSize: 15)
            }
            .buttonStyle(RowPressStyle())
            .accessibilityHint("Opens the equipment")
        } else {
            JobPanelRow(title: unit.name, subtitle: unit.detail, titleSize: 15)
                .accessibilityElement(children: .combine)
        }
    }

    private func visitsPanel(_ history: JobPropertyHistory, savedAt: Date?) -> some View {
        JobPanelSection(title: history.scope == .address ? "Past visits here" : "Past visits", count: "\(history.visits.count)") {
            savedLine(savedAt)
            ForEach(history.visits) { visit in
                NavigationLink(value: PaperRoute.job(visit.id)) {
                    JobPanelRow(title: visit.title, subtitle: visitLine(visit),
                                leading: visit.date?.formatted(.dateTime.month(.abbreviated).day()) ?? "—", titleSize: 15)
                }
                .buttonStyle(RowPressStyle())
                .accessibilityIdentifier("job-property-visit-\(visit.id)")
                .accessibilityHint("Opens that job")
            }
        }
    }

    /// What was done when the visit says so, else "2026 · You · Completed": status always as a word.
    private func visitLine(_ visit: JobPropertyHistory.Visit) -> String {
        let facts = [visit.date.map { $0.formatted(.dateTime.year()) }, visit.technician, visit.status.statusLabel]
            .compactMap { $0 }.joined(separator: " · ")
        guard let notes = visit.notes else { return facts }
        return "\(notes)\n\(facts)"
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
