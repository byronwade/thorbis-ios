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
            var preview: TruckStockStore?
            #if DEBUG
            if PaperPreview.enabled, directory == nil {
                preview = try PlacesPreviewData.truckStock(organizationID: organizationID, userID: userID)
            }
            #endif
            let opened = try preview ?? TruckStockStore(organizationID: organizationID, userID: userID, directory: directory)
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
            return "\(item.quantity == 0 ? "Out" : "\(item.quantity) left") \u{00B7} par \(item.minimum)"
        }
        let part = (item.partNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = item.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        return [part, item.minimum > 0 ? "par \(item.minimum)" : "no par",
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

    private func circle(_ glyph: PaperGlyph, label: String, tint: Bool, enabled: Bool, delta: Int) -> some View {
        Button { step(delta) } label: {
            PaperIcon(glyph, size: 12, color: tint ? Theme.brandText : Theme.foreground)
                .frame(width: 44, height: 44)
                .background(tint ? Theme.brandTint : Theme.quietFill, in: Circle())
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
            circle(.placeMinus, label: "One fewer \(name)", tint: false, enabled: quantity > 0, delta: -1)
            Text("\(quantity)").font(Theme.font(16, weight: .semibold))
                .foregroundStyle(Theme.foreground)
                .frame(minWidth: 22)
                .accessibilityHidden(true)
            // Paper 84: the + of a low item is brand-tinted, the way back over its minimum.
            circle(.placeStepPlus, label: "One more \(name)", tint: low, enabled: quantity < TruckStockRules.maximumCount, delta: 1)
        }
        .fixedSize()
    }
}

/// Paper 84 "Inventory (truck stock)": the title over "42 items · 4 low", the search field, the
/// segments, "Running low" with − count + on each row, then the rest with their counts, and the +
/// circle at the foot. Paper's Warehouse segment and "Scan to use" pill need a server and a part
/// catalogue the phone doesn't have, so they are left out.
struct TruckStockView: View {
    @EnvironmentObject private var session: SessionController
    @Environment(\.dynamicTypeSize) private var typeSize
    @StateObject private var model = TruckStockModel()
    @State private var query = ""
    @State private var tab = "My truck"
    @State private var editor: TruckStockEditorRequest?
    @State private var opened: TruckStockOpen?
    @State private var showRestock = false
    @State private var actionError: String?

    init() {}

    private var identityKey: String { "\(session.activeOrganization?.id ?? "")|\(session.user?.id ?? "")" }

    private var subtitle: String {
        guard model.bound, !model.items.isEmpty else { return "Counted by hand \u{00B7} kept on this phone" }
        return "\(TruckStockFormat.summary(model.items)) \u{00B7} on this phone"
    }

    private func adjust(_ item: TruckStockItem, by delta: Int) {
        do {
            try model.adjust(item.id, by: delta)
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// Paper 84: the hexagon in a 34pt slot (amber when low), the name over what is left, then
    /// − count + on a low row and the plain count on the rest. 64 tall.
    private func row(_ item: TruckStockItem) -> some View {
        let low = TruckStockRules.isLow(item)
        let subtitle = TruckStockFormat.rowSubtitle(item)
        let stacked = typeSize.isAccessibilitySize
        let words = Button { opened = TruckStockOpen(id: item.id) } label: {
            HStack(alignment: .center, spacing: 0) {
                PaperIcon(.placeHex, size: 20, color: low ? Theme.warning : Theme.muted)
                    .frame(width: 34, alignment: .leading)
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.name).font(Theme.font(16, weight: .medium)).tracking(-0.16).foregroundStyle(Theme.foreground)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(Theme.font(14)).foregroundStyle(low ? Theme.warning : Theme.muted)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                if !low {
                    Text("\(item.quantity)").font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                        .frame(minWidth: 28, alignment: .trailing)
                        .padding(.trailing, 16)
                }
            }
            .padding(.leading, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(TruckStockRules.amount(item.quantity, unit: item.unit)) on the truck\(low ? ", low" : "")\(item.minimum > 0 ? ", par \(item.minimum)" : "")")
        .accessibilityHint("Opens the item")
        let stepper = TruckStockStepper(name: item.name, quantity: item.quantity, low: low) { adjust(item, by: $0) }
        return Group {
            if !low {
                words
            } else if stacked {
                // Large text: the count sits under the words instead of squeezing them.
                VStack(alignment: .leading, spacing: 0) {
                    words
                    stepper.padding(.leading, 50).padding(.bottom, 8)
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

    @ViewBuilder private func rows(_ list: [TruckStockItem]) -> some View {
        ForEach(list) { item in
            if item.id != list.first?.id { WellDivider(leading: 50) }
            row(item)
        }
    }

    /// Paper 84's foot: the 50pt + circle at the trailing edge (beside where Paper's scan pill sits).
    private var bar: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button { editor = TruckStockEditorRequest() } label: {
                PaperIcon(.plusLight, size: 20)
                    .frame(width: 50, height: 50)
                    .background(Theme.card, in: Circle())
                    .background(Theme.quietFill, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Add stock item")
            .accessibilityIdentifier("header-create")
        }
        .padding(.horizontal, PaperCardMetrics.margin).padding(.bottom, 8)
    }

    var body: some View {
        let matching = model.items.filter { TruckStockFormat.matches($0, query: query) }
        let low = matching.filter(TruckStockRules.isLow)
        let rest = tab == "Low stock" ? [] : matching.filter { !TruckStockRules.isLow($0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Paper 84: the place header (menu circle only), the search, then the segments.
                PaperHeader(title: "Truck stock", subtitle: subtitle)
                if model.bound && !model.items.isEmpty {
                    PlaceSearchField(query: $query, identifier: "truckstock-search")
                    PaperTabs(options: ["My truck", "Low stock"], selection: $tab)
                        .padding(.top, 16)
                        .accessibilityIdentifier("truckstock-filter")
                }
                if let message = actionError ?? model.error {
                    Text(message).font(Theme.font(15)).foregroundStyle(Theme.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.gutter).padding(.top, 14)
                }
                if !model.bound {
                    if model.error == nil { SkeletonRows(count: 3, leading: false, inset: 0).paperCardMargin().padding(.top, 22) }
                } else if model.items.isEmpty {
                    PaperEmptyState(symbol: "shippingbox", title: "No stock yet",
                                    message: "Add what you carry and the count it shouldn\u{2019}t fall below. Low items collect into a restock list. Counts stay on this phone.",
                                    actionTitle: "Add stock item") { editor = TruckStockEditorRequest() }
                        .paperCardMargin().padding(.top, 22)
                } else if matching.isEmpty {
                    PaperEmptyState(symbol: "magnifyingglass", title: "No matches",
                                    message: "No item or part number matches \u{201C}\(query)\u{201D}.",
                                    actionTitle: "Clear search") { query = "" }
                        .paperCardMargin().padding(.top, 22)
                } else if tab == "Low stock" && low.isEmpty {
                    PaperEmptyState(symbol: "checkmark.circle", title: "Nothing is low",
                                    message: "Items at or under their par show here.",
                                    actionTitle: "Show all") { tab = "My truck" }
                        .paperCardMargin().padding(.top, 22)
                } else {
                    if !low.isEmpty {
                        // Paper 84: a 6pt warning dot, "Running low", and "Restock all" in the
                        // brand ink; here that opens the list to share.
                        HStack(alignment: .center, spacing: 6) {
                            Circle().fill(Theme.statusInProgress).frame(width: 6, height: 6).accessibilityHidden(true)
                            Text("Running low").font(Theme.font(13, weight: .semibold))
                                .foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel("Running low, \(low.count)")
                                .accessibilityAddTraits(.isHeader)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button { showRestock = true } label: {
                                Text("Restock all").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.brandText)
                                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing).contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle())
                            .padding(.vertical, -13)
                            .accessibilityHint("Opens the restock list to share")
                            .accessibilityIdentifier("truckstock-restock")
                        }
                        .padding(.horizontal, PaperCardMetrics.margin + 4)
                        .padding(.top, 16).padding(.bottom, 8)
                        PaperRowsCard { rows(low) }
                    }
                    if !rest.isEmpty {
                        PaperCardLabel(title: "On the truck", count: rest.count).padding(.top, 22)
                        PaperRowsCard { rows(rest) }
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("truckstock-root")
        .safeAreaInset(edge: .bottom, spacing: 0) { if model.bound { bar } }
        .sensoryFeedback(.selection, trigger: model.items.reduce(0) { $0 + $1.quantity })
        .task(id: identityKey) {
            editor = nil
            opened = nil
            showRestock = false
            actionError = nil
            model.bind(organizationID: session.activeOrganization?.id, userID: session.user?.id)
            #if DEBUG
            if PaperPreview.enabled {
                switch PaperPreview.screen {
                case "truck-stock-item": opened = model.items.first { $0.name.hasPrefix("Run cap") }.map { TruckStockOpen(id: $0.id) }
                case "truck-stock-add": editor = TruckStockEditorRequest()
                case "truck-stock-restock": showRestock = true
                default: break
                }
            }
            #endif
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
    @State private var restock = false
    @State private var counting = false

    private func figure(_ value: String, _ label: String, tint: Color = Theme.foreground) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.font(34, weight: .bold)).tracking(-0.68).foregroundStyle(tint)
            Text(label).font(Theme.font(13)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
    }

    private var rule: some View {
        Rectangle().fill(Theme.border).frame(width: typeSize.isAccessibilitySize ? nil : 1, height: typeSize.isAccessibilitySize ? 1 : nil)
            .accessibilityHidden(true)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        PlaceSheetValueRow(label: label, value: value, minHeight: 52)
    }

    private func page(_ item: TruckStockItem) -> some View {
        let low = TruckStockRules.isLow(item)
        let part = (item.partNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let needed = TruckStockRules.needed(item)
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 0))
        let pills = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return VStack(alignment: .leading, spacing: 12) {
            // Paper 84B: the name in 28 Bold, then Low beside where the stock is.
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name).font(Theme.heading()).tracking(-0.56)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 8) {
                    if low {
                        Text("Low").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.warning)
                            .padding(.horizontal, 10).frame(minHeight: PaperControl.statusHeight)
                            .background(Theme.warningSurface, in: Capsule())
                    }
                    Text("My truck \u{00B7} on this phone").font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
            .padding(.bottom, 4)
            if let actionError {
                Text(actionError).font(Theme.font(15)).foregroundStyle(Theme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
            }
            // Paper's third figure is "Used in July"; uses aren't recorded here, so it is what to get.
            layout {
                figure("\(item.quantity)", "On the truck", tint: low ? Theme.warning : Theme.foreground)
                rule
                figure(item.minimum > 0 ? "\(item.minimum)" : "\u{2013}", "Par")
                rule
                figure("\(needed)", "To restock")
            }
            .padding(.vertical, 16).padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            pills {
                if low {
                    Button { restock = true } label: {
                        Text("Request \(needed) more").paperButton(.commit, tone: .brand, fills: true)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityHint("Opens the restock list to share")
                    .accessibilityIdentifier("truckstock-request")
                }
                Button { counting = true } label: {
                    Text("Fix count").font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .frame(minWidth: 130, maxWidth: low && !typeSize.isAccessibilitySize ? 130 : .infinity, minHeight: 50)
                        .background(Theme.quietFill, in: Capsule()).contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("truckstock-fix-count")
            }
            TimeClockCard {
                fact("Part number", part.isEmpty ? "None" : part)
                WellDivider(leading: 0)
                fact("Unit", item.unit.isEmpty ? TruckStockRules.defaultUnit : item.unit)
            }
            Text("Saved on this phone only. The count changes when you change it here; parts used on jobs don\u{2019}t count down on their own.")
                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
                .padding(.top, 4)
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
            .paperCardMargin().padding(.top, 14).padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: item?.quantity ?? 0)
        .sheet(isPresented: $restock) { SheetSurface { TruckRestockSheet(items: item.map { [$0] } ?? []) } }
        .sheet(isPresented: $counting) { SheetSurface {
            if let item {
                TruckStockCountSheet(item: item) { count in
                    try model.adjust(item.id, by: count - (model.item(id)?.quantity ?? item.quantity))
                    actionError = nil
                }
            }
        } }
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
                        countRow("Keep at least (par)", value: $minimum, field: .minimum, identifier: "truckstock-minimum")
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
            SalesSheetHeader(title: "Restock list", saveTitle: nil, onCancel: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if lines.isEmpty {
                        PaperEmptyState(symbol: "checkmark.circle", title: "Nothing is low",
                                        message: "Items at or under their minimum collect here.")
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("My truck \u{00B7} \(lines.count == 1 ? "1 item" : "\(lines.count) items") below par")
                                .font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 4).accessibilityAddTraits(.isHeader)
                            TimeClockCard {
                                ForEach(lines) { line in
                                    if line.id != lines.first?.id { WellDivider(leading: 0) }
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
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 24)
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

    /// Paper 84A: the item over "Have 1 \u{00B7} par 4" (amber "Out" when there are none), then how
    /// many to get on the quiet capsule. Paper steps that figure; here it is the gap to par.
    private func row(_ line: TruckRestockLine) -> some View {
        let part = (line.item.partNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let have = line.item.quantity == 0 ? "Out" : "Have \(line.item.quantity)"
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(line.item.name).font(Theme.font(16, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text([have, "par \(line.item.minimum)", part].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                    .font(Theme.font(14)).foregroundStyle(line.item.quantity == 0 ? Theme.warning : Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text("Get \(TruckStockRules.amount(line.needed, unit: line.item.unit))")
                .font(Theme.font(15, weight: .semibold))
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 16).frame(minHeight: 44)
                .background(Theme.fill, in: Capsule())
        }
        .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Paper 84B's "Fix count": the count as it really is on the truck, set with the same − and + as
/// Paper 84C, then saved.
private struct TruckStockCountSheet: View {
    let item: TruckStockItem
    let onSave: (Int) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var count: Int
    @State private var error: String?

    init(item: TruckStockItem, onSave: @escaping (Int) throws -> Void) {
        self.item = item
        self.onSave = onSave
        _count = State(initialValue: item.quantity)
    }

    var body: some View {
        VStack(spacing: 0) {
            SalesSheetHeader(title: "Fix count", saveIdentifier: "truckstock-count-save", onCancel: { dismiss() }) {
                do { try onSave(count); dismiss() } catch { self.error = error.localizedDescription }
            }
            VStack(alignment: .leading, spacing: 12) {
                if let error { SalesProblemLine(message: error) }
                TimeClockCard {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("On the truck now").font(Theme.font(16)).foregroundStyle(Theme.foreground)
                            Text(item.name).font(Theme.font(14)).foregroundStyle(Theme.muted)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        SalesQuantityStepper(value: count, range: 0...TruckStockRules.maximumCount, name: item.name) { count = $0 }
                    }
                    .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 10)
                    .frame(minHeight: 66)
                }
                Text("Saved on this phone only.").font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16).padding(.top, 16)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background.ignoresSafeArea())
        .presentationDetents([.height(260), .large])
    }
}
