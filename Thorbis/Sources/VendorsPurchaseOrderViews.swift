import SwiftUI
import UIKit

/// An item being added to or edited on a draft purchase order.
struct PurchaseOrderLineDraft: Identifiable {
    let id: String
    let existing: PurchaseOrderLine?
    init(_ existing: PurchaseOrderLine? = nil) { self.existing = existing; self.id = existing?.id ?? UUID().uuidString }
}

/// Starts a purchase order: who it is for and what it is for. Saving takes the next PO number.
struct NewPurchaseOrderSheet: View {
    let vendors: [VendorRecord]
    let onCreate: (String, String?) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var vendorID: String
    @State private var note = ""
    @State private var error: String?

    init(vendors: [VendorRecord], vendorID: String?, onCreate: @escaping (String, String?) throws -> Void) {
        self.vendors = vendors
        self.onCreate = onCreate
        _vendorID = State(initialValue: vendorID ?? vendors.first?.id ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            SalesSheetHeader(title: "New purchase order", saveTitle: "Create", saveIdentifier: "vendors-create-order",
                             onCancel: { dismiss() }, onSave: create)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error { SalesProblemLine(message: error) }
                    SalesFormCard {
                        ThorbisSelect(options: vendors.map { (value: $0.id, label: $0.name) }, selection: $vendorID,
                                      label: "Vendor", placeholder: "Choose a vendor")
                            .padding(.horizontal, 16).frame(minHeight: 56)
                        WellDivider(leading: 16)
                        SalesStackedField(label: "What it\u{2019}s for", text: $note, prompt: "Truck restock, or a job\u{2019}s name")
                    }
                    SalesPhoneNote(text: "The order starts as a draft on this phone. Add items next, then mark it ordered. Nothing is sent to the vendor until you share it.")
                }
                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background.ignoresSafeArea())
    }

    private func create() {
        guard vendors.contains(where: { $0.id == vendorID }) else { error = "Choose a vendor to start the order."; return }
        let about = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do { try onCreate(vendorID, about.isEmpty ? nil : about); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

/// Paper 41 "Purchase order": the number and what it is for, the facts as chips, Details, the items
/// with their quantity capsules, the total, then the one commit for where the order stands:
/// mark it ordered, then receive it.
struct PurchaseOrderDetailView: View {
    let orderID: String
    @ObservedObject var book: VendorsBook
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var lineDraft: PurchaseOrderLineDraft?
    @State private var receiving = false
    @State private var removing = false
    @State private var sharedText: SharedText?
    @State private var sharedFiles: MediaShareFiles?
    @State private var actionError: String?

    private func attempt(_ work: () throws -> Void) {
        do { try work(); actionError = nil }
        catch { actionError = error.localizedDescription }
    }

    var body: some View {
        let order = book.order(orderID)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let order {
                    page(order)
                } else {
                    Text("This purchase order is no longer on this phone.").font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .paperCardMargin().padding(.top, 8).padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let order {
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        // Paper 41: share, then •••, each a 44 circle on the card tone.
                        ThorbisMenu(items: [
                            ThorbisMenuItem("Share as text", icon: "text.alignleft") { shareText(order) },
                            ThorbisMenuItem("Share as PDF", icon: "doc.richtext") { sharePDF(order) },
                        ], title: "Share \(order.numberLabel)", accessibilityLabel: "Share purchase order") {
                            PaperCircleLabel(symbol: "square.and.arrow.up", size: 44, fill: Theme.card)
                        }
                        .accessibilityIdentifier("vendors-order-share")
                        ThorbisMenu(items: menuItems(order), accessibilityLabel: "Purchase order actions") {
                            PaperCircleLabel(symbol: "ellipsis", size: 44, fill: Theme.card)
                        }
                    }
                }
            }
        }
        .sheet(item: $lineDraft) { draft in SheetSurface {
            PurchaseOrderLineSheet(existing: draft.existing) { line in
                try book.change { records in
                    guard var current = records.order(orderID) else { return }
                    if let index = current.lines.firstIndex(where: { $0.id == line.id }) { current.lines[index] = line }
                    else { current.lines.append(line) }
                    try records.save(current)
                }
                actionError = nil
            }
        } }
        .sheet(isPresented: $receiving) { SheetSurface {
            if let order = book.order(orderID) {
                PurchaseOrderReceiveSheet(order: order) { counts in
                    try book.change { try $0.receive(orderID, counts: counts) }
                    actionError = nil
                }
            }
        } }
        .sheet(item: $sharedText) { shared in TextShareSheet(text: shared.text).ignoresSafeArea() }
        .sheet(item: $sharedFiles) { files in
            MediaShareSheet(urls: files.urls) {
                for url in files.urls { try? FileManager.default.removeItem(at: url) }
            }
            .ignoresSafeArea()
        }
        .thorbisConfirm("Remove this purchase order?",
                        message: "It is deleted from this phone. Its number is not used again.",
                        isPresented: $removing,
                        actions: [ThorbisConfirmAction("Remove", role: .destructive) {
                            do { try book.change { try $0.removeOrder(orderID) }; dismiss() }
                            catch { actionError = error.localizedDescription }
                        }])
    }

    private func menuItems(_ order: PurchaseOrderRecord) -> [ThorbisMenuItem] {
        var items: [ThorbisMenuItem] = []
        if order.status == .draft, !order.lines.isEmpty {
            items.append(ThorbisMenuItem("Mark as ordered", icon: "checkmark.circle") { markOrdered() })
        }
        if order.status == .ordered {
            items.append(ThorbisMenuItem("Receive items", icon: "shippingbox") { receiving = true })
            if order.receivedUnits == 0 {
                items.append(ThorbisMenuItem("Back to draft", icon: "arrow.uturn.backward") {
                    attempt { try book.change { try $0.backToDraft(orderID) } }
                })
            }
        }
        items.append(ThorbisMenuItem("Remove", icon: "trash", role: .destructive) { removing = true })
        return items
    }

    private func markOrdered() { attempt { try book.change { try $0.markOrdered(orderID) } } }

    private func shareText(_ order: PurchaseOrderRecord) {
        sharedText = SharedText(PurchaseOrderDocument.text(order, vendor: book.vendor(order.vendorID),
                                                          company: session.activeOrganization?.name))
    }

    private func sharePDF(_ order: PurchaseOrderRecord) {
        attempt {
            let data = PurchaseOrderDocument.pdf(order, vendor: book.vendor(order.vendorID),
                                                 company: session.activeOrganization?.name)
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("purchase-orders", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent(PurchaseOrderDocument.fileName(order))
            try? FileManager.default.removeItem(at: file)
            try data.write(to: file, options: [.atomic, .completeFileProtection])
            sharedFiles = MediaShareFiles(urls: [file])
        }
    }

    @ViewBuilder private func page(_ order: PurchaseOrderRecord) -> some View {
        let vendor = book.vendor(order.vendorID)
        let draft = order.status == .draft
        VStack(alignment: .leading, spacing: 2) {
            Text("Purchase order").font(Theme.font(34, weight: .bold)).tracking(-0.85)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text([order.numberLabel, order.note ?? ""].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                .font(Theme.font(15)).monospacedDigit().foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        // Paper 41: the status, the vendor and the total as chips under the title.
        FlowRow(spacing: 8, lineSpacing: 8) {
            SalesStatusChip(text: PurchaseOrderTone.word(order), ink: PurchaseOrderTone.ink(order),
                            surface: PurchaseOrderTone.surface(order))
            PropertyChip(order.vendorName, symbol: "shippingbox")
            PropertyChip(PurchaseOrderMath.money(order.totalCents, alwaysCents: true))
            if let orderedAt = order.orderedAt {
                PropertyChip("Ordered \(orderedAt.formatted(.dateTime.month(.abbreviated).day()))", symbol: "clock")
            }
        }
        .padding(.horizontal, 4)
        if let actionError { SalesProblemLine(message: actionError) }
        PaperSection("Details") { details(order, vendor: vendor, draft: draft) }
        if draft {
            // Paper 41: "+ Add part" on its own card, with what it takes on the right.
            Button { lineDraft = PurchaseOrderLineDraft() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.brandText)
                        .accessibilityHidden(true)
                    Text("Add item").font(Theme.font(16)).foregroundStyle(Theme.foreground)
                    Spacer(minLength: 8)
                    Text("Description, quantity and cost").font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Add item")
            .accessibilityIdentifier("vendors-order-add-item")
        }
        if !order.lines.isEmpty {
            PaperSection(title: "Items") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(order.lines) { line in
                        if line.id != order.lines.first?.id { WellDivider() }
                        if draft { draftLine(line, in: order) } else { orderedLine(line) }
                    }
                }
            } accessory: {
                Text(order.lines.count == 1 ? "1 item" : "\(order.lines.count) items")
                    .font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
            }
            if draft {
                Text("Tap an item to edit its name or cost. At quantity 1, minus becomes remove.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4).padding(.top, -8)
            }
        }
        // Paper 41: "PO total" beside the figure in 24 Bold, on its own card.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) { totalLabel; Spacer(minLength: 8); totalFigure(order) }
            VStack(alignment: .leading, spacing: 4) { totalLabel; totalFigure(order) }
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        commit(order, vendor: vendor)
        SalesPhoneNote(text: "Saved on this phone only. Your team doesn\u{2019}t see this order.")
    }

    private var totalLabel: some View {
        Text("PO total").font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
    }

    private func totalFigure(_ order: PurchaseOrderRecord) -> some View {
        Text(PurchaseOrderMath.money(order.totalCents, alwaysCents: true))
            .font(Theme.font(24, weight: .bold)).monospacedDigit().foregroundStyle(Theme.foreground)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Paper 41 "Details": Vendor, Account and what it is for. A draft can change them.
    @ViewBuilder private func details(_ order: PurchaseOrderRecord, vendor: VendorRecord?, draft: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if draft, !book.vendors.isEmpty {
                ThorbisSelect(options: book.vendors.map { (value: $0.id, label: $0.name) },
                              selection: Binding(get: { order.vendorID }, set: { chosen in
                                  attempt {
                                      try book.change { records in
                                          guard var current = records.order(orderID), let picked = records.vendor(chosen) else { return }
                                          current.vendorID = picked.id
                                          current.vendorName = picked.name
                                          try records.save(current)
                                      }
                                  }
                              }),
                              label: "Vendor", placeholder: order.vendorName)
                    .padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 56)
            } else {
                fact("Vendor", order.vendorName)
            }
            WellDivider()
            fact("Account", [vendor?.maskedAccount ?? "", vendor?.terms ?? ""].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "),
                 empty: vendor == nil ? "Vendor removed" : "Not set")
            WellDivider()
            if draft {
                SalesInlineField(label: "For", text: Binding(get: { order.note ?? "" }, set: { typed in
                    attempt {
                        try book.change { records in
                            guard var current = records.order(orderID) else { return }
                            current.note = typed.isEmpty ? nil : typed
                            try records.save(current)
                        }
                    }
                }), prompt: "Truck restock")
            } else {
                fact("For", order.note ?? "", empty: "Not set")
                if let orderedAt = order.orderedAt {
                    WellDivider()
                    fact("Ordered", orderedAt.formatted(date: .abbreviated, time: .omitted))
                }
                if let receivedAt = order.receivedAt {
                    WellDivider()
                    fact("Received", receivedAt.formatted(date: .abbreviated, time: .omitted))
                }
            }
        }
    }

    private func fact(_ label: String, _ value: String, empty: String = "") -> some View {
        PaperDetailRow(label: label) { Text(value.isEmpty ? empty : value).monospacedDigit() }
            .padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 56)
    }

    /// Paper 41: the name over "$164.00 for 2", then minus, the count and plus on a capsule.
    private func draftLine(_ line: PurchaseOrderLine, in order: PurchaseOrderRecord) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Button { lineDraft = PurchaseOrderLineDraft(line) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(line.description).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(costLine(line)).font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityHint("Edits the item")
            SalesQuantityStepper(value: line.quantity, range: 1...9_999, name: line.description, onChange: { count in
                setQuantity(line.id, count)
            }, onRemove: { removeLine(line.id) })
        }
        .padding(.leading, PaperCardMetrics.inset).padding(.trailing, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    }

    private func costLine(_ line: PurchaseOrderLine) -> String {
        let each = PurchaseOrderMath.money(line.unitCostCents, alwaysCents: true)
        guard line.quantity > 1 else { return each }
        return "\(each) each \u{00B7} \(PurchaseOrderMath.money(line.totalCents, alwaysCents: true)) for \(line.quantity)"
    }

    /// Once ordered the items are fixed: what was ordered, what has come in, and the line's cost.
    private func orderedLine(_ line: PurchaseOrderLine) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(line.description).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(line.received >= line.quantity ? "Ordered \(line.quantity) \u{00B7} all received"
                     : line.received > 0 ? "\(line.received) of \(line.quantity) received" : "Ordered \(line.quantity)")
                    .font(Theme.font(14)).monospacedDigit()
                    .foregroundStyle(line.received > 0 && line.received < line.quantity ? Theme.warning : Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(PurchaseOrderMath.money(line.totalCents, alwaysCents: true)).font(Theme.font(16, weight: .medium)).monospacedDigit()
                .foregroundStyle(Theme.foreground).fixedSize()
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func setQuantity(_ lineID: String, _ count: Int) {
        attempt {
            try book.change { records in
                guard var current = records.order(orderID), current.status == .draft,
                      let index = current.lines.firstIndex(where: { $0.id == lineID }) else { return }
                current.lines[index].quantity = max(1, count)
                try records.save(current)
            }
        }
    }

    private func removeLine(_ lineID: String) {
        attempt {
            try book.change { records in
                guard var current = records.order(orderID), current.status == .draft else { return }
                current.lines.removeAll { $0.id == lineID }
                try records.save(current)
            }
        }
    }

    /// Paper 41: the brand commit, with the vendor's phone on a 52 circle beside it.
    @ViewBuilder private func commit(_ order: PurchaseOrderRecord, vendor: VendorRecord?) -> some View {
        let callURL = vendor?.callURL
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                switch order.status {
                case .draft:
                    Button { markOrdered() } label: {
                        SalesBrandCommit(title: "Mark as ordered", symbol: "checkmark.shield")
                            .opacity(order.lines.isEmpty ? 0.5 : 1)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityIdentifier("vendors-order-mark-ordered")
                case .ordered:
                    Button { receiving = true } label: {
                        SalesBrandCommit(title: "Receive items", symbol: "shippingbox")
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityIdentifier("vendors-order-receive")
                case .received:
                    EmptyView()
                }
                if let callURL {
                    Button { openURL(callURL) } label: {
                        Image(systemName: "phone").font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.foreground)
                            .frame(width: 52, height: 52)
                            .background(Theme.card, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Call \(order.vendorName)")
                    .accessibilityIdentifier("vendors-order-call")
                }
                if order.status == .received, callURL != nil { Spacer(minLength: 0) }
            }
            if order.status == .draft {
                Text(order.lines.isEmpty ? "Add an item before marking this ordered."
                     : "Marking it ordered doesn\u{2019}t send anything. Share the order to send it to the vendor.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            } else if order.isPartlyReceived {
                Text("\(order.receivedUnits) of \(order.orderedUnits) received. The order stays open for the rest.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// One item on a purchase order: what it is, how many, and what one costs.
struct PurchaseOrderLineSheet: View {
    let existing: PurchaseOrderLine?
    let onSave: (PurchaseOrderLine) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var description: String
    @State private var quantity: String
    @State private var cost: String
    @State private var descriptionMissing = false
    @State private var quantityProblem = false
    @State private var costProblem = false
    @State private var error: String?

    init(existing: PurchaseOrderLine?, onSave: @escaping (PurchaseOrderLine) throws -> Void) {
        self.existing = existing
        self.onSave = onSave
        _description = State(initialValue: existing?.description ?? "")
        _quantity = State(initialValue: existing.map { "\($0.quantity)" } ?? "1")
        _cost = State(initialValue: existing.map { String(format: "%.2f", Double($0.unitCostCents) / 100) } ?? "")
    }

    private var lineTotal: String? {
        guard let count = Int(quantity.trimmingCharacters(in: .whitespaces)), count > 0,
              let cents = MoneyInput.cents(cost) else { return nil }
        return PurchaseOrderMath.money(count * cents, alwaysCents: true)
    }

    var body: some View {
        VStack(spacing: 0) {
            SalesSheetHeader(title: existing == nil ? "Add item" : "Edit item", saveTitle: "Save",
                             saveIdentifier: "vendors-save-item", onCancel: { dismiss() }, onSave: save)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error { SalesProblemLine(message: error) }
                    SalesFormCard {
                        SalesStackedField(label: "Description", text: $description, prompt: "Contactor relay, 24V",
                                          problem: descriptionMissing ? "Say what the item is to save." : nil)
                    }
                    SalesFormCard {
                        SalesInlineField(label: "Quantity", text: $quantity, prompt: "1",
                                         problem: quantityProblem ? "Quantity is a whole number, 1 or more." : nil,
                                         keyboard: .numberPad)
                        WellDivider(leading: 16)
                        SalesInlineField(label: "Unit cost", text: $cost, prompt: "0.00",
                                         problem: costProblem ? "Write the cost as dollars and cents, like 28.00." : nil,
                                         keyboard: .decimalPad)
                        if let lineTotal {
                            WellDivider(leading: 16)
                            PaperDetailRow(label: "Line total") { Text(lineTotal).monospacedDigit() }
                                .padding(.horizontal, 16).frame(minHeight: 52)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background.ignoresSafeArea())
        .onChange(of: description) { _, _ in descriptionMissing = false }
        .onChange(of: quantity) { _, _ in quantityProblem = false }
        .onChange(of: cost) { _, _ in costProblem = false }
    }

    private func save() {
        let name = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = Int(quantity.trimmingCharacters(in: .whitespaces))
        let typedCost = cost.trimmingCharacters(in: .whitespaces)
        let cents = typedCost.isEmpty ? 0 : MoneyInput.cents(typedCost)
        descriptionMissing = name.isEmpty
        quantityProblem = (count ?? 0) < 1 || (count ?? 0) > 9_999
        costProblem = cents == nil
        guard !descriptionMissing, !quantityProblem, let count, let cents else { return }
        let line = PurchaseOrderLine(id: existing?.id ?? UUID().uuidString, description: name, quantity: count,
                                     unitCostCents: cents, received: existing?.received ?? 0)
        do { try onSave(line); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

/// Paper 41A "Receive purchase order": each item with a mark, what was ordered, and a capsule for
/// how many have come in. Short lines turn amber and the order stays open for them.
struct PurchaseOrderReceiveSheet: View {
    let order: PurchaseOrderRecord
    let onReceive: ([String: Int]) throws -> Void
    @Environment(\.dismiss) private var dismiss
    /// Each line's total received, starting from everything having arrived.
    @State private var counts: [String: Int]
    @State private var error: String?

    init(order: PurchaseOrderRecord, onReceive: @escaping ([String: Int]) throws -> Void) {
        self.order = order
        self.onReceive = onReceive
        var start: [String: Int] = [:]
        for line in order.lines { start[line.id] = line.quantity }
        _counts = State(initialValue: start)
    }

    private func count(_ line: PurchaseOrderLine) -> Int { counts[line.id] ?? line.received }
    private var receivedAfter: Int { order.lines.reduce(0) { $0 + count($1) } }
    private var short: [PurchaseOrderLine] { order.lines.filter { count($0) < $0.quantity } }

    private var summary: String {
        var parts: [String] = []
        if let orderedAt = order.orderedAt { parts.append("Ordered \(orderedAt.formatted(.dateTime.month(.abbreviated).day()))") }
        parts.append(order.orderedUnits == 1 ? "1 item" : "\(order.orderedUnits) items")
        parts.append(PurchaseOrderMath.money(order.totalCents, alwaysCents: true))
        return parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        VStack(spacing: 0) {
            SalesSheetHeader(title: "Receive \(order.numberLabel)", saveTitle: nil, onCancel: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(order.vendorName).font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(summary).font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 4)
                    if let error { SalesProblemLine(message: error) }
                    SalesFormCard {
                        ForEach(order.lines) { line in
                            if line.id != order.lines.first?.id { WellDivider(leading: 0) }
                            row(line)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 10) {
                if !short.isEmpty {
                    Text(short.count == 1 ? "The order stays open for the \(short[0].description) still to come."
                         : "The order stays open for the \(short.count) items still to come.")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(action: receive) {
                    SalesBrandCommit(title: "Receive \(receivedAfter) of \(order.orderedUnits) items")
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("vendors-receive-commit")
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 12)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background.ignoresSafeArea())
    }

    /// Paper 41A: a green tick when the line is complete, an amber mark and words when it is short.
    private func row(_ line: PurchaseOrderLine) -> some View {
        let now = count(line)
        let complete = now >= line.quantity
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: complete ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(complete ? Theme.success : Theme.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(line.description).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(complete ? "Ordered \(line.quantity)" : "\(now) of \(line.quantity) received \u{00B7} back-ordered")
                    .font(Theme.font(13, weight: complete ? .regular : .semibold)).monospacedDigit()
                    .foregroundStyle(complete ? Theme.muted : Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            SalesQuantityStepper(value: now, range: min(line.received, line.quantity)...line.quantity,
                                 name: "\(line.description) received", onChange: { counts[line.id] = $0 })
        }
        .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(complete ? Color.clear : Theme.warningSurface)
    }

    private func receive() {
        do { try onReceive(counts); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

extension PurchaseOrderDocument {
    /// A plain US Letter page: black on white, the items as a table, the total under them.
    @MainActor static func pdf(_ order: PurchaseOrderRecord, vendor: VendorRecord?, company: String?) -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 54
        let width = page.width - margin * 2
        let ink = UIColor.black
        let quiet = UIColor(white: 0.35, alpha: 1)
        func attributes(_ size: CGFloat, _ weight: UIFont.Weight, _ color: UIColor, _ alignment: NSTextAlignment = .left) -> [NSAttributedString.Key: Any] {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            paragraph.lineBreakMode = .byWordWrapping
            return [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph]
        }
        return UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            var y = margin
            func newPage() { context.beginPage(); y = margin }
            @discardableResult
            func draw(_ text: String, _ style: [NSAttributedString.Key: Any], x: CGFloat = margin, width boxWidth: CGFloat? = nil,
                      advance: Bool = true) -> CGFloat {
                let box = boxWidth ?? width
                let string = NSAttributedString(string: text, attributes: style)
                let height = ceil(string.boundingRect(with: CGSize(width: box, height: .greatestFiniteMagnitude),
                                                     options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
                string.draw(with: CGRect(x: x, y: y, width: box, height: height),
                            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                if advance { y += height }
                return height
            }
            func rule() {
                context.cgContext.setStrokeColor(UIColor(white: 0.8, alpha: 1).cgColor)
                context.cgContext.setLineWidth(0.5)
                context.cgContext.move(to: CGPoint(x: margin, y: y))
                context.cgContext.addLine(to: CGPoint(x: page.width - margin, y: y))
                context.cgContext.strokePath()
            }
            newPage()
            draw("Purchase order", attributes(24, .bold, ink)); y += 2
            draw(order.numberLabel, attributes(13, .medium, quiet)); y += 18
            if let company, !company.isEmpty { draw("From  \(company)", attributes(12, .regular, ink)); y += 3 }
            draw("To  \(vendor?.name ?? order.vendorName)", attributes(12, .regular, ink)); y += 3
            if let account = vendor?.accountNumber, !account.isEmpty { draw("Account  \(account)", attributes(12, .regular, ink)); y += 3 }
            draw("Date  \((order.orderedAt ?? order.createdAt).formatted(date: .abbreviated, time: .omitted))", attributes(12, .regular, ink)); y += 3
            if let note = order.note, !note.isEmpty { draw("For  \(note)", attributes(12, .regular, ink)) }
            y += 20
            let quantityWidth: CGFloat = 50, costWidth: CGFloat = 90, totalWidth: CGFloat = 90
            let nameWidth = width - quantityWidth - costWidth - totalWidth - 24
            let quantityX = margin + nameWidth + 8, costX = quantityX + quantityWidth + 8, totalX = costX + costWidth + 8
            let head = attributes(10, .semibold, quiet)
            draw("ITEM", head, width: nameWidth, advance: false)
            draw("QTY", attributes(10, .semibold, quiet, .right), x: quantityX, width: quantityWidth, advance: false)
            draw("UNIT COST", attributes(10, .semibold, quiet, .right), x: costX, width: costWidth, advance: false)
            y += draw("TOTAL", attributes(10, .semibold, quiet, .right), x: totalX, width: totalWidth, advance: false) + 6
            rule(); y += 8
            let body = attributes(12, .regular, ink)
            let figure = attributes(12, .regular, ink, .right)
            for line in order.lines {
                if y > page.height - margin - 80 { newPage() }
                let height = draw(line.description, body, width: nameWidth, advance: false)
                draw("\(line.quantity)", figure, x: quantityX, width: quantityWidth, advance: false)
                draw(PurchaseOrderMath.money(line.unitCostCents, alwaysCents: true), figure, x: costX, width: costWidth, advance: false)
                draw(PurchaseOrderMath.money(line.totalCents, alwaysCents: true), figure, x: totalX, width: totalWidth, advance: false)
                y += height + 8
            }
            if order.lines.isEmpty { draw("No items yet.", attributes(12, .regular, quiet)); y += 8 }
            rule(); y += 10
            draw("Total", attributes(13, .semibold, ink), width: nameWidth, advance: false)
            draw(PurchaseOrderMath.money(order.totalCents, alwaysCents: true), attributes(13, .semibold, ink, .right),
                 x: costX, width: costWidth + totalWidth + 8)
        }
    }
}
