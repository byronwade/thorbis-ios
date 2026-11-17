import SwiftUI

/// Opens one workspace's lead file and tells the screens when it changes.
@MainActor
final class PipelineBook: ObservableObject {
    @Published private(set) var organizationID: String?
    @Published private(set) var error: String?
    @Published private(set) var revision = 0
    private var storage: PipelineRecords?

    var isOpen: Bool { storage != nil }
    var leads: [LeadRecord] { storage?.leads ?? [] }
    func lead(_ id: String) -> LeadRecord? { storage?.lead(id) }

    func bind(organizationID: String?) {
        guard let organizationID else {
            storage = nil; self.organizationID = nil; error = nil; revision += 1
            return
        }
        guard self.organizationID != organizationID || storage == nil else { return }
        storage = nil
        self.organizationID = nil
        error = nil
        do {
            #if DEBUG
            if PaperPreview.enabled {
                storage = try PipelinePreviewData.records(organizationID: organizationID)
                self.organizationID = organizationID
                revision += 1
                return
            }
            #endif
            storage = try PipelineRecords(organizationID: organizationID)
            self.organizationID = organizationID
        } catch {
            self.error = error.localizedDescription
        }
        revision += 1
    }

    /// Runs one change against the file and redraws.
    func change(_ work: (PipelineRecords) throws -> Void) throws {
        guard let storage else { throw Problem(title: "No workspace is open", status: nil, detail: nil) }
        try work(storage)
        revision += 1
    }
}

/// A lead being added or edited in the sheet.
struct LeadDraft: Identifiable {
    let id: String
    let existing: LeadRecord?
    init(_ existing: LeadRecord? = nil) { self.existing = existing; self.id = existing?.id ?? UUID().uuidString }
}

struct LeadRoute: Hashable { let id: String }

/// Paper 82A "Pipeline (leads)": how many leads are open and what they could be worth, the stages
/// as pills with their counts, then that stage's leads on one card. Kept on this phone for the
/// open workspace, and the page says so.
struct PipelineView: View {
    @EnvironmentObject private var session: SessionController
    @Environment(\.openURL) private var openURL
    @StateObject private var book = PipelineBook()
    @State private var stage: LeadStage = .new
    @State private var route: LeadRoute?
    @State private var draft: LeadDraft?
    @State private var actionError: String?

    init() {}

    private var organizationID: String? { session.activeOrganization?.id }

    private func attempt(_ work: () throws -> Void) {
        do { try work(); actionError = nil }
        catch { actionError = error.localizedDescription }
    }

    var body: some View {
        let leads = book.leads
        let counts = PipelineMath.counts(leads)
        let shown = PipelineMath.leads(leads, in: stage)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaperHeader(title: "Pipeline",
                            subtitle: book.isOpen ? PipelineMath.summary(leads) : "Kept on this phone",
)
                if book.isOpen {
                    stagePills(counts).padding(.top, 16)
                }
                VStack(alignment: .leading, spacing: 12) {
                    if let error = actionError ?? book.error { SalesProblemLine(message: error) }
                    if !book.isOpen && book.error == nil {
                        if organizationID == nil {
                            PaperEmptyState(symbol: "building.2", title: "No workspace is open",
                                            message: "Leads are kept for each workspace. Open one to see them.")
                        } else {
                            SkeletonRows(count: 3, leading: false, inset: 0)
                        }
                    } else if book.isOpen {
                        if leads.isEmpty {
                            PaperEmptyState(symbol: "person.crop.circle.badge.plus", title: "No leads yet",
                                            message: "Add someone who called or asked for a quote, then move them along as you book a visit and quote the work.",
                                            actionTitle: "New lead") { draft = LeadDraft() }
                                .padding(.horizontal, -PaperCardMetrics.margin)
                        } else if shown.isEmpty {
                            PaperCard {
                                Text(emptyLine).font(Theme.font(15)).foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 16)
                            }
                        } else {
                            PaperCard {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(shown) { lead in
                                        if lead.id != shown.first?.id { WellDivider(leading: 0) }
                                        leadRow(lead)
                                    }
                                }
                            }
                            if stage == .won || stage == .lost, PipelineMath.value(leads, in: stage) > 0 {
                                Text("\(PipelineMath.money(PipelineMath.value(leads, in: stage))) \(stage == .won ? "won" : "lost"), by your own estimates.")
                                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 4)
                            }
                        }
                        // Paper 82A's note sits here (13 muted, 4 in); this one says what is true on this phone.
                        Text("Leads are kept on this phone. Moving a lead doesn\u{2019}t create a customer or a job.")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                }
                .paperCardMargin().padding(.top, 16).padding(.bottom, 24)
            }
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("pipeline-root")
        .placeBarCreate("New lead", shows: book.isOpen) { draft = LeadDraft() }
        .task(id: organizationID) {
            route = nil; draft = nil; actionError = nil
            book.bind(organizationID: organizationID)
        }
        .thorbisDestination(item: $route) { LeadDetailView(leadID: $0.id, book: book) }
        .sheet(item: $draft) { editing in SheetSurface {
            LeadEditorSheet(existing: editing.existing) { lead in
                try book.change { try $0.save(lead) }
                actionError = nil
                stage = lead.stage
            }
        } }
    }

    private var emptyLine: String {
        switch stage {
        case .new: "No new leads. Add one with the + above."
        case .visitBooked: "No leads with a visit booked."
        case .quoted: "No leads waiting on a quote."
        case .won: "No leads marked won yet."
        case .lost: "No leads marked lost."
        }
    }

    /// Paper 82A: "New · 3", "Visit booked · 2", "Quoted · 4" as 36-tall pills; the chosen one in
    /// ink. Won and Lost follow, so a finished lead is still found.
    private func stagePills(_ counts: [LeadStage: Int]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LeadStage.allCases, id: \.self) { item in
                    let isOn = item == stage
                    Button { stage = item } label: {
                        Text("\(item.label) \u{00B7} \(counts[item] ?? 0)")
                            .font(Theme.font(14, weight: isOn ? .semibold : .medium))
                            .foregroundStyle(isOn ? Theme.onInk : Theme.foreground)
                            .padding(.horizontal, 14).frame(minHeight: 36)
                            .background(isOn ? Theme.ink : Theme.card, in: Capsule())
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("\(item.label), \(counts[item] ?? 0)")
                    .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                    .accessibilityIdentifier("pipeline-stage-\(item.rawValue)")
                }
            }
            .padding(.horizontal, PaperCardMetrics.margin)
        }
    }

    /// Paper 82A: the name (16 Semibold) and when, where it came from and what they need, then the
    /// likely value. A new lead carries its two next steps as pills.
    private func leadRow(_ lead: LeadRecord) -> some View {
        let today = Calendar.current.isDateInToday(lead.updatedAt)
        return VStack(alignment: .leading, spacing: 0) {
            Button { route = LeadRoute(id: lead.id) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(lead.name).font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(PipelineMath.when(lead.updatedAt))
                            .font(Theme.font(13, weight: today ? .semibold : .regular))
                            .foregroundStyle(today ? Theme.brandText : Theme.subtle)
                            .fixedSize()
                    }
                    let about = [lead.source ?? "", lead.need ?? ""].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
                    if !about.isEmpty {
                        Text(about).font(Theme.font(15)).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    let extra = [lead.valueCents.map { "about \(PipelineMath.money($0))" } ?? "", lead.note ?? ""]
                        .filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
                    if !extra.isEmpty {
                        Text(extra).font(Theme.font(13)).foregroundStyle(Theme.subtle)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, PaperCardMetrics.inset).padding(.top, 14)
                .padding(.bottom, lead.stage == .new ? 6 : 14)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the lead")
            if lead.stage == .new {
                FlowRow(spacing: 8, lineSpacing: 4) {
                    if let callURL = lead.callURL {
                        rowPill("Call back", spoken: "Call \(lead.name)", fill: Theme.brand, ink: .white, weight: .semibold) { openURL(callURL) }
                    }
                    rowPill("Visit booked", spoken: "Mark visit booked for \(lead.name)", fill: Theme.sidebarAccent,
                            ink: Theme.foreground, weight: .medium) {
                        attempt { try book.change { try $0.move(lead.id, to: .visitBooked) } }
                    }
                }
                .padding(.horizontal, PaperCardMetrics.inset).padding(.bottom, 10)
            }
        }
    }

    private func rowPill(_ title: String, spoken: String, fill: Color, ink: Color, weight: Font.Weight,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.font(14, weight: weight)).foregroundStyle(ink)
                .padding(.horizontal, 14).frame(minHeight: 36)
                .background(fill, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(spoken)
    }
}

/// Paper 82B "Lead detail": the name, where the lead stands, Call as the commit with Text and the
/// next step beside it, the facts, the notes, then won or lost.
struct LeadDetailView: View {
    let leadID: String
    @ObservedObject var book: PipelineBook
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var editing: LeadDraft?
    @State private var removing = false
    @State private var actionError: String?

    private func attempt(_ work: () throws -> Void) {
        do { try work(); actionError = nil }
        catch { actionError = error.localizedDescription }
    }

    private func move(_ stage: LeadStage) { attempt { try book.change { try $0.move(leadID, to: stage) } } }

    var body: some View {
        let lead = book.lead(leadID)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let lead {
                    page(lead)
                } else {
                    Text("This lead is no longer on this phone.").font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .paperCardMargin().padding(.top, 8).padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let lead {
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    ThorbisMenu(items: menuItems(lead), accessibilityLabel: "Lead actions") {
                        PaperCircleLabel(symbol: "ellipsis", size: 44, fill: Theme.card)
                    }
                }
            }
        }
        .sheet(item: $editing) { draft in SheetSurface {
            LeadEditorSheet(existing: draft.existing) { saved in
                try book.change { try $0.save(saved) }
                actionError = nil
            }
        } }
        .thorbisConfirm("Remove this lead?", message: "It is deleted from this phone.", isPresented: $removing,
                        actions: [ThorbisConfirmAction("Remove", role: .destructive) {
                            do { try book.change { try $0.remove(leadID) }; dismiss() }
                            catch { actionError = error.localizedDescription }
                        }])
    }

    private func menuItems(_ lead: LeadRecord) -> [ThorbisMenuItem] {
        var items = [ThorbisMenuItem("Edit lead", icon: "pencil") { editing = LeadDraft(lead) }]
        if lead.stage.isOpen {
            items.append(ThorbisMenuItem("Mark won", icon: "checkmark.circle") { move(.won) })
            items.append(ThorbisMenuItem("Mark lost", icon: "xmark.circle") { move(.lost) })
        } else {
            items.append(ThorbisMenuItem("Reopen as new", icon: "arrow.uturn.backward") { move(.new) })
        }
        items.append(ThorbisMenuItem("Remove", icon: "trash", role: .destructive) { removing = true })
        return items
    }

    private func chipInk(_ stage: LeadStage) -> Color {
        switch stage {
        case .new, .visitBooked, .quoted: Theme.brandText
        case .won: Theme.success
        case .lost: Theme.muted
        }
    }

    private func chipSurface(_ stage: LeadStage) -> Color {
        switch stage {
        case .new, .visitBooked, .quoted: Theme.brandSurface
        case .won: Theme.successSurface
        case .lost: Theme.fill
        }
    }

    @ViewBuilder private func page(_ lead: LeadRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(lead.name).font(Theme.font(28, weight: .bold)).tracking(-0.6)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            FlowRow(spacing: 8, lineSpacing: 4) {
                SalesStatusChip(text: lead.stage == .new ? "New lead" : lead.stage.label,
                                ink: chipInk(lead.stage), surface: chipSurface(lead.stage))
                Text([lead.need ?? "", PipelineMath.when(lead.updatedAt)].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                    .font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 24)
            }
        }
        .padding(.horizontal, 4).padding(.bottom, 4)
        if let actionError { SalesProblemLine(message: actionError) }
        if let callURL = lead.callURL {
            Button { openURL(callURL) } label: {
                SalesBrandCommit(title: lead.stage == .new ? "Call back" : "Call", symbol: "phone")
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Call \(lead.name)")
            .accessibilityIdentifier("pipeline-call")
        }
        HStack(alignment: .top, spacing: 8) {
            if let textURL = lead.textURL {
                Button { openURL(textURL) } label: { SalesQuietPill(title: "Text", symbol: "message") }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Text \(lead.name)")
                    .accessibilityIdentifier("pipeline-text")
            }
            if let next = lead.stage.next {
                Button { move(next) } label: { SalesQuietPill(title: next == .won ? "Mark won" : "Move to \(next.label.lowercased())") }
                    .buttonStyle(PressStyle())
                    .accessibilityIdentifier("pipeline-move-next")
            }
        }
        PaperCard {
            VStack(alignment: .leading, spacing: 0) {
                ThorbisSelect(options: LeadStage.allCases.map { (value: $0, label: $0.label) },
                              selection: Binding(get: { lead.stage }, set: { move($0) }),
                              label: "Stage", menuTitle: "Move to")
                    .padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 52)
                    .accessibilityIdentifier("pipeline-stage-select")
                WellDivider()
                fact("Source", lead.source ?? "", empty: "Not set")
                WellDivider()
                fact("Likely value", lead.valueCents.map { PipelineMath.money($0) } ?? "", empty: "Not set")
                WellDivider()
                fact("Phone", lead.phone ?? "", empty: "No phone yet")
                WellDivider()
                fact("Added", lead.createdAt.formatted(date: .abbreviated, time: .omitted))
            }
        }
        // Paper 82B: "Notes" with its action in the brand ink on the right, the words under them.
        PaperCard {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Notes").font(Theme.font(13)).foregroundStyle(Theme.muted)
                    Spacer(minLength: 8)
                    Button { editing = LeadDraft(lead) } label: {
                        Text((lead.note ?? "").isEmpty ? "Add note" : "Edit")
                            .font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.brandText)
                            .frame(minWidth: 44, minHeight: 44, alignment: .trailing).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityIdentifier("pipeline-edit-note")
                }
                Text((lead.note ?? "").isEmpty ? "No notes yet." : (lead.note ?? ""))
                    .font(Theme.font(15)).foregroundStyle((lead.note ?? "").isEmpty ? Theme.muted : Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, PaperCardMetrics.inset).padding(.top, 2).padding(.bottom, 14)
        }
        if lead.stage.isOpen {
            HStack(alignment: .top, spacing: 8) {
                Button { move(.won) } label: { SalesQuietPill(title: "Won", symbol: "checkmark", ink: Theme.success) }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Mark won")
                    .accessibilityIdentifier("pipeline-mark-won")
                Button { move(.lost) } label: { SalesQuietPill(title: "Lost", symbol: "xmark", ink: Theme.destructive) }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Mark lost")
                    .accessibilityIdentifier("pipeline-mark-lost")
            }
        } else {
            Button { move(.new) } label: { SalesQuietPill(title: "Reopen as new", symbol: "arrow.uturn.backward") }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("pipeline-reopen")
        }
        SalesPhoneNote(text: "Saved on this phone only. Moving this lead doesn\u{2019}t create a customer or a job.")
            .padding(.top, 4)
    }

    private func fact(_ label: String, _ value: String, empty: String = "") -> some View {
        PaperDetailRow(label: label) { Text(value.isEmpty ? empty : value) }
            .padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 52)
    }
}

/// Paper 82C "New lead": Cancel and Save in the title row, who they are on one card, what they
/// need, where they came from and the likely value on the next, then a note.
struct LeadEditorSheet: View {
    let existing: LeadRecord?
    let onSave: (LeadRecord) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var phone: String
    @State private var need: String
    @State private var source: String
    @State private var value: String
    @State private var note: String
    @State private var nameMissing = false
    @State private var valueProblem = false
    @State private var error: String?

    init(existing: LeadRecord?, onSave: @escaping (LeadRecord) throws -> Void) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _phone = State(initialValue: existing?.phone ?? "")
        _need = State(initialValue: existing?.need ?? "")
        _source = State(initialValue: existing?.source ?? "")
        _value = State(initialValue: existing?.valueCents.map { cents in
            cents % 100 == 0 ? "\(cents / 100)" : String(format: "%.2f", Double(cents) / 100)
        } ?? "")
        _note = State(initialValue: existing?.note ?? "")
    }

    /// The listed sources, plus whatever this lead already says if it is not one of them.
    private var sourceOptions: [(value: String, label: String)] {
        var options = PipelineMath.sources
        if !source.isEmpty, !options.contains(source) { options.insert(source, at: 0) }
        return options.map { (value: $0, label: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            SalesSheetHeader(title: existing == nil ? "New lead" : "Edit lead", saveTitle: "Save",
                             saveIdentifier: "pipeline-save-lead", onCancel: { dismiss() }, onSave: save)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error { SalesProblemLine(message: error) }
                    SalesFormCard {
                        SalesStackedField(label: "Name", text: $name, prompt: "Person or business",
                                          problem: nameMissing ? "Add a name to save." : nil,
                                          content: .name, capitalization: .words)
                        WellDivider(leading: 16)
                        SalesStackedField(label: "Phone", text: $phone, prompt: "(555) 010-0100",
                                          keyboard: .phonePad, content: .telephoneNumber)
                    }
                    SalesFormCard {
                        SalesStackedField(label: "What they need", text: $need, prompt: "Water heater quote, 50 gal gas")
                        WellDivider(leading: 16)
                        ThorbisSelect(options: sourceOptions, selection: $source, label: "Source", placeholder: "Choose")
                            .padding(.horizontal, 16).frame(minHeight: 56)
                        WellDivider(leading: 16)
                        SalesInlineField(label: "Likely value", text: $value, prompt: "$0",
                                         problem: valueProblem ? "Write the value as dollars, like 2400." : nil,
                                         keyboard: .decimalPad)
                    }
                    SalesFormCard {
                        SalesStackedField(label: "Note", text: $note, prompt: "Anything worth remembering before you call",
                                          multiline: true)
                    }
                    SalesPhoneNote(text: "Leads live in Pipeline until you mark them won or lost. Saved on this phone only.")
                }
                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background.ignoresSafeArea())
        .onChange(of: name) { _, _ in nameMissing = false }
        .onChange(of: value) { _, _ in valueProblem = false }
    }

    private func trimmed(_ text: String) -> String? {
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private func save() {
        guard let leadName = trimmed(name) else { nameMissing = true; return }
        var cents: Int?
        if let typed = trimmed(value) {
            let plain = typed.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
            guard let parsed = MoneyInput.cents(plain, maximumCents: 10_000_000_000) else { valueProblem = true; return }
            cents = parsed
        }
        var lead = existing ?? LeadRecord(name: leadName)
        lead.name = leadName
        lead.phone = trimmed(phone)
        lead.need = trimmed(need)
        lead.source = trimmed(source)
        lead.valueCents = cents
        lead.note = trimmed(note)
        do { try onSave(lead); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

#if DEBUG
/// Screenshot fixtures only (`--paper-preview`): Paper 82A's leads in a throwaway folder, never in
/// the real file. Absent from Release builds.
enum PipelinePreviewData {
    @MainActor static func records(organizationID: String) throws -> PipelineRecords {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("paper-preview-pipeline-\(UUID().uuidString)", isDirectory: true)
        let records = try PipelineRecords(organizationID: organizationID, directory: folder)
        let now = Date()
        let day: TimeInterval = 86_400
        let samples: [LeadRecord] = [
            LeadRecord(name: "Gloria Reyes", phone: "(555) 010-0193", need: "wants a quote for a new furnace",
                       source: "Phone call", valueCents: 720_000, createdAt: now.addingTimeInterval(-600)),
            LeadRecord(name: "Mei Chen", phone: "(555) 010-0121", need: "ductless mini-split, 2 rooms",
                       source: "Google", valueCents: 620_000, createdAt: now.addingTimeInterval(-day)),
            LeadRecord(name: "Oakline Dental", phone: "(555) 010-0166", need: "maintenance contract",
                       source: "Referral", valueCents: 480_000, note: "3 rooftop units", createdAt: now.addingTimeInterval(-3 * day)),
            LeadRecord(name: "Tom Becker", phone: "(555) 010-0192", need: "Water heater quote, 50 gal gas",
                       source: "Google", valueCents: 240_000, stage: .visitBooked, createdAt: now.addingTimeInterval(-2 * day)),
            LeadRecord(name: "Ridgeview HOA", need: "Clubhouse AC replacement", source: "Website", valueCents: 980_000,
                       stage: .quoted, createdAt: now.addingTimeInterval(-5 * day)),
        ]
        for lead in samples { try records.save(lead) }
        return records
    }
}
#endif
