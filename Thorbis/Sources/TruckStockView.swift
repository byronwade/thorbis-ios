import SwiftUI

// Paper 84 "Inventory (truck stock)", 84B "Stock item", 84C "Add stock item" and 84A "Restock
// request". The designs draw a warehouse, a price book that counts parts down, and a request sent
// to the office. None of that has a server route, so this place is the person's own count: items
// kept on this phone, + and − by hand, a low state at or under the minimum, and a restock list
// that is shared as text rather than "sent".

/// The stock on screen, bound to one person in one workspace.
@MainActor
final class TruckStockModel: ObservableObject {
    @Published private(set) var items: [TruckStockItem] = []
    @Published private(set) var bound = false
    @Published private(set) var error: String?
    private var store: TruckStockStore?
    private var key: String?

    func bind(organizationID: String?, userID: String?, directory: URL? = nil) {
        let next = "\(organizationID ?? "")|\(userID ?? "")"
        guard next != key else { return }
        key = next
        store = nil
        items = []
        bound = false
        error = nil
        guard let organizationID, let userID else { return }
        do {
            let opened = try TruckStockStore(organizationID: organizationID, userID: userID, directory: directory)
            store = opened
            items = TruckStockRules.sorted(opened.items)
            bound = true
        } catch {
            self.error = "Truck stock on this phone couldn\u{2019}t be opened. \(error.localizedDescription)"
        }
    }

    func item(_ id: String) -> TruckStockItem? { items.first { $0.id == id } }

    private func opened() throws -> TruckStockStore {
        guard let store else { throw Problem(title: "Truck stock is not open on this phone", status: nil, detail: nil) }
        return store
    }

    func save(_ item: TruckStockItem) throws {
        let store = try opened()
        try store.save(item)
        items = TruckStockRules.sorted(store.items)
    }

    func adjust(_ id: String, by delta: Int) throws {
        let store = try opened()
        try store.adjust(id, by: delta)
        items = TruckStockRules.sorted(store.items)
    }

    func remove(_ id: String) throws {
        let store = try opened()
        try store.remove(id)
        items = TruckStockRules.sorted(store.items)
    }
}

/// How stock reads on screen.
enum TruckStockFormat {
    /// "42 items · 4 low"
    static func summary(_ items: [TruckStockItem]) -> String {
        let count = items.count == 1 ? "1 item" : "\(items.count) items"
        let low = TruckStockRules.lowCount(items)
        return low > 0 ? "\(count) \u{00B7} \(low) low" : count
    }

    /// Low: "1 left · keep 6" or "Out · keep 6". Otherwise the part number and the minimum.
    static func rowSubtitle(_ item: TruckStockItem) -> String {
        if TruckStockRules.isLow(item) {
            return "\(item.quantity == 0 ? "Out" : "\(item.quantity) left") \u{00B7} keep \(item.minimum)"
        }
        let part = (item.partNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = item.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        return [part, item.minimum > 0 ? "keep \(item.minimum)" : "no minimum",
                unit.isEmpty || unit.lowercased() == TruckStockRules.defaultUnit ? "" : unit]
            .filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }

    static func matches(_ item: TruckStockItem, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return [item.name, item.partNumber ?? ""].contains { $0.localizedCaseInsensitiveContains(needle) }
    }
}

private struct TruckStockOpen: Hashable { let id: String }

private struct TruckStockEditorRequest: Identifiable {
    let id = UUID()
    var item: TruckStockItem?
}

/// Paper 84's − count +: 44pt circles 2 apart around a 16 Semibold tabular count.
private struct TruckStockStepper: View {
    let name: String
    let quantity: Int
    var low = false
    let step: (Int) -> Void

    private func circle(_ symbol: String, label: String, tint: Bool, enabled: Bool, delta: Int) -> some View {
        Button { step(delta) } label: {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint ? Theme.brandText : Theme.foreground)
                .frame(width: 44, height: 44)
                .background(tint ? Theme.brandSurface : Theme.fill, in: Circle())
                .contentShape(Circle())
                .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityValue("\(quantity) on the truck")
    }

    var body: some View {
        HStack(spacing: 2) {
            circle("minus", label: "One fewer \(name)", tint: false, enabled: quantity > 0, delta: -1)
            Text("\(quantity)").font(Theme.font(16, weight: .semibold)).monospacedDigit()
                .foregroundStyle(Theme.foreground)
                .frame(minWidth: 22)
                .accessibilityHidden(true)
            // Paper 84: the + of a low item is the brand surface, the way back over its minimum.
            circle("plus", label: "One more \(name)", tint: low, enabled: quantity < TruckStockRules.maximumCount, delta: 1)
        }
        .fixedSize()
    }
}

struct TruckStockView: View {
    private enum Filter: Hashable { case all, low }

    @EnvironmentObject private var session: SessionController
    @Environment(\.dynamicTypeSize) private var typeSize
    @StateObject private var model = TruckStockModel()
    @State private var query = ""
    @State private var filter = Filter.all
    @State private var editor: TruckStockEditorRequest?
    @State private var opened: TruckStockOpen?
    @State private var showRestock = false
    @State private var actionError: String?

    init() {}

    private var identityKey: String { "\(session.activeOrganization?.id ?? "")|\(session.user?.id ?? "")" }

    private var subtitle: String {
        guard model.bound, !model.items.isEmpty else { return "On this phone \u{00B7} Counted by hand" }
        return "\(TruckStockFormat.summary(model.items)) \u{00B7} On this phone"
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.muted).accessibilityHidden(true)
            TextField("", text: $query, prompt: .placeholder("Item or part number"))
                .font(Theme.font(16)).foregroundStyle(Theme.foreground)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .frame(minHeight: 46)
                .accessibilityLabel("Search truck stock")
                .accessibilityIdentifier("truckstock-search")
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

    private func adjust(_ item: TruckStockItem, by delta: Int) {
        do {
            try model.adjust(item.id, by: delta)
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// Paper 84: the hexagon (amber when low), the name over what is left, then − count +.
    private func row(_ item: TruckStockItem) -> some View {
        let low = TruckStockRules.isLow(item)
        let subtitle = TruckStockFormat.rowSubtitle(item)
        let words = Button { opened = TruckStockOpen(id: item.id) } label: {
            HStack(alignment: .center, spacing: 0) {
                Image(systemName: "hexagon").font(.system(size: 18, weight: .regular))
                    .foregroundStyle(low ? Theme.warning : Theme.muted)
                    .frame(width: 34, alignment: .leading).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(Theme.font(14)).foregroundStyle(low ? Theme.warning : Theme.muted)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, PaperCardMetrics.inset).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(TruckStockRules.amount(item.quantity, unit: item.unit)) on the truck\(low ? ", low" : "")\(item.minimum > 0 ? ", keep at least \(item.minimum)" : "")")
        .accessibilityHint("Opens the item")
        let stepper = TruckStockStepper(name: item.name, quantity: item.quantity, low: low) { adjust(item, by: $0) }
        return Group {
            if typeSize.isAccessibilitySize {
                // Large text: the count sits under the words instead of squeezing them.
                VStack(alignment: .leading, spacing: 0) {
                    words
                    stepper.padding(.leading, PaperCardMetrics.inset + 34).padding(.bottom, 8)
                }
            } else {
                HStack(spacing: 8) {
                    words
                    stepper
                }
                .padding(.trailing, 10)
            }
        }
    }

    private func rows(_ list: [TruckStockItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(list) { item in
                if item.id != list.first?.id { WellDivider() }
                row(item)
            }
        }
    }

    var body: some View {
        let matching = model.items.filter { TruckStockFormat.matches($0, query: query) }
        let low = matching.filter(TruckStockRules.isLow)
        let rest = filter == .low ? [] : matching.filter { !TruckStockRules.isLow($0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Paper 84: the place header, the search, then the segments.
                PaperHeader(title: "Truck stock", subtitle: subtitle, showsCreate: model.bound)
                    .environment(\.paperCreate, model.bound
                                 ? PaperCreateAction(label: "Add stock item", run: { editor = TruckStockEditorRequest() })
                                 : nil)
                if model.bound && !model.items.isEmpty {
                    searchField.padding(.top, 2)
                    ThorbisSegmented(options: [(Filter.all, "All items"), (Filter.low, "Low stock")], selection: $filter)
                        .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 16)
                        .accessibilityIdentifier("truckstock-filter")
                }
                VStack(alignment: .leading, spacing: 20) {
                    if let message = actionError ?? model.error {
                        Text(message).font(Theme.font(15)).foregroundStyle(Theme.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
                    }
                    if !model.bound {
                        if model.error == nil { SkeletonRows(count: 3, leading: false, inset: 0) }
                    } else if model.items.isEmpty {
                        PaperEmptyState(symbol: "shippingbox", title: "No stock yet",
                                        message: "Add what you carry and the count it shouldn\u{2019}t fall below. Low items collect into a restock list.",
                                        actionTitle: "Add stock item") { editor = TruckStockEditorRequest() }
                    } else if matching.isEmpty {
                        PaperEmptyState(symbol: "magnifyingglass", title: "No matches",
                                        message: "No item or part number matches \u{201C}\(query)\u{201D}.",
                                        actionTitle: "Clear search") { query = "" }
                    } else if filter == .low && low.isEmpty {
                        PaperEmptyState(symbol: "checkmark.circle", title: "Nothing is low",
                                        message: "Items at or under their minimum show here.",
                                        actionTitle: "Show all") { filter = .all }
                    } else {
                        if !low.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                // Paper 84: a 6pt warning dot, "Running low", and "Restock all" in
                                // the brand ink; here that opens the list to share.
                                HStack(alignment: .center, spacing: 6) {
                                    Circle().fill(Theme.warning).frame(width: 6, height: 6).accessibilityHidden(true)
                                    Text("Running low").font(Theme.font(13, weight: .semibold))
                                        .foregroundStyle(Theme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .accessibilityLabel("Running low, \(low.count)")
                                        .accessibilityAddTraits(.isHeader)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Button { showRestock = true } label: {
                                        Text("Restock list").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.brandText)
                                            .frame(minWidth: 44, minHeight: 44, alignment: .trailing).contentShape(Rectangle())
                                    }
                                    .buttonStyle(PressStyle())
                                    .accessibilityIdentifier("truckstock-restock")
                                }
                                .padding(.horizontal, 4)
                                PaperCard { rows(low) }
                            }
                        }
                        if !rest.isEmpty {
                            PaperSection("On the truck", count: rest.count) { rows(rest) }
                        }
                    }
                    if model.bound {
                        Text("Counts are saved on this phone only and change when you change them here. Parts used on a job don\u{2019}t count down on their own.")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
                    }
                }
                .paperCardMargin().padding(.top, 14).padding(.bottom, 24)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("truckstock-root")
        .sensoryFeedback(.selection, trigger: model.items.reduce(0) { $0 + $1.quantity })
        .task(id: identityKey) {
            editor = nil
            opened = nil
            showRestock = false
            actionError = nil
            model.bind(organizationID: session.activeOrganization?.id, userID: session.user?.id)
        }
        .thorbisDestination(item: $opened) { TruckStockItemView(id: $0.id, model: model) }
        .sheet(item: $editor) { request in SheetSurface {
            TruckStockEditor(existing: request.item) { saved in
                try model.save(saved)
                actionError = nil
            }
        } }
        .sheet(isPresented: $showRestock) { SheetSurface { TruckRestockSheet(items: model.items) } }
    }
}

/// Paper 84B "Stock item": the name, Low beside where it is kept, the three figures, the count's
/// − and +, then its details. "Used in July", price and "Latest uses" need a price book and job
/// usage the phone doesn't have, so they are not drawn.
private struct TruckStockItemView: View {
    let id: String
    @ObservedObject var model: TruckStockModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var editor: TruckStockEditorRequest?
    @State private var confirmRemove = false
    @State private var actionError: String?

    private func figure(_ value: String, _ label: String, tint: Color = Theme.foreground) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.font(30, weight: .bold)).monospacedDigit().foregroundStyle(tint)
            Text(label).font(Theme.font(13)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
    }

    private func page(_ item: TruckStockItem) -> some View {
        let low = TruckStockRules.isLow(item)
        let part = (item.partNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        return VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name).font(Theme.font(34, weight: .bold)).tracking(-0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 8) {
                    if low {
                        Text("Low").font(Theme.font(12, weight: .semibold)).foregroundStyle(Theme.warning)
                            .padding(.horizontal, 10).frame(minHeight: 24)
                            .background(Theme.warningSurface, in: Capsule())
                    }
                    Text("My truck \u{00B7} On this phone").font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
            if let actionError {
                Text(actionError).font(Theme.font(15)).foregroundStyle(Theme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
            }
            PaperCard {
                layout {
                    figure("\(item.quantity)", "On the truck", tint: low ? Theme.warning : Theme.foreground)
                    figure(item.minimum > 0 ? "\(item.minimum)" : "\u{2013}", "Keep at least")
                    figure(low ? "\(TruckStockRules.needed(item))" : "0", "To restock")
                }
            }
            PaperCard {
                HStack(spacing: 8) {
                    Text("Count").font(Theme.font(16)).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    TruckStockStepper(name: item.name, quantity: item.quantity, low: low) { delta in
                        do {
                            try model.adjust(item.id, by: delta)
                            actionError = nil
                        } catch {
                            actionError = error.localizedDescription
                        }
                    }
                }
                .padding(.leading, PaperCardMetrics.inset).padding(.trailing, 8).frame(minHeight: 60)
            }
            PaperSection(title: "Details") {
                VStack(alignment: .leading, spacing: 0) {
                    PaperDetailRow("Part number", value: part.isEmpty ? "None" : part)
                        .padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 52)
                    WellDivider()
                    PaperDetailRow("Unit", value: item.unit.isEmpty ? TruckStockRules.defaultUnit : item.unit)
                        .padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 52)
                }
            } accessory: {
                Button { editor = TruckStockEditorRequest(item: item) } label: {
                    Text("Edit").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.brandText)
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Edit stock item")
                .accessibilityIdentifier("truckstock-edit")
            }
            Text("Saved on this phone only. The count changes when you change it here.")
                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
        }
    }

    var body: some View {
        let item = model.item(id)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let item {
                    page(item)
                } else {
                    Text("This item is no longer on this phone.").font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .paperCardMargin().padding(.top, 8).padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: item?.quantity ?? 0)
        .toolbar {
            if item != nil {
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    ThorbisMenu(items: [
                        ThorbisMenuItem("Edit", icon: "pencil") { editor = model.item(id).map { TruckStockEditorRequest(item: $0) } },
                        ThorbisMenuItem("Remove", icon: "trash", role: .destructive) { confirmRemove = true },
                    ], accessibilityLabel: "Stock item actions") {
                        PaperCircleLabel(symbol: "ellipsis", size: 44, fill: Theme.card)
                    }
                    .accessibilityIdentifier("truckstock-actions")
                }
            }
        }
        .sheet(item: $editor) { request in SheetSurface {
            TruckStockEditor(existing: request.item) { saved in
                try model.save(saved)
                actionError = nil
            }
        } }
        .thorbisConfirm("Remove \(item?.name ?? "this item")?",
                        message: "It comes off your truck stock on this phone. This can\u{2019}t be undone.",
                        isPresented: $confirmRemove,
                        actions: [ThorbisConfirmAction("Remove", role: .destructive) {
                            do {
                                try model.remove(id)
                                dismiss()
                            } catch {
                                actionError = error.localizedDescription
                            }
                        }])
    }
}

/// Paper 84C "Add stock item": Cancel and Save in the title row, the item on one card, the two
/// counts with − and + on the next. The design picks the item from the price book and a truck from
/// a list; here it is typed, and it says where it is saved.
private struct TruckStockEditor: View {
    private enum Field: Hashable { case name, part, quantity, minimum, unit }

    let existing: TruckStockItem?
    let onSave: (TruckStockItem) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var part: String
    @State private var quantity: Int
    @State private var minimum: Int
    @State private var unit: String
    @State private var nameMissing = false
    @State private var error: String?
    @FocusState private var focus: Field?

    init(existing: TruckStockItem?, onSave: @escaping (TruckStockItem) throws -> Void) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _part = State(initialValue: existing?.partNumber ?? "")
        _quantity = State(initialValue: existing?.quantity ?? 0)
        _minimum = State(initialValue: existing?.minimum ?? 0)
        _unit = State(initialValue: existing?.unit ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error {
                        Text(error).font(Theme.font(15)).foregroundStyle(Theme.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        stacked("Item", prompt: "Run capacitor 45/5 \u{00B5}F",
                                text: Binding(get: { name }, set: { name = $0; nameMissing = false }), field: .name,
                                problem: nameMissing ? "Add the item\u{2019}s name to save." : nil, identifier: "truckstock-name")
                        WellDivider(leading: 16)
                        stacked("Part number", prompt: "Optional", text: $part, field: .part, problem: nil,
                                identifier: "truckstock-part")
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    VStack(alignment: .leading, spacing: 0) {
                        countRow("On the truck now", value: $quantity, field: .quantity, identifier: "truckstock-quantity")
                        WellDivider(leading: 16)
                        countRow("Keep at least", value: $minimum, field: .minimum, identifier: "truckstock-minimum")
                        WellDivider(leading: 16)
                        HStack(spacing: 8) {
                            Text("Unit").font(Theme.font(16)).foregroundStyle(Theme.foreground).accessibilityHidden(true)
                            Spacer(minLength: 8)
                            TextField("", text: $unit, prompt: .placeholder(TruckStockRules.defaultUnit))
                                .font(Theme.font(16)).foregroundStyle(Theme.muted)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .focused($focus, equals: .unit)
                                .accessibilityLabel("Unit")
                                .accessibilityIdentifier("truckstock-unit")
                        }
                        .padding(.horizontal, 16).frame(minHeight: 56)
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    Text("It shows as low when the count is at or under \u{201C}Keep at least\u{201D}; leave that at 0 for no minimum. Saved on this phone only, and parts used on jobs don\u{2019}t count down on their own.")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background.ignoresSafeArea())
    }

    private var header: some View {
        ZStack {
            Text(existing == nil ? "Add stock item" : "Edit stock item").font(Theme.font(17, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 100)
            HStack {
                Button { dismiss() } label: {
                    Text("Cancel").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .background(Theme.card, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                Spacer(minLength: 8)
                // Never pre-disabled: pressed without a name, it says so under the field.
                Button { save() } label: {
                    Text("Save").font(Theme.font(16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).frame(minHeight: 44)
                        .background(Theme.brand, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("truckstock-save")
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 2)
    }

    private func stacked(_ label: String, prompt: String, text: Binding<String>, field: Field,
                         problem: String?, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.font(13)).foregroundStyle(Theme.muted).accessibilityHidden(true)
            TextField("", text: text, prompt: .placeholder(prompt))
                .font(Theme.font(17, weight: .medium))
                .frame(minHeight: 28)
                .autocorrectionDisabled()
                .focused($focus, equals: field)
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier)
            if let problem { FieldProblem(message: problem) }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    }

    /// Paper 84C: the label, then − count +. The count can also be typed, for a box of 250.
    private func countRow(_ label: String, value: Binding<Int>, field: Field, identifier: String) -> some View {
        let typed = Binding<String>(
            get: { "\(value.wrappedValue)" },
            set: { text in
                let digits = text.filter(\.isNumber)
                value.wrappedValue = min(TruckStockRules.maximumCount, Int(digits) ?? 0)
            })
        return HStack(spacing: 4) {
            Text(label).font(Theme.font(16)).foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            Spacer(minLength: 8)
            countCircle("minus", label: "One fewer, \(label.lowercased())", enabled: value.wrappedValue > 0) {
                value.wrappedValue = TruckStockRules.stepped(value.wrappedValue, by: -1)
            }
            TextField("", text: typed)
                .font(Theme.font(17, weight: .semibold)).monospacedDigit()
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .frame(width: 52).frame(minHeight: 44)
                .focused($focus, equals: field)
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier)
            countCircle("plus", label: "One more, \(label.lowercased())", enabled: value.wrappedValue < TruckStockRules.maximumCount) {
                value.wrappedValue = TruckStockRules.stepped(value.wrappedValue, by: 1)
            }
        }
        .padding(.leading, 16).padding(.trailing, 8).frame(minHeight: 56)
    }

    private func countCircle(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.foreground)
                .frame(width: 36, height: 36)
                .background(Theme.fill, in: Circle())
                .frame(width: 44, height: 44).contentShape(Rectangle())
                .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func save() {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            nameMissing = true
            focus = .name
            return
        }
        let number = part.trimmingCharacters(in: .whitespacesAndNewlines)
        let word = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = TruckStockItem(id: existing?.id ?? UUID().uuidString, name: title,
                                  partNumber: number.isEmpty ? nil : number, quantity: quantity, minimum: minimum,
                                  unit: word.isEmpty ? TruckStockRules.defaultUnit : word,
                                  createdAt: existing?.createdAt ?? Date())
        do {
            try onSave(item)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Paper 84A "Restock request": everything at or under its minimum and how many to get. The design
/// sends the request to a warehouse; there is no office route for that, so the commit shares the
/// list as text and never says it was sent.
private struct TruckRestockSheet: View {
    let items: [TruckStockItem]
    @Environment(\.dismiss) private var dismiss
    @State private var shared: SharedText?

    var body: some View {
        let lines = TruckStockRules.restockList(items)
        VStack(spacing: 0) {
            ZStack {
                Text("Restock list").font(Theme.font(17, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 100)
                HStack {
                    Button { dismiss() } label: {
                        Text("Close").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                            .padding(.horizontal, 16).frame(minHeight: 44)
                            .background(Theme.card, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle())
                    Spacer(minLength: 8)
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 2)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if lines.isEmpty {
                        PaperEmptyState(symbol: "checkmark.circle", title: "Nothing is low",
                                        message: "Items at or under their minimum collect here.")
                    } else {
                        PaperSection(lines.count == 1 ? "1 item at or under its minimum" : "\(lines.count) items at or under their minimum") {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(lines) { line in
                                    if line.id != lines.first?.id { WellDivider() }
                                    row(line)
                                }
                            }
                        }
                        Text("Share sends this list as text through the app you pick. Thorbis doesn\u{2019}t send it to the office or a supplier.")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !lines.isEmpty {
                PaperActionBar(title: "Share list", symbol: "square.and.arrow.up", identifier: "truckstock-share-restock") {
                    if let text = TruckStockRules.restockText(items) { shared = SharedText(text) }
                }
            }
        }
        .sheet(item: $shared) { TextShareSheet(text: $0.text) }
    }

    /// Paper 84A: the item over "Have 1 · keep 4" (amber "Out" when there are none), then how many to get.
    private func row(_ line: TruckRestockLine) -> some View {
        let part = (line.item.partNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let have = line.item.quantity == 0 ? "Out" : "Have \(line.item.quantity)"
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.item.name).font(Theme.font(16, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text([have, "keep \(line.item.minimum)", part].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                    .font(Theme.font(14)).foregroundStyle(line.item.quantity == 0 ? Theme.warning : Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text("Get \(TruckStockRules.amount(line.needed, unit: line.item.unit))")
                .font(Theme.font(15, weight: .semibold)).monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
