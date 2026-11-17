import SwiftUI

/// Opens one workspace's vendor file and tells the screens when it changes.
@MainActor
final class VendorsBook: ObservableObject {
    @Published private(set) var organizationID: String?
    @Published private(set) var error: String?
    @Published private(set) var revision = 0
    private var storage: VendorsRecords?

    var isOpen: Bool { storage != nil }
    var vendors: [VendorRecord] { storage?.vendors ?? [] }
    var orders: [PurchaseOrderRecord] { storage?.orders ?? [] }
    func vendor(_ id: String) -> VendorRecord? { storage?.vendor(id) }
    func order(_ id: String) -> PurchaseOrderRecord? { storage?.order(id) }
    func orders(for vendorID: String) -> [PurchaseOrderRecord] { storage?.orders(for: vendorID) ?? [] }

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
                storage = try VendorsPreviewData.records(organizationID: organizationID)
                self.organizationID = organizationID
                revision += 1
                return
            }
            #endif
            storage = try VendorsRecords(organizationID: organizationID)
            self.organizationID = organizationID
        } catch {
            self.error = error.localizedDescription
        }
        revision += 1
    }

    /// Runs one change against the file and redraws.
    @discardableResult
    func change<Result>(_ work: (VendorsRecords) throws -> Result) throws -> Result {
        guard let storage else { throw Problem(title: "No workspace is open", status: nil, detail: nil) }
        let result = try work(storage)
        revision += 1
        return result
    }
}

enum VendorsRoute: Hashable {
    case vendor(String)
    case order(String)
}

/// A vendor being added or edited in the sheet.
struct VendorDraft: Identifiable {
    let id: String
    let existing: VendorRecord?
    init(_ existing: VendorRecord? = nil) { self.existing = existing; self.id = existing?.id ?? UUID().uuidString }
}

/// A new purchase order being started, for a vendor when it was started from one.
struct PurchaseOrderStart: Identifiable {
    let id = UUID()
    var vendorID: String?
}

/// Paper 42 and 43 "Vendors": the place header, a search, then Vendors and Purchase orders as two
/// tabs. Everything here is kept on this phone for the open workspace, and the page says so.
struct VendorsAndOrdersView: View {
    enum Tab: Hashable, CaseIterable {
        case vendors, orders
        var title: String { self == .vendors ? "Vendors" : "Purchase orders" }
    }

    @EnvironmentObject private var session: SessionController
    @StateObject private var book = VendorsBook()
    @State private var tab: Tab = .vendors
    @State private var query = ""
    @State private var openOnly = true
    @State private var route: VendorsRoute?
    @State private var vendorDraft: VendorDraft?
    @State private var orderStart: PurchaseOrderStart?
    @State private var actionError: String?

    init() {}

    private var organizationID: String? { session.activeOrganization?.id }

    private func matches(_ vendor: VendorRecord) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return [vendor.name, vendor.contact ?? "", vendor.accountNumber ?? ""].contains { $0.localizedCaseInsensitiveContains(needle) }
    }

    private func matches(_ order: PurchaseOrderRecord) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return [order.numberLabel, order.vendorName, order.note ?? ""].contains { $0.localizedCaseInsensitiveContains(needle) }
            || order.lines.contains { $0.description.localizedCaseInsensitiveContains(needle) }
    }

    private var subtitle: String {
        // Paper: "Company operations · 3 vendors". These are kept on this phone, so it says that.
        guard book.isOpen else { return "Kept on this phone" }
        switch tab {
        case .vendors:
            let count = book.vendors.count
            return "On this phone \u{00B7} \(count == 1 ? "1 vendor" : "\(count) vendors")"
        case .orders:
            let open = book.orders.filter(\.isOpen).count
            return "On this phone \u{00B7} \(open == 1 ? "1 open PO" : "\(open) open POs")"
        }
    }

    private func startCreate() {
        switch tab {
        case .vendors: vendorDraft = VendorDraft()
        case .orders:
            // A purchase order is made for a vendor, so the first vendor comes first.
            if book.vendors.isEmpty { vendorDraft = VendorDraft() } else { orderStart = PurchaseOrderStart() }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaperHeader(title: "Vendors", subtitle: subtitle)
                // Paper 42 / 43: the search field (the PO tab holds "Open" as a chip), then the segments.
                PlaceSearchField(query: $query,
                                 chips: tab == .orders && openOnly
                                     ? [PaperFilterChip(id: "open", title: "Open") { openOnly = false }] : [],
                                 identifier: "vendors-search") {
                    if tab == .orders {
                        ThorbisMenu(items: [
                            ThorbisMenuItem("Open", icon: openOnly ? "checkmark" : "tray") { openOnly = true },
                            ThorbisMenuItem("All purchase orders", icon: openOnly ? "tray.full" : "checkmark") { openOnly = false },
                        ], title: "Show", accessibilityLabel: "Filter purchase orders") {
                            PaperFilterCircle(active: false)
                        }
                        .accessibilityIdentifier("header-filter")
                    }
                }
                PaperTabs(options: Tab.allCases.map(\.title), selection: Binding(
                    get: { tab.title }, set: { title in tab = Tab.allCases.first { $0.title == title } ?? .vendors }))
                    .padding(.top, 16)
                if let error = actionError ?? book.error {
                    SalesProblemLine(message: error).paperCardMargin().padding(.top, 14)
                }
                if !book.isOpen && book.error == nil {
                    if organizationID == nil {
                        PaperEmptyState(symbol: "building.2", title: "No workspace is open",
                                        message: "Vendors are kept for each workspace. Open one to see them.")
                            .padding(.top, 22)
                    } else {
                        SkeletonRows(count: 3, leading: false, inset: 0).paperCardMargin().padding(.top, 22)
                    }
                } else if book.isOpen {
                    switch tab {
                    case .vendors: vendorsTab
                    case .orders: ordersTab
                    }
                    PlacePhoneLine(text: "Kept on this phone \u{00B7} your team doesn\u{2019}t see these")
                        .padding(.top, 16)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("vendors-root")
        .placeBarCreate(tab == .vendors ? "Add vendor" : "New purchase order", shows: book.isOpen, action: startCreate)
        .task(id: organizationID) {
            route = nil; vendorDraft = nil; orderStart = nil; actionError = nil
            book.bind(organizationID: organizationID)
            #if DEBUG
            if PaperPreview.enabled, PaperPreview.screen == "vendors-orders" { tab = .orders }
            #endif
        }
        .thorbisDestination(item: $route) { route in
            switch route {
            case .vendor(let id): VendorDetailView(vendorID: id, book: book)
            case .order(let id): PurchaseOrderDetailView(orderID: id, book: book)
            }
        }
        .sheet(item: $vendorDraft) { draft in SheetSurface {
            VendorEditorSheet(existing: draft.existing) { vendor in
                try book.change { try $0.save(vendor) }
                actionError = nil
            }
        } }
        .sheet(item: $orderStart) { start in SheetSurface {
            NewPurchaseOrderSheet(vendors: book.vendors, vendorID: start.vendorID) { vendorID, note in
                let order = try book.change { try $0.createOrder(vendorID: vendorID, note: note) }
                actionError = nil
                tab = .orders
                route = .order(order.id)
            }
        } }
    }

    // MARK: Vendors

    /// Paper 42 / 43: the group's label with its count beside it and a small + at the trailing edge.
    private func label(_ title: String, count: Int, add: String, identifier: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text(title).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("\(count)").font(Theme.font(13)).foregroundStyle(Theme.muted)
            Spacer(minLength: 8)
            Button(action: action) {
                PaperIcon(.placeSmallPlus, size: 16, color: Theme.muted)
                    .frame(width: 44, height: 44, alignment: .trailing).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .padding(.vertical, -13)
            .accessibilityLabel(add)
            .accessibilityIdentifier(identifier)
        }
        .frame(minHeight: 18)
        .padding(.horizontal, PaperCardMetrics.margin + 4)
        .padding(.top, 22).padding(.bottom, 8)
    }

    @ViewBuilder private var vendorsTab: some View {
        let all = book.vendors
        let shown = all.filter(matches)
        let year = Calendar.current.component(.year, from: Date())
        if all.isEmpty {
            PaperEmptyState(symbol: "shippingbox", title: "No vendors yet",
                            message: "Add the suppliers you buy from, then write purchase orders for them.",
                            actionTitle: "Add vendor") { vendorDraft = VendorDraft() }
                .padding(.top, 22)
        } else if shown.isEmpty {
            PaperEmptyState(symbol: "magnifyingglass", title: "No matches",
                            message: "No vendor matches \u{201C}\(query)\u{201D}.",
                            actionTitle: "Clear search") { query = "" }
                .padding(.top, 22)
        } else {
            label(query.isEmpty ? "All vendors" : "Matches", count: shown.count, add: "Add vendor", identifier: "vendors-add") {
                vendorDraft = VendorDraft()
            }
            PaperRowsCard {
                ForEach(shown) { vendor in
                    if vendor.id != shown.first?.id { WellDivider(leading: 60) }
                    Button { route = .vendor(vendor.id) } label: {
                        VendorRow(vendor: vendor,
                                  spend: PurchaseOrderMath.spend(book.orders, vendorID: vendor.id, year: year))
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Opens the vendor")
                }
            }
        }
    }

    // MARK: Purchase orders

    @ViewBuilder private var ordersTab: some View {
        let all = book.orders
        let shown = all.filter(matches)
        let open = shown.filter(\.isOpen)
        let received = openOnly ? [] : shown.filter { !$0.isOpen }
        if all.isEmpty {
            if book.vendors.isEmpty {
                PaperEmptyState(symbol: "doc.text", title: "No purchase orders yet",
                                message: "A purchase order is written for a vendor. Add your first vendor to start one.",
                                actionTitle: "Add vendor") { vendorDraft = VendorDraft() }
                    .padding(.top, 22)
            } else {
                PaperEmptyState(symbol: "doc.text", title: "No purchase orders yet",
                                message: "Write one for a vendor, mark it ordered, then check the items in when they arrive.",
                                actionTitle: "New purchase order") { orderStart = PurchaseOrderStart() }
                    .padding(.top, 22)
            }
        } else if shown.isEmpty {
            PaperEmptyState(symbol: "magnifyingglass", title: "No matches",
                            message: "No purchase order matches \u{201C}\(query)\u{201D}.",
                            actionTitle: "Clear search") { query = "" }
                .padding(.top, 22)
        } else {
            label("Open purchase orders", count: open.count, add: "New purchase order", identifier: "vendors-new-order") { startOrder() }
            PaperRowsCard {
                if open.isEmpty {
                    Button { openOnly = false } label: {
                        Text(openOnly ? "Nothing open. Show received orders" : "Nothing open. Every order has been received.")
                            .font(Theme.font(15)).foregroundStyle(openOnly ? Theme.brandText : Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, 16).padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    .disabled(!openOnly)
                } else {
                    orderRows(open)
                }
            }
            if !received.isEmpty {
                PaperCardLabel(title: "Received", count: received.count).padding(.top, 22)
                PaperRowsCard { orderRows(received) }
            }
        }
    }

    private func startOrder() {
        if book.vendors.isEmpty { vendorDraft = VendorDraft() } else { orderStart = PurchaseOrderStart() }
    }

    @ViewBuilder private func orderRows(_ list: [PurchaseOrderRecord]) -> some View {
        ForEach(list) { order in
            if order.id != list.first?.id { WellDivider(leading: 84) }
            Button { route = .order(order.id) } label: { PurchaseOrderRow(order: order) }
                .buttonStyle(RowPressStyle())
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens the purchase order")
        }
    }
}

/// The two letters on a vendor's circle: the first letters of its first two words.
enum VendorInitials {
    static func of(_ name: String) -> String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let letters = words.prefix(2).compactMap(\.first).map { String($0) }.joined()
        if letters.count == 1, let word = words.first, word.count > 1 { return String(word.prefix(2)).uppercased() }
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

struct VendorMark: View {
    let name: String
    var size: CGFloat = 32

    var body: some View {
        Text(VendorInitials.of(name))
            .font(.custom("Inter-Regular", fixedSize: size * 0.34).weight(.semibold))
            .foregroundStyle(Theme.subtle)
            .frame(width: size, height: size)
            .background(Theme.quietFill, in: Circle())
            .dynamicTypeSize(...DynamicTypeSize.large)
            .accessibilityHidden(true)
    }
}

/// Paper 42: the circle, the name (16 Medium) over "#4482 · Net 30", then this year's spend.
private struct VendorRow: View {
    let vendor: VendorRecord
    let spend: Int

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VendorMark(name: vendor.name)
            VStack(alignment: .leading, spacing: 0) {
                Text(vendor.name).font(Theme.font(16, weight: .medium)).tracking(-0.16).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                let line = vendor.accountLine.isEmpty ? (vendor.contact ?? "") : vendor.accountLine
                if !line.isEmpty {
                    Text(line).font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if spend > 0 {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(PurchaseOrderMath.money(spend)).font(Theme.font(16, weight: .medium))
                        .foregroundStyle(Theme.foreground)
                    Text("YTD spend").font(Theme.font(14)).foregroundStyle(Theme.muted)
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// How a purchase order's status reads and is tinted.
enum PurchaseOrderTone {
    static func word(_ order: PurchaseOrderRecord) -> String {
        order.isPartlyReceived ? "Partly received" : order.status.label
    }

    static func ink(_ order: PurchaseOrderRecord) -> Color {
        if order.isPartlyReceived { return Theme.warning }
        switch order.status {
        case .draft: return Theme.muted
        case .ordered: return Theme.brandText
        case .received: return Theme.success
        }
    }

    static func surface(_ order: PurchaseOrderRecord) -> Color {
        if order.isPartlyReceived { return Theme.warningSurface }
        switch order.status {
        case .draft: return Theme.fill
        case .ordered: return Theme.brandSurface
        case .received: return Theme.successSurface
        }
    }

    /// "Truck restock · Jul 20": what it is for, then the day that matters for its status.
    static func line(_ order: PurchaseOrderRecord) -> String {
        let day = (order.receivedAt ?? order.orderedAt ?? order.createdAt).formatted(.dateTime.month(.abbreviated).day())
        let items = order.lines.count == 1 ? "1 item" : "\(order.lines.count) items"
        let about = (order.note ?? "").isEmpty ? items : (order.note ?? "")
        return "\(about) \u{00B7} \(day)"
    }
}

/// Paper 43: the number in a 68 column, the vendor and the total on one line, what it is for, then
/// the status on its chip.
struct PurchaseOrderRow: View {
    let order: PurchaseOrderRecord
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        HStack(alignment: .top, spacing: 0) {
            if !stacked {
                Text(order.numberLabel).font(Theme.font(13, weight: .medium))
                    .foregroundStyle(Theme.subtle)
                    .padding(.top, 13)
                    .frame(width: 68, alignment: .leading)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            VStack(alignment: .leading, spacing: 2) {
                if stacked {
                    Text(order.numberLabel).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.subtle)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(order.vendorName).font(Theme.font(16, weight: .medium)).tracking(-0.16).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(PurchaseOrderMath.money(order.totalCents)).font(Theme.font(16, weight: .medium))
                        .foregroundStyle(Theme.foreground).fixedSize()
                }
                Text(PurchaseOrderTone.line(order)).font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                SalesStatusChip(text: PurchaseOrderTone.word(order), ink: PurchaseOrderTone.ink(order),
                                surface: PurchaseOrderTone.surface(order))
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Paper 42A "Vendor detail": the circle and the name, what was ordered this year and what is still
/// on order, how to reach them, their purchase orders, and New PO as the page's commit.
struct VendorDetailView: View {
    let vendorID: String
    @ObservedObject var book: VendorsBook
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var route: VendorsRoute?
    @State private var editing: VendorDraft?
    @State private var orderStart: PurchaseOrderStart?
    @State private var removing = false
    @State private var actionError: String?

    var body: some View {
        let vendor = book.vendor(vendorID)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let vendor {
                    page(vendor)
                } else {
                    Text("This vendor is no longer on this phone.").font(Theme.font(15)).foregroundStyle(Theme.muted)
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
            if let vendor {
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    ThorbisMenu(items: [
                        ThorbisMenuItem("Edit vendor", icon: "pencil") { editing = VendorDraft(vendor) },
                        ThorbisMenuItem("Remove vendor", icon: "trash", role: .destructive) { removing = true },
                    ], accessibilityLabel: "Vendor actions") {
                        PaperCircleLabel(symbol: "ellipsis", size: 44, fill: Theme.card)
                    }
                }
            }
        }
        .thorbisDestination(item: $route) { route in
            switch route {
            case .vendor(let id): VendorDetailView(vendorID: id, book: book)
            case .order(let id): PurchaseOrderDetailView(orderID: id, book: book)
            }
        }
        .sheet(item: $editing) { draft in SheetSurface {
            VendorEditorSheet(existing: draft.existing) { saved in
                try book.change { try $0.save(saved) }
                actionError = nil
            }
        } }
        .sheet(item: $orderStart) { start in SheetSurface {
            NewPurchaseOrderSheet(vendors: book.vendors, vendorID: start.vendorID) { chosen, note in
                let order = try book.change { try $0.createOrder(vendorID: chosen, note: note) }
                actionError = nil
                route = .order(order.id)
            }
        } }
        .thorbisConfirm("Remove this vendor?",
                        message: "Its purchase orders stay on this phone under the vendor\u{2019}s name.",
                        isPresented: $removing,
                        actions: [ThorbisConfirmAction("Remove", role: .destructive) {
                            do { try book.change { try $0.removeVendor(vendorID) }; dismiss() }
                            catch { actionError = error.localizedDescription }
                        }])
    }

    @ViewBuilder private func page(_ vendor: VendorRecord) -> some View {
        let orders = book.orders(for: vendor.id)
        let open = orders.filter(\.isOpen).count
        let year = Calendar.current.component(.year, from: Date())
        HStack(alignment: .center, spacing: 14) {
            VendorMark(name: vendor.name, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(vendor.name).font(Theme.font(28, weight: .bold)).tracking(-0.6)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let terms = vendor.terms, !terms.isEmpty {
                    Text(terms).font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 4)
        if let actionError { SalesProblemLine(message: actionError) }
        HStack(alignment: .top, spacing: 8) {
            tile("Ordered this year", PurchaseOrderMath.money(PurchaseOrderMath.spend(book.orders, vendorID: vendor.id, year: year)),
                 ink: Theme.foreground)
            let onOrder = PurchaseOrderMath.onOrder(book.orders, vendorID: vendor.id)
            tile("Still on order", PurchaseOrderMath.money(onOrder), ink: onOrder > 0 ? Theme.warning : Theme.foreground)
        }
        PaperCard {
            VStack(alignment: .leading, spacing: 0) {
                reachRow(title: (vendor.contact ?? "").isEmpty ? "Phone" : (vendor.contact ?? ""),
                         value: (vendor.phone ?? "").isEmpty ? "No phone yet" : (vendor.phone ?? ""),
                         symbol: "phone", spoken: "Call \(vendor.name)", identifier: "vendors-call", url: vendor.callURL)
                WellDivider()
                reachRow(title: "Email for POs",
                         value: (vendor.email ?? "").isEmpty ? "No email yet" : (vendor.email ?? ""),
                         symbol: "envelope", spoken: "Email \(vendor.name)", identifier: "vendors-email", url: vendor.mailURL)
                WellDivider()
                PaperDetailRow(label: "Account number") {
                    Text(vendor.maskedAccount ?? "Not set")
                }
                .padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 52)
            }
        }
        PaperSection(title: open > 0 ? "Purchase orders \u{00B7} \(open) open" : "Purchase orders") {
            if orders.isEmpty {
                Text("No purchase orders for this vendor yet.").font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 14)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(orders) { order in
                        if order.id != orders.first?.id { WellDivider() }
                        Button { route = .order(order.id) } label: { vendorOrderRow(order) }
                            .buttonStyle(RowPressStyle())
                            .accessibilityElement(children: .combine)
                            .accessibilityHint("Opens the purchase order")
                    }
                }
            }
        } accessory: { EmptyView() }
        if let notes = vendor.notes, !notes.isEmpty {
            PaperSection("Notes") {
                Text(notes).font(Theme.font(15)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
            }
        }
        Button { orderStart = PurchaseOrderStart(vendorID: vendor.id) } label: { SalesBrandCommit(title: "New PO") }
            .buttonStyle(PressStyle())
            .accessibilityLabel("New purchase order")
            .accessibilityIdentifier("vendors-detail-new-order")
        SalesPhoneNote(text: "Saved on this phone only. Your team doesn\u{2019}t see this vendor.")
    }

    /// Paper 42A: a small label over the figure in 20 Semibold.
    private func tile(_ label: String, _ value: String, ink: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.font(13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            Text(value).font(Theme.font(20, weight: .semibold)).foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Paper 42A: who to reach over the number, then the action on a brand-surface circle.
    private func reachRow(title: String, value: String, symbol: String, spoken: String, identifier: String, url: URL?) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(value).font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if let url {
                Button { openURL(url) } label: {
                    Image(systemName: symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.brandText)
                        .frame(width: 44, height: 44)
                        .background(Theme.brandSurface, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(spoken)
                .accessibilityIdentifier(identifier)
            }
        }
        .padding(.leading, PaperCardMetrics.inset).padding(.trailing, 10).padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
    }

    /// Paper 42A: the number over "Sent Jul 20 · truck restock", the total over its status word.
    private func vendorOrderRow(_ order: PurchaseOrderRecord) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(order.numberLabel).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                Text(PurchaseOrderTone.line(order)).font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 0) {
                Text(PurchaseOrderMath.money(order.totalCents, alwaysCents: true)).font(Theme.font(16, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                Text(PurchaseOrderTone.word(order)).font(Theme.font(13)).foregroundStyle(PurchaseOrderTone.ink(order))
            }
            .fixedSize()
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Paper 42B "New vendor": Cancel and Save vendor in the title row, who they are on one card, the
/// account on the next. Saved on this phone only, and it says so under the cards.
struct VendorEditorSheet: View {
    let existing: VendorRecord?
    let onSave: (VendorRecord) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var contact: String
    @State private var phone: String
    @State private var email: String
    @State private var account: String
    @State private var terms: String
    @State private var notes: String
    @State private var nameMissing = false
    @State private var emailProblem = false
    @State private var error: String?

    init(existing: VendorRecord?, onSave: @escaping (VendorRecord) throws -> Void) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _contact = State(initialValue: existing?.contact ?? "")
        _phone = State(initialValue: existing?.phone ?? "")
        _email = State(initialValue: existing?.email ?? "")
        _account = State(initialValue: existing?.accountNumber ?? "")
        _terms = State(initialValue: existing?.terms ?? "")
        _notes = State(initialValue: existing?.notes ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            SalesSheetHeader(title: existing == nil ? "New vendor" : "Edit vendor", saveTitle: "Save vendor",
                             saveIdentifier: "vendors-save-vendor", onCancel: { dismiss() }, onSave: save)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error { SalesProblemLine(message: error) }
                    SalesFormCard {
                        SalesStackedField(label: "Business name", text: $name, prompt: "Sierra Pipe and Supply",
                                          problem: nameMissing ? "Add the business name to save." : nil,
                                          content: .organizationName, capitalization: .words)
                        WellDivider(leading: 16)
                        SalesStackedField(label: "Contact", text: $contact, prompt: "Who you talk to",
                                          content: .name, capitalization: .words)
                        WellDivider(leading: 16)
                        SalesStackedField(label: "Phone", text: $phone, prompt: "(555) 010-0100",
                                          keyboard: .phonePad, content: .telephoneNumber)
                        WellDivider(leading: 16)
                        SalesStackedField(label: "Email for POs", text: $email, prompt: "name@vendor.com",
                                          problem: emailProblem ? "That email is missing an @." : nil,
                                          keyboard: .emailAddress, content: .emailAddress, capitalization: .never)
                    }
                    SalesFormCard {
                        SalesInlineField(label: "Your account number", text: $account, capitalization: .characters)
                        WellDivider(leading: 16)
                        SalesInlineField(label: "Payment terms", text: $terms, prompt: "Net 30")
                    }
                    SalesFormCard {
                        SalesStackedField(label: "Notes", text: $notes, prompt: "Hours, will-call counter, who to ask for",
                                          multiline: true)
                    }
                    SalesPhoneNote(text: "Saved on this phone only. Your team doesn\u{2019}t see it. Account numbers show the last 4 digits after you save.")
                }
                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background.ignoresSafeArea())
        .onChange(of: name) { _, _ in nameMissing = false }
        .onChange(of: email) { _, _ in emailProblem = false }
    }

    private func trimmed(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func save() {
        guard let businessName = trimmed(name) else { nameMissing = true; return }
        if let address = trimmed(email), !address.contains("@") { emailProblem = true; return }
        var vendor = existing ?? VendorRecord(name: businessName)
        vendor.name = businessName
        vendor.contact = trimmed(contact)
        vendor.phone = trimmed(phone)
        vendor.email = trimmed(email)
        vendor.accountNumber = trimmed(account)
        vendor.terms = trimmed(terms)
        vendor.notes = trimmed(notes)
        do { try onSave(vendor); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

#if DEBUG
/// Screenshot fixtures only (`--paper-preview`): Paper 42 and 43's vendors and orders in a
/// throwaway folder, never in the real file. Absent from Release builds.
enum VendorsPreviewData {
    @MainActor static func records(organizationID: String) throws -> VendorsRecords {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("paper-preview-vendors-\(UUID().uuidString)", isDirectory: true)
        let records = try VendorsRecords(organizationID: organizationID, directory: folder)
        let coolAir = VendorRecord(name: "CoolAir Supply Co.", contact: "Dana Ortiz", phone: "(555) 010-0193",
                                   email: "orders@coolair.example", accountNumber: "CA-4482", terms: "Net 30")
        let valley = VendorRecord(name: "Valley Electric Wholesale", phone: "(555) 010-0144", accountNumber: "1187", terms: "Net 15")
        let ferguson = VendorRecord(name: "Ferguson Supply", contact: "Kelly Tran \u{00B7} branch rep", phone: "(555) 010-0172",
                                    accountNumber: "48299034", terms: "Net 30", notes: "Will-call counter closes at 4.")
        for vendor in [coolAir, valley, ferguson] { try records.save(vendor) }
        let day: TimeInterval = 86_400
        let now = Date()
        try records.createOrder(vendorID: ferguson.id, note: "Water heater install", lines: [
            PurchaseOrderLine(description: "50 gal gas water heater", quantity: 1, unitCostCents: 54_000),
        ], now: now.addingTimeInterval(-9 * day))
        let panel = try records.createOrder(vendorID: ferguson.id, note: "Panel upgrade", lines: [
            PurchaseOrderLine(description: "Run capacitor 45/5 \u{00B5}F", quantity: 1, unitCostCents: 3_840),
            PurchaseOrderLine(description: "Contactor 40A", quantity: 2, unitCostCents: 28_000),
            PurchaseOrderLine(description: "Condensate pump", quantity: 1, unitCostCents: 2_000),
        ], now: now.addingTimeInterval(-3 * day))
        try records.createOrder(vendorID: coolAir.id, note: "AC not cooling", lines: [
            PurchaseOrderLine(description: "R-410A refrigerant, 25 lb", quantity: 2, unitCostCents: 48_000),
            PurchaseOrderLine(description: "Contactor relay, 24V", quantity: 1, unitCostCents: 28_000),
        ], now: now)
        if let first = records.orders.last {
            try records.markOrdered(first.id, now: now.addingTimeInterval(-9 * day))
            var counts: [String: Int] = [:]
            for line in first.lines { counts[line.id] = line.quantity }
            try records.receive(first.id, counts: counts, now: now.addingTimeInterval(-7 * day))
        }
        try records.markOrdered(panel.id, now: now.addingTimeInterval(-3 * day))
        return records
    }
}
#endif
