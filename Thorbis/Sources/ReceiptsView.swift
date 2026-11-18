import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

// Paper 46 "Receipts", 44 "Receipt scanner", 45 "Receipt scanner (camera)" and 46A "Receipt detail".
// The designs show receipts being submitted, reviewed and reimbursed. No server route does any of
// that, so this place is the person's own record: receipts kept on this phone, grouped by month
// with their totals, read from a photo with Vision and checked by hand, and shared as a CSV.

/// The receipts on screen, bound to one person in one workspace.
@MainActor
final class ReceiptsModel: ObservableObject {
    @Published private(set) var receipts: [ReceiptRecord] = []
    @Published private(set) var bound = false
    @Published private(set) var error: String?
    private var store: ReceiptsStore?
    private var key: String?

    func bind(organizationID: String?, userID: String?, directory: URL? = nil) {
        let next = "\(organizationID ?? "")|\(userID ?? "")"
        guard next != key else { return }
        key = next
        store = nil
        receipts = []
        bound = false
        error = nil
        guard let organizationID, let userID else { return }
        do {
            var preview: ReceiptsStore?
            #if DEBUG
            if PaperPreview.enabled, directory == nil {
                preview = try PlacesPreviewData.receipts(organizationID: organizationID, userID: userID)
            }
            #endif
            let opened = try preview ?? ReceiptsStore(organizationID: organizationID, userID: userID, directory: directory)
            store = opened
            receipts = opened.receipts
            bound = true
        } catch {
            self.error = "Receipts on this phone couldn\u{2019}t be opened. \(error.localizedDescription)"
        }
    }

    func receipt(_ id: String) -> ReceiptRecord? { receipts.first { $0.id == id } }

    func imageURL(for receipt: ReceiptRecord) -> URL? { store?.imageURL(for: receipt) }

    func save(_ record: ReceiptRecord, image: ReceiptImageChange) throws {
        guard let store else { throw Problem(title: "Receipts are not open on this phone", status: nil, detail: nil) }
        try store.save(record, image: image)
        receipts = store.receipts
    }

    func remove(_ id: String) throws {
        guard let store else { throw Problem(title: "Receipts are not open on this phone", status: nil, detail: nil) }
        try store.remove(id)
        receipts = store.receipts
    }
}

/// How receipts read on screen.
enum ReceiptFormat {
    static let currency = "USD"

    static func amount(_ cents: Int) -> String { money(cents, currency: currency) }

    /// "Nov 12" this year, "Nov 12, 2025" otherwise.
    static func day(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        return calendar.isDate(date, equalTo: now, toGranularity: .year)
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    static func month(_ start: Date) -> String { start.formatted(.dateTime.month(.wide).year()) }

    /// "Parts · Nov 12 · JOB-2214"
    static func rowSubtitle(_ receipt: ReceiptRecord) -> String {
        [receipt.category.label, day(receipt.date), receipt.jobReference ?? ""]
            .filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }

    /// "46.80", "$46.80", "1,204.5" or "46,80" as cents; nil when it is not an amount above zero.
    static func cents(_ text: String) -> Int? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "$", with: "")
        if value.contains(".") {
            value = value.replacingOccurrences(of: ",", with: "")
        } else if let comma = value.lastIndex(of: ","), value.distance(from: comma, to: value.endIndex) <= 3 {
            // A decimal comma from a keyboard that has no point.
            value.replaceSubrange(comma...comma, with: ".")
        }
        value = value.replacingOccurrences(of: ",", with: "")
        guard let cents = MoneyInput.cents(value), cents > 0 else { return nil }
        return cents
    }

    static func matches(_ receipt: ReceiptRecord, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return [receipt.merchant, receipt.category.label, receipt.jobReference ?? "", receipt.note ?? ""]
            .contains { $0.localizedCaseInsensitiveContains(needle) }
    }
}

/// The photo on disk: made small enough to keep, and read back off the main thread.
enum ReceiptPhoto {
    @MainActor
    static func jpeg(_ image: UIImage, maxSide: CGFloat = 2000) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxSide / longest)
        let size = CGSize(width: max(1, floor(image.size.width * scale)), height: max(1, floor(image.size.height * scale)))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.7) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    @MainActor
    static func load(_ url: URL) async -> UIImage? {
        let data = await Task.detached(priority: .userInitiated) { try? Data(contentsOf: url) }.value
        return data.flatMap { UIImage(data: $0) }
    }
}

private struct ReceiptOpen: Hashable { let id: String }

private struct ReceiptEditorRequest: Identifiable {
    let id = UUID()
    var record: ReceiptRecord?
    var startsWithCamera = false
}

private struct ReceiptExportFile: Identifiable {
    let id = UUID()
    let url: URL
    let folder: URL
}

/// Paper 46 "Receipts": the place header, the search field holding what narrows the list as chips,
/// then groups of rows with a 24pt circle that picks a receipt. Paper groups by Pending, Submitted
/// and Reimbursed and submits what is picked; nothing here is submitted, so the groups are months
/// and the bar shares what is picked as a CSV.
struct ReceiptsView: View {
    @EnvironmentObject private var session: SessionController
    @StateObject private var model = ReceiptsModel()
    @State private var query = ""
    @State private var thisMonthOnly = true
    @State private var category: ReceiptCategory?
    @State private var picked: Set<String> = []
    @State private var editor: ReceiptEditorRequest?
    @State private var opened: ReceiptOpen?
    @State private var export: ReceiptExportFile?
    @State private var actionError: String?

    init() {}

    private var identityKey: String { "\(session.activeOrganization?.id ?? "")|\(session.user?.id ?? "")" }

    /// "This month · $312.40 on this phone"
    private var subtitle: String {
        guard model.bound, !model.receipts.isEmpty else { return "Kept on this phone" }
        let total = ReceiptMath.monthTotal(model.receipts, containing: Date())
        return "This month \u{00B7} \(ReceiptFormat.amount(total)) on this phone"
    }

    private var chips: [PaperFilterChip] {
        var all: [PaperFilterChip] = []
        if thisMonthOnly { all.append(PaperFilterChip(id: "month", title: "This month") { thisMonthOnly = false }) }
        if let category { all.append(PaperFilterChip(id: "category", title: category.label) { self.category = nil }) }
        return all
    }

    private var shown: [ReceiptRecord] {
        let now = Date()
        return model.receipts.filter { receipt in
            (!thisMonthOnly || Calendar.current.isDate(receipt.date, equalTo: now, toGranularity: .month))
                && (category == nil || receipt.category == category)
                && ReceiptFormat.matches(receipt, query: query)
        }
    }

    private func filterItems(_ shown: [ReceiptRecord]) -> [ThorbisMenuItem] {
        var items = [
            ThorbisMenuItem("This month", icon: thisMonthOnly ? "checkmark" : "calendar") { thisMonthOnly = true },
            ThorbisMenuItem("All receipts", icon: thisMonthOnly ? "tray.full" : "checkmark") { thisMonthOnly = false },
        ]
        for (index, option) in ReceiptCategory.allCases.enumerated() {
            items.append(ThorbisMenuItem(option.label, icon: category == option ? "checkmark" : "tag", startsGroup: index == 0) {
                category = category == option ? nil : option
            })
        }
        if !shown.isEmpty {
            items.append(ThorbisMenuItem("Select all shown", icon: "checkmark.circle", startsGroup: true) {
                picked = Set(shown.map(\.id))
            })
        }
        return items
    }

    /// Paper 46's row: the 24pt circle, 12, the merchant over "Parts · Jul 18", the amount.
    private func row(_ receipt: ReceiptRecord, first: Bool) -> some View {
        let on = picked.contains(receipt.id)
        return HStack(spacing: 0) {
            Button {
                if on { picked.remove(receipt.id) } else { picked.insert(receipt.id) }
            } label: {
                ZStack {
                    if on {
                        Circle().fill(Theme.brand)
                        PaperIcon(.placeCheck, size: 12, color: .white)
                    } else {
                        Circle().strokeBorder(Theme.borderStrong, lineWidth: 1.5)
                    }
                }
                .frame(width: 24, height: 24)
                .padding(.leading, 16).padding(.trailing, 12)
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Select \(receipt.merchant)")
            .accessibilityAddTraits(on ? .isSelected : [])
            .accessibilityIdentifier("receipts-pick-\(receipt.id)")
            Button { opened = ReceiptOpen(id: receipt.id) } label: {
                OnPhoneRow(title: receipt.merchant, subtitle: ReceiptFormat.rowSubtitle(receipt)) {
                    PlaceAmount(text: ReceiptFormat.amount(receipt.totalCents))
                }
                .padding(.leading, -16)
            }
            .buttonStyle(RowPressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the receipt")
        }
    }

    @ViewBuilder private func groups(_ months: [ReceiptMonth]) -> some View {
        ForEach(months) { month in
            PaperCardLabel(title: ReceiptFormat.month(month.start), count: month.receipts.count)
                .padding(.top, 22)
            PaperRowsCard {
                ForEach(month.receipts) { receipt in
                    if receipt.id != month.receipts.first?.id { WellDivider(leading: 52) }
                    row(receipt, first: receipt.id == month.receipts.first?.id)
                }
            }
        }
    }

    /// Paper 46's bar: × lets go of the picks, the count over their total, then the one pill.
    private func selectionBar(_ chosen: [ReceiptRecord]) -> some View {
        HStack(spacing: 10) {
            Button { picked = [] } label: {
                PaperIcon(.close, size: 14)
                    .frame(width: 44, height: 44)
                    .background(Theme.quietFill, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Clear selection")
            VStack(alignment: .leading, spacing: 0) {
                Text("\(chosen.count) selected").font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.foreground)
                Text(ReceiptFormat.amount(ReceiptMath.total(chosen))).font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button { share(chosen) } label: {
                Text("Share CSV").paperButton(.secondary, tone: .brand)
            }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("receipts-share")
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 60)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 8)
        .padding(.horizontal, PaperCardMetrics.margin).padding(.bottom, 8)
    }

    var body: some View {
        let shown = shown
        let chosen = model.receipts.filter { picked.contains($0.id) }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Paper 46: the place header (menu circle, +, 34 Bold title, the month's total).
                PaperHeader(title: "Receipts", subtitle: subtitle)
                if model.bound && !model.receipts.isEmpty {
                    PlaceSearchField(query: $query, chips: chips, identifier: "receipts-search") {
                        ThorbisMenu(items: filterItems(shown), title: "Show", accessibilityLabel: "Filter receipts") {
                            PaperFilterCircle(active: category != nil)
                        }
                        .accessibilityIdentifier("header-filter")
                    }
                }
                if let message = actionError ?? model.error {
                    Text(message).font(Theme.font(15)).foregroundStyle(Theme.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.gutter).padding(.top, 14)
                }
                if !model.bound {
                    if model.error == nil { SkeletonRows(count: 3, leading: false, inset: 0).paperCardMargin().padding(.top, 22) }
                } else if model.receipts.isEmpty {
                    PaperEmptyState(symbol: "doc.text", title: "No receipts yet",
                                    message: "Photograph a receipt and its merchant, date and total are read for you to check. Receipts stay on this phone; the office doesn\u{2019}t see them.",
                                    actionTitle: "Add receipt") { editor = ReceiptEditorRequest(startsWithCamera: true) }
                        .paperCardMargin().padding(.top, 22)
                } else if shown.isEmpty {
                    PaperEmptyState(symbol: "magnifyingglass", title: thisMonthOnly && query.isEmpty && category == nil ? "No receipts this month" : "No matches",
                                    message: "Nothing matches what the list is narrowed to.",
                                    actionTitle: "Show all receipts") { query = ""; category = nil; thisMonthOnly = false }
                        .paperCardMargin().padding(.top, 22)
                } else {
                    groups(ReceiptMath.months(shown))
                }
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("receipts-root")
        .placeBarCreate("Add receipt", shows: model.bound) { editor = ReceiptEditorRequest() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.bound, !chosen.isEmpty { selectionBar(chosen) }
        }
        .task(id: identityKey) {
            editor = nil
            opened = nil
            actionError = nil
            picked = []
            model.bind(organizationID: session.activeOrganization?.id, userID: session.user?.id)
            #if DEBUG
            if PaperPreview.enabled {
                switch PaperPreview.screen {
                case "receipt-detail": opened = model.receipts.first.map { ReceiptOpen(id: $0.id) }
                case "receipt-editor": editor = ReceiptEditorRequest()
                default: picked = Set(model.receipts.prefix(2).map(\.id))
                }
            }
            #endif
        }
        .thorbisDestination(item: $opened) { ReceiptDetailView(id: $0.id, model: model) }
        .sheet(item: $editor) { request in SheetSurface {
            ReceiptEditor(existing: request.record, existingPhoto: request.record.flatMap { model.imageURL(for: $0) },
                          startsWithCamera: request.startsWithCamera) { record, image in
                try model.save(record, image: image)
                actionError = nil
            }
        } }
        .sheet(item: $export) { file in
            MediaShareSheet(urls: [file.url]) { try? FileManager.default.removeItem(at: file.folder) }
        }
    }

    /// Writes the picked receipts to a temporary CSV and hands it to the share sheet.
    private func share(_ receipts: [ReceiptRecord]) {
        guard !receipts.isEmpty else { return }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("receipts-export-\(UUID().uuidString)", isDirectory: true)
        let url = folder.appendingPathComponent("Receipts.csv")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(ReceiptMath.csv(receipts).utf8).write(to: url, options: .atomic)
            actionError = nil
            export = ReceiptExportFile(url: url, folder: folder)
        } catch {
            actionError = "The CSV couldn\u{2019}t be written. \(error.localizedDescription)"
        }
    }
}

/// The receipt's photo, or a quiet page mark when it has none.
private struct ReceiptThumb: View {
    let image: UIImage?
    var width: CGFloat = 84
    var height: CGFloat = 112

    var body: some View {
        ZStack {
            Theme.fill
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "doc.text").font(.system(size: 22)).foregroundStyle(Theme.muted)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, lineWidth: 1) }
        .accessibilityHidden(true)
    }
}

/// Paper 46A "Receipt detail": the photo beside the total, the merchant and the day, then what it
/// was for. The design's Review, Approve and "Read from the photo" lines belong to an office
/// review that does not exist here, so they are not drawn.
private struct ReceiptDetailView: View {
    let id: String
    @ObservedObject var model: ReceiptsModel
    @Environment(\.dismiss) private var dismiss
    @State private var editor: ReceiptEditorRequest?
    @State private var confirmDelete = false
    @State private var actionError: String?
    @State private var photo: UIImage?
    @State private var showPhoto = false

    /// "Today 9:20 AM", "Yesterday 4:05 PM", "Mon, Nov 9 10:00 AM"
    private func when(_ date: Date) -> String {
        let calendar = Calendar.current
        let day = calendar.isDateInToday(date) ? "Today" : calendar.isDateInYesterday(date) ? "Yesterday"
            : date.formatted(calendar.isDate(date, equalTo: Date(), toGranularity: .year)
                             ? .dateTime.weekday(.abbreviated).month(.abbreviated).day()
                             : .dateTime.month(.abbreviated).day().year())
        return "\(day) \(date.tradeTime)"
    }

    /// Paper 46A's field row: it opens the editor, so it ends in the 14pt chevron.
    private func fieldRow<Content: View>(height: CGFloat, identifier: String, _ receipt: ReceiptRecord,
                                         @ViewBuilder content: () -> Content) -> some View {
        Button { editor = ReceiptEditorRequest(record: receipt) } label: {
            HStack(alignment: .center, spacing: 12) {
                content()
                PaperIcon(.chevronRightSmall, size: 14, color: Theme.subtleForeground).accessibilityHidden(true)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the receipt to edit")
        .accessibilityIdentifier(identifier)
    }

    private func page(_ receipt: ReceiptRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                if let photo {
                    Button { showPhoto = true } label: { ReceiptThumb(image: photo) }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Receipt photo")
                        .accessibilityHint("Opens the photo")
                        .accessibilityIdentifier("receipts-photo")
                } else {
                    ReceiptThumb(image: nil)
                }
                // Paper 46A: the total in 28 Bold, the merchant in 16 Semibold, then when.
                VStack(alignment: .leading, spacing: 4) {
                    Text(ReceiptFormat.amount(receipt.totalCents)).font(Theme.heading()).tracking(-0.56)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(receipt.merchant).font(Theme.font(16, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(when(receipt.date))
                        .font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if receipt.imageFile != nil, photo == nil {
                        Text("Photo not found on this phone").font(Theme.font(14)).foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
            if let actionError {
                Text(actionError).font(Theme.font(15)).foregroundStyle(Theme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
            }
            TimeClockCard {
                fieldRow(height: 56, identifier: "receipts-edit", receipt) {
                    Text("Category").font(Theme.font(16)).foregroundStyle(Theme.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(receipt.category.label).font(Theme.font(16)).foregroundStyle(Theme.muted)
                }
                WellDivider(leading: 0)
                fieldRow(height: 64, identifier: "receipts-edit-job", receipt) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Job").font(Theme.font(13)).foregroundStyle(Theme.muted)
                        Text(receipt.jobReference ?? "None").font(Theme.font(16, weight: .medium))
                            .foregroundStyle(receipt.jobReference == nil ? Theme.muted : Theme.foreground)
                            .multilineTextAlignment(.leading)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 2)
            if let note = receipt.note, !note.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Note").font(Theme.font(13)).foregroundStyle(Theme.muted)
                    Text(note).font(Theme.font(16)).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .accessibilityElement(children: .combine)
            }
            Text("Saved on this phone only. The office doesn\u{2019}t see it.")
                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
                .padding(.top, 4)
        }
    }

    var body: some View {
        let receipt = model.receipt(id)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let receipt {
                    page(receipt)
                } else {
                    Text("This receipt is no longer on this phone.").font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .paperCardMargin().padding(.top, 14).padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if receipt != nil {
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    ThorbisMenu(items: [
                        ThorbisMenuItem("Edit", icon: "pencil") { editor = model.receipt(id).map { ReceiptEditorRequest(record: $0) } },
                        ThorbisMenuItem("Delete", icon: "trash", role: .destructive) { confirmDelete = true },
                    ], accessibilityLabel: "Receipt actions") {
                        PaperCircleLabel(symbol: "ellipsis", size: 44, fill: Theme.card)
                    }
                    .accessibilityIdentifier("receipts-actions")
                }
            }
        }
        .task(id: receipt?.imageFile) {
            photo = nil
            guard let receipt, let url = model.imageURL(for: receipt) else { return }
            photo = await ReceiptPhoto.load(url)
        }
        .sheet(item: $editor) { request in SheetSurface {
            ReceiptEditor(existing: request.record, existingPhoto: request.record.flatMap { model.imageURL(for: $0) },
                          startsWithCamera: false) { record, image in
                try model.save(record, image: image)
                actionError = nil
            }
        } }
        .sheet(isPresented: $showPhoto) { SheetSurface { ReceiptPhotoSheet(image: photo) } }
        .thorbisConfirm("Delete this receipt?",
                        message: "It and its photo are removed from this phone. This can\u{2019}t be undone.",
                        isPresented: $confirmDelete,
                        actions: [ThorbisConfirmAction("Delete", role: .destructive) {
                            do {
                                try model.remove(id)
                                dismiss()
                            } catch {
                                actionError = error.localizedDescription
                            }
                        }])
    }
}

/// The whole photo, to read a line the form didn't keep.
private struct ReceiptPhotoSheet: View {
    let image: UIImage?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Receipt photo").font(Theme.font(17, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                PaperCircleButton(symbol: "xmark", label: "Close", size: 36, fill: Theme.card) { dismiss() }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
            ScrollView {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(16)
                        .accessibilityLabel("Photo of the receipt")
                } else {
                    Text("The photo is not on this phone.").font(Theme.font(15)).foregroundStyle(Theme.muted).padding(16)
                }
            }
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background.ignoresSafeArea())
    }
}

/// Paper 44 "Add receipt", used to add by hand, to check what a photo read, and to edit.
/// The close circle, the 34 Bold title, the "read from the photo" note, Receipt details, Category
/// chips, the job, then the one commit. The design's "Submit for reimbursement" has nowhere to
/// submit to, so the commit saves.
private struct ReceiptEditor: View {
    private enum Field: Hashable { case merchant, total, job, note }
    private enum Reading: Equatable {
        case none, working
        /// What the photo filled in, by name ("merchant", "total", "date").
        case filled([String])
        case nothing
    }

    let existing: ReceiptRecord?
    let existingPhoto: URL?
    let startsWithCamera: Bool
    let onSave: (ReceiptRecord, ReceiptImageChange) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var merchant: String
    @State private var totalText: String
    @State private var date: Date
    @State private var category: ReceiptCategory
    @State private var job: String
    @State private var note: String
    /// Fields a photo filled and nobody has typed in since; a retake may overwrite them.
    @State private var fromPhoto: Set<Field> = []
    @State private var dateTouched: Bool
    @State private var shownPhoto: UIImage?
    @State private var newPhoto: UIImage?
    @State private var removedPhoto = false
    @State private var reading: Reading = .none
    @State private var showCamera = false
    @State private var showPicker = false
    @State private var picked: PhotosPickerItem?
    @State private var missing: Set<Field> = []
    @State private var error: String?
    @State private var openedCamera = false
    @State private var picking: PlaceDatePick?
    @FocusState private var focus: Field?

    init(existing: ReceiptRecord?, existingPhoto: URL?, startsWithCamera: Bool,
         onSave: @escaping (ReceiptRecord, ReceiptImageChange) throws -> Void) {
        self.existing = existing
        self.existingPhoto = existingPhoto
        self.startsWithCamera = startsWithCamera
        self.onSave = onSave
        _merchant = State(initialValue: existing?.merchant ?? "")
        _totalText = State(initialValue: existing.map { ReceiptMath.plainAmount($0.totalCents) } ?? "")
        _date = State(initialValue: existing?.date ?? Date())
        _category = State(initialValue: existing?.category ?? .parts)
        _job = State(initialValue: existing?.jobReference ?? "")
        _note = State(initialValue: existing?.note ?? "")
        _dateTouched = State(initialValue: existing != nil)
    }

    private var cameraDenied: Bool {
        [.denied, .restricted].contains(AVCaptureDevice.authorizationStatus(for: .video))
    }
    private var cameraUsable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) && !cameraDenied }

    private func typed(_ field: Field, _ text: Binding<String>) -> Binding<String> {
        Binding(get: { text.wrappedValue },
                set: { text.wrappedValue = $0; fromPhoto.remove(field); missing.remove(field) })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                PaperCircleButton(symbol: "xmark", label: "Close without saving", size: 44, fill: Theme.card) { dismiss() }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.top, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PaperPageTitle(title: existing == nil ? "Add receipt" : "Edit receipt",
                                   columnInset: PaperCardMetrics.margin, underBar: false)
                    if let error {
                        Text(error).font(Theme.font(15)).foregroundStyle(Theme.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                    readingNote
                    photoCard
                    detailsCard
                    VStack(alignment: .leading, spacing: 8) {
                        PaperSectionLabel(title: "Category", gap: 0)
                        // Paper 44: 40-tall pills in 14; the chosen one on the brand tint in brand ink.
                        FlowRow(spacing: 8, lineSpacing: 8) {
                            ForEach(ReceiptCategory.allCases, id: \.self) { choice in
                                let on = choice == category
                                Button { category = choice } label: {
                                    PaperChoiceChipLabel(title: choice.label, isOn: on)
                                }
                                .buttonStyle(PressStyle())
                                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                                .accessibilityIdentifier("receipts-category-\(choice.rawValue)")
                            }
                        }
                    }
                    textCard(label: "Job", prompt: "Job number or name (optional)", text: typed(.job, $job), field: .job,
                             help: "Written as text. It isn\u{2019}t linked to the job\u{2019}s record.")
                    textCard(label: "Note", prompt: "Anything worth remembering (optional)", text: typed(.note, $note),
                             field: .note, multiline: true)
                    Text("Saved on this phone only. The office doesn\u{2019}t see it and nothing is submitted for reimbursement.")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Never pre-disabled: pressed with the merchant or total missing, it says which under it.
            PaperActionBar(title: "Save receipt", identifier: "receipts-save") { save() }
        }
        .placeDatePicker($picking)
        .photosPicker(isPresented: $showPicker, selection: $picked, matching: .images)
        .fullScreenCover(isPresented: $showCamera) {
            CameraCapture { image in
                showCamera = false
                if let image { Task { await take(image) } }
            }
            .ignoresSafeArea()
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                defer { picked = nil }
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                    error = "That photo couldn\u{2019}t be opened."
                    return
                }
                await take(image)
            }
        }
        .task {
            if let existingPhoto, shownPhoto == nil { shownPhoto = await ReceiptPhoto.load(existingPhoto) }
            // Paper 45: "Photograph receipt" goes straight to the camera once the sheet has settled.
            guard startsWithCamera, !openedCamera, cameraUsable else { return }
            openedCamera = true
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled { showCamera = true }
        }
    }

    /// Paper 44's note above the form, in plain words: what the photo filled in, to be checked.
    @ViewBuilder private var readingNote: some View {
        switch reading {
        case .none:
            EmptyView()
        case .working:
            noteCard(title: "Reading the photo", body: "Looking for the vendor, total and date.", busy: true)
        case .filled(let names):
            noteCard(title: "Read from the photo",
                     body: "\(Self.sentence(names)) filled in. Check \(names.count == 1 ? "it" : "them") before saving.", busy: false)
        case .nothing:
            noteCard(title: "Nothing could be read",
                     body: "The photo is attached. Enter the vendor, total and date by hand.", busy: false)
        }
    }

    /// "Merchant, total and date were" / "Total was"
    private static func sentence(_ names: [String]) -> String {
        guard let last = names.last else { return "Nothing was" }
        let lead = names.dropLast().joined(separator: ", ")
        let list = lead.isEmpty ? last : "\(lead) and \(last)"
        return list.prefix(1).uppercased() + String(list.dropFirst()) + (names.count == 1 ? " was" : " were")
    }

    private func noteCard(title: String, body: String, busy: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if busy { ProgressView().tint(Theme.brandText) } else {
                    PaperIcon(.placeBolt, size: 16, color: Theme.brandText)
                }
            }
            .frame(width: 16, height: 16).padding(.top, 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.brandText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(body).font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.brandSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("receipts-reading-note")
    }

    private func quietPill(_ title: String, symbol: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium)).accessibilityHidden(true)
                Text(title).fixedSize(horizontal: false, vertical: true)
            }
            .paperButton(.secondary, tone: .quiet)
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier(identifier)
    }

    /// The photo and how to take one. With no photo the form still saves: a receipt can be entered by hand.
    private var photoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                if let shownPhoto { ReceiptThumb(image: shownPhoto, width: 64, height: 80) }
                VStack(alignment: .leading, spacing: 10) {
                    Text(shownPhoto == nil ? "Photo" : "Photo attached").font(Theme.font(16, weight: .medium))
                    if shownPhoto == nil {
                        Text("Take a photo and the vendor, total and date are read from it on this phone.")
                            .font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    FlowRow(spacing: 8, lineSpacing: 8) {
                        if cameraUsable {
                            quietPill(shownPhoto == nil ? "Take photo" : "Retake", symbol: "camera",
                                      identifier: "receipts-take-photo") { showCamera = true }
                        }
                        quietPill("Choose photo", symbol: "photo.on.rectangle", identifier: "receipts-choose-photo") { showPicker = true }
                        if shownPhoto != nil {
                            quietPill("Remove", symbol: "trash", identifier: "receipts-remove-photo") {
                                shownPhoto = nil
                                newPhoto = nil
                                removedPhoto = true
                                reading = .none
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if cameraDenied {
                PermissionNotice(permission: .camera, purpose: "photograph receipts", outer: 0)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    /// Paper 44 "Receipt details": the label on the left, the answer on the right, 56 tall.
    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaperSectionLabel(title: "Receipt details", gap: 0)
            VStack(alignment: .leading, spacing: 0) {
                inlineRow("Vendor", problem: missing.contains(.merchant) ? "Add the vendor to save." : nil) {
                    TextField("", text: typed(.merchant, $merchant), prompt: .placeholder("Where it was bought"))
                        .font(Theme.font(15, weight: .medium)).multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                        .focused($focus, equals: .merchant)
                        .accessibilityLabel("Vendor")
                        .accessibilityIdentifier("receipts-merchant")
                }
                WellDivider(leading: 16)
                inlineRow("Total", problem: missing.contains(.total) ? "Enter the total, like 46.80." : nil) {
                    TextField("", text: typed(.total, $totalText), prompt: .placeholder("0.00"))
                        .font(Theme.font(15, weight: .medium)).monospacedDigit().multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .focused($focus, equals: .total)
                        .accessibilityLabel("Total in dollars")
                        .accessibilityIdentifier("receipts-total")
                }
                WellDivider(leading: 16)
                Button {
                    focus = nil
                    picking = PlaceDatePick(id: "date", title: "Date", date: date, includesTime: true, upper: Date()) {
                        date = $0
                        dateTouched = true
                    }
                } label: {
                    inlineRow("Date", problem: nil) {
                        Text(Self.dayAndTime(date)).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                            .multilineTextAlignment(.trailing)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .accessibilityLabel("Date, \(Self.dayAndTime(date))")
                .accessibilityIdentifier("receipts-date")
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
    }

    /// "Today, 9:20 AM", "Mon, Nov 9, 10:00 AM"
    private static func dayAndTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let day = calendar.isDateInToday(date) ? "Today" : calendar.isDateInYesterday(date) ? "Yesterday"
            : date.formatted(calendar.isDate(date, equalTo: Date(), toGranularity: .year)
                             ? .dateTime.weekday(.abbreviated).month(.abbreviated).day()
                             : .dateTime.month(.abbreviated).day().year())
        return "\(day), \(date.tradeTime)"
    }

    /// Paper 44's row: the 15 label, then the 15 Medium answer and the 12pt up-and-down mark.
    private func inlineRow<Answer: View>(_ label: String, problem: String?, @ViewBuilder answer: () -> Answer) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(label).font(Theme.font(15)).foregroundStyle(Theme.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .accessibilityHidden(true)
                Spacer(minLength: 6)
                answer()
                PaperIcon(.placeUpDown, size: 12, color: Theme.muted).frame(width: 14).accessibilityHidden(true)
            }
            if let problem { FieldProblem(message: problem) }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    }

    private func textCard(label: String, prompt: String, text: Binding<String>, field: Field,
                          multiline: Bool = false, help: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.font(13)).foregroundStyle(Theme.muted).accessibilityHidden(true)
            TextField("", text: text, prompt: .placeholder(prompt), axis: multiline ? .vertical : .horizontal)
                .font(multiline ? Theme.font(15) : Theme.font(17, weight: .medium))
                .frame(minHeight: 28)
                .focused($focus, equals: field)
                .accessibilityLabel(label)
            if let help {
                Text(help).font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    /// Keeps the photo and fills in what Vision could read, leaving anything typed by hand alone.
    private func take(_ image: UIImage) async {
        error = nil
        shownPhoto = image
        newPhoto = image
        removedPhoto = false
        reading = .working
        let result = await DataPlateOCR.read(image)
        // Removed or retaken while it was being read: this reading is for a photo no longer shown.
        guard newPhoto === image else { return }
        let read = ReceiptTextParser.parse(lines: result.lines)
        var names: [String] = []
        if let name = read.merchant, merchant.trimmingCharacters(in: .whitespaces).isEmpty || fromPhoto.contains(.merchant) {
            merchant = name
            fromPhoto.insert(.merchant)
            missing.remove(.merchant)
            names.append("vendor")
        }
        if let cents = read.totalCents, cents > 0, totalText.trimmingCharacters(in: .whitespaces).isEmpty || fromPhoto.contains(.total) {
            totalText = ReceiptMath.plainAmount(cents)
            fromPhoto.insert(.total)
            missing.remove(.total)
            names.append("total")
        }
        if let day = read.date, !dateTouched {
            date = day
            names.append("date")
        }
        reading = names.isEmpty ? .nothing : .filled(names)
    }

    private func save() {
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        var empty: Set<Field> = []
        if name.isEmpty { empty.insert(.merchant) }
        let cents = ReceiptFormat.cents(totalText)
        if cents == nil { empty.insert(.total) }
        guard empty.isEmpty, let cents else {
            missing = empty
            focus = empty.contains(.merchant) ? .merchant : .total
            return
        }
        var change = ReceiptImageChange.keep
        if let newPhoto {
            guard let data = ReceiptPhoto.jpeg(newPhoto) else {
                error = "The photo couldn\u{2019}t be saved. Take it again, or remove it and save without it."
                return
            }
            change = .replace(data)
        } else if removedPhoto {
            change = .remove
        }
        let jobText = job.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteText = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = ReceiptRecord(id: existing?.id ?? UUID().uuidString, merchant: name, date: date, totalCents: cents,
                                   category: category, jobReference: jobText.isEmpty ? nil : jobText,
                                   note: noteText.isEmpty ? nil : noteText, imageFile: existing?.imageFile,
                                   createdAt: existing?.createdAt ?? Date())
        do {
            try onSave(record, change)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
