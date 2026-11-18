import SwiftUI

/// Paper 21O "At this address" (More › At this address): the title over "412 Birchwood Ln · 4
/// visits", then Past visits, Equipment and who was notified, each a label over one card of 64pt
/// rows. `extras` are the job's other records that have no place on Paper's Overview; they follow
/// Paper's three sections.
struct JobAtAddressView<Extras: View>: View {
    let job: JobRecord
    let street: String?
    let visits: [JobVisitRecord]
    let visitsLoaded: Bool
    let locations: [ServiceLocationRecord]
    @ViewBuilder var extras: Extras
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var store: Store
    @State private var equipment: [EquipmentRecord]?
    @State private var notices: [JobNoticeStatus] = []
    @State private var editing: EquipmentEditorItem?

    private var history: JobPropertyHistory {
        JobPropertyHistory.make(job: job, locations: [], equipment: equipment ?? [], visits: visits,
                                listedJobs: store.jobs, currentUserID: session.user?.id)
    }

    var body: some View {
        let history = history
        let count = history.visits.count
        let subtitle = [street, visitsLoaded ? "\(count) \(count == 1 ? "visit" : "visits")" : nil].compactMap { $0 }
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PaperPageTitle(title: "At this address", subtitle: subtitle.joined(separator: " \u{00B7} "), columnInset: PaperCardMetrics.margin)
                if !history.visits.isEmpty {
                    section("Past visits") {
                        ForEach(Array(history.visits.enumerated()), id: \.element.id) { index, visit in
                            row(title: visit.title,
                                subtitle: [visit.date?.formatted(.dateTime.month(.abbreviated).day().year()), visit.technician]
                                    .compactMap { $0 }.joined(separator: " \u{00B7} "),
                                first: index == 0)
                                .accessibilityElement(children: .combine)
                        }
                    }
                }
                if !history.equipment.isEmpty {
                    section("Equipment", count: history.equipment.count) {
                        ForEach(Array(history.equipment.enumerated()), id: \.element.id) { index, unit in
                            let record = equipment?.first { $0.id == unit.id }
                            if session.can("customer.edit", feature: "core_crm"), let record {
                                Button { editing = EquipmentEditorItem(record: record) } label: {
                                    row(title: unit.name, subtitle: unit.detail ?? "", first: index == 0, chevron: true)
                                }
                                .buttonStyle(RowPressStyle())
                                .accessibilityHint("Opens this equipment")
                            } else {
                                row(title: unit.name, subtitle: unit.detail ?? "", first: index == 0)
                                    .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
                if !notices.isEmpty {
                    section("Who was notified") {
                        ForEach(Array(notices.enumerated()), id: \.element.id) { index, notice in
                            row(title: notice.who,
                                subtitle: [JobFiltering.date(notice.scheduledFor)?.tradeTime, notice.statusWord.lowercased()]
                                    .compactMap { $0 }.joined(separator: " \u{00B7} "),
                                first: index == 0)
                                .accessibilityElement(children: .combine)
                        }
                    }
                }
                extras
            }
            .padding(.horizontal, 16).padding(.bottom, 28)
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .task(id: session.generation) { await load() }
        .sheet(item: $editing) { item in SheetSurface {
            EquipmentEditor(customerID: job.customerId, locations: locations, existing: item.record) { await load() }
        } }
        .accessibilityIdentifier("job-at-address")
    }

    /// Paper: a 13 Semibold label (its count at the trailing edge) 8 over a radius-20 card.
    private func section<Rows: View>(_ title: String, count: Int? = nil, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(Theme.font(13, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let count { Text("\(count)").font(Theme.font(13)) }
            }
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 4)
            VStack(spacing: 0) { rows() }
                .panelBackground(cornerRadius: Theme.cardRadius)
        }
    }

    /// Paper's row: 16 Medium over 14 in the marker grey, 64 tall, a hairline above every row but
    /// the first, a chevron when it opens something.
    private func row(title: String, subtitle: String, first: Bool, chevron: Bool = false) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Theme.font(16, weight: .medium)).tracking(-0.16).foregroundStyle(Theme.foreground)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !subtitle.isEmpty {
                    Text(subtitle).font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if chevron { PaperIcon(.jobChevronRight18, size: 18, color: Theme.muted) }
        }
        .padding(.trailing, 14).padding(.vertical, 8)
        .frame(minHeight: 64)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Theme.border).frame(height: 1) } }
        .padding(.leading, 16)
        .contentShape(Rectangle())
    }

    private func load() async {
        let generation = session.generation
        if let page = try? await api.jobNotices(job.id), session.generation == generation { notices = page.items }
        if let context = try? await JobServiceContextLoader.load(job.id, api: api) {
            guard session.generation == generation else { return }
            equipment = context.equipmentRecords.filter { $0.customerId == job.customerId }
            return
        }
        if let loaded = try? await api.customerEquipment(job.customerId), session.generation == generation {
            equipment = loaded.filter { $0.customerId == job.customerId }
        } else if session.generation == generation, equipment == nil {
            equipment = []
        }
    }
}
