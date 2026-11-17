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
            let opened = try ReceiptsStore(organizationID: organizationID, userID: userID, directory: directory)
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
        calendar.isDate(date, equalTo: now, toGranularity: .year)
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

struct ReceiptsView: View {
    @EnvironmentObject private var session: SessionController
    @StateObject private var model = ReceiptsModel()
    @State private var query = ""
    @State private var editor: ReceiptEditorRequest?
    @State private var opened: ReceiptOpen?
    @State private var export: ReceiptExportFile?
    @State private var actionError: String?

    init() {}

    private var identityKey: String { "\(session.activeOrganization?.id ?? "")|\(session.user?.id ?? "")" }

    private var subtitle: String {
        guard model.bound, !model.receipts.isEmpty else { return "On this phone \u{00B7} Not shared with the office" }
        let total = ReceiptMath.monthTotal(model.receipts, containing: Date())
        return "This month \u{00B7} \(ReceiptFormat.amount(total)) \u{00B7} On this phone"
    }

    /// The search on the card (46 tall, radius 14); it narrows this list.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.muted).accessibilityHidden(true)
            TextField("", text: $query, prompt: .placeholder("Merchant, category or job"))
                .font(Theme.font(16)).foregroundStyle(Theme.foreground)
                .autocorrectionDisabled()
                .frame(minHeight: 46)
                .accessibilityLabel("Search receipts")
                .accessibilityIdentifier("receipts-search")
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

    /// One month on one card: its receipts, then the month's total. "Share CSV" sits beside the label.
    private func monthSection(_ month: ReceiptMonth) -> some View {
        PaperSection(title: ReceiptFormat.month(month.start), count: month.receipts.count) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(month.receipts) { receipt in
                    if receipt.id != month.receipts.first?.id { WellDivider() }
                    Button { opened = ReceiptOpen(id: receipt.id) } label: {
                        PaperListRow(title: receipt.merchant, subtitle: ReceiptFormat.rowSubtitle(receipt),
                                     amount: ReceiptFormat.amount(receipt.totalCents))
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Opens the receipt")
                }
                WellDivider()
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(query.isEmpty ? "Month total" : "Total of matches").font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text(ReceiptFormat.amount(month.totalCents)).font(Theme.amountFont(16)).foregroundStyle(Theme.foreground)
                }
                .padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 48)
                .accessibilityElement(children: .combine)
            }
        } accessory: {
            Button { share(month.id) } label: {
                Text("Share CSV").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.brandText)
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Share \(ReceiptFormat.month(month.start)) as a CSV file")
            .accessibilityIdentifier("receipts-share-\(month.id)")
        }
    }

    var body: some View {
        let shown = ReceiptMath.months(model.receipts.filter { ReceiptFormat.matches($0, query: query) })
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Paper 46: the place header (menu circle, +, 34 Bold title, the month's total).
                PaperHeader(title: "Receipts", subtitle: subtitle, showsCreate: model.bound)
                    .environment(\.paperCreate, model.bound
                                 ? PaperCreateAction(label: "Add receipt", run: { editor = ReceiptEditorRequest() })
                                 : nil)
                if model.bound && !model.receipts.isEmpty { searchField.padding(.top, 2) }
                VStack(alignment: .leading, spacing: 20) {
                    if let message = actionError ?? model.error {
                        Text(message).font(Theme.font(15)).foregroundStyle(Theme.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
                    }
                    if !model.bound {
                        if model.error == nil { SkeletonRows(count: 3, leading: false, inset: 0) }
                    } else if model.receipts.isEmpty {
                        PaperEmptyState(symbol: "doc.text", title: "No receipts yet",
                                        message: "Photograph a receipt and its merchant, date and total are read for you to check. Or add one by hand.",
                                        actionTitle: "Add receipt") { editor = ReceiptEditorRequest() }
                    } else if shown.isEmpty {
                        PaperEmptyState(symbol: "magnifyingglass", title: "No matches",
                                        message: "No merchant, category, job or note matches \u{201C}\(query)\u{201D}.",
                                        actionTitle: "Clear search") { query = "" }
                    } else {
                        ForEach(shown) { month in monthSection(month) }
                    }
                    if model.bound {
                        Text("Receipts and their photos are saved on this phone only. The office doesn\u{2019}t see them and nothing is submitted for reimbursement; share a month\u{2019}s CSV to hand them in.")
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
        .accessibilityIdentifier("receipts-root")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Paper 45: photographing is the main way in.
            if model.bound {
                PaperActionBar(title: "Photograph receipt", symbol: "camera", identifier: "receipts-photograph") {
                    editor = ReceiptEditorRequest(startsWithCamera: true)
                }
            }
        }
        .task(id: identityKey) {
            editor = nil
            opened = nil
            actionError = nil
            model.bind(organizationID: session.activeOrganization?.id, userID: session.user?.id)
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

    /// Writes the whole month (not only the search's matches) to a temporary CSV and hands it to the share sheet.
    private func share(_ monthID: String) {
        guard let month = ReceiptMath.months(model.receipts).first(where: { $0.id == monthID }) else { return }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("receipts-export-\(UUID().uuidString)", isDirectory: true)
        let url = folder.appendingPathComponent("Receipts-\(month.id).csv")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(ReceiptMath.csv(month.receipts).utf8).write(to: url, options: .atomic)
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
    var height: CGFloat = 104

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

    private func page(_ receipt: ReceiptRecord) -> some View {
        VStack(alignment: .leading, spacing: 20) {
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(ReceiptFormat.amount(receipt.totalCents)).font(Theme.font(30, weight: .bold)).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(receipt.merchant).font(Theme.font(17, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(receipt.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                        .font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
            if let actionError {
                Text(actionError).font(Theme.font(15)).foregroundStyle(Theme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
            }
            PaperSection(title: "Details") {
                VStack(alignment: .leading, spacing: 0) {
                    PaperDetailRow("Category", value: receipt.category.label)
                        .padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 52)
                    WellDivider()
                    PaperDetailRow("Job", value: receipt.jobReference ?? "None")
                        .padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 52)
                    WellDivider()
                    PaperDetailRow("Photo", value: receipt.imageFile == nil ? "None" : (photo == nil ? "Not found on this phone" : "Attached"))
                        .padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 52)
                }
            } accessory: {
                Button { editor = ReceiptEditorRequest(record: receipt) } label: {
                    Text("Edit").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.brandText)
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Edit receipt")
                .accessibilityIdentifier("receipts-edit")
            }
            if let note = receipt.note, !note.isEmpty {
                PaperSection("Note") {
                    Text(note).font(Theme.font(15)).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
                }
            }
            Text("Saved on this phone only. The office doesn\u{2019}t see it.")
                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
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
            .paperCardMargin().padding(.top, 8).padding(.bottom, 24)
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
                VStack(alignment: .leading, spacing: 16) {
                    Text(existing == nil ? "Add receipt" : "Edit receipt")
                        .font(Theme.font(34, weight: .bold)).tracking(-0.85)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 4)
                    if let error {
                        Text(error).font(Theme.font(15)).foregroundStyle(Theme.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                    readingNote
                    photoCard
                    detailsCard
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Category").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                            .padding(.horizontal, 4).accessibilityAddTraits(.isHeader)
                        ThorbisChipGroup(data: ReceiptCategory.allCases, id: \.self,
                                         isOn: { $0 == category }, label: { $0.label }, toggle: { category = $0 })
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
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 24)
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
            noteCard(title: "Reading the photo", body: "Looking for the merchant, total and date.", busy: true)
        case .filled(let names):
            noteCard(title: "Read from the photo",
                     body: "\(Self.sentence(names)) filled in. Check \(names.count == 1 ? "it" : "them") before saving.", busy: false)
        case .nothing:
            noteCard(title: "Nothing could be read",
                     body: "The photo is attached. Enter the merchant, total and date by hand.", busy: false)
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
                    Image(systemName: "text.viewfinder").font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.brandText)
                }
            }
            .frame(width: 20, height: 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.brandText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(body).font(Theme.font(14)).foregroundStyle(Theme.foreground)
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
                Text(title).font(Theme.font(14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(Theme.fill, in: Capsule())
            .contentShape(Capsule())
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
                        Text("Take a photo and the merchant, total and date are read from it on this phone.")
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
            Text("Receipt details").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                .padding(.horizontal, 4).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                inlineRow("Merchant", problem: missing.contains(.merchant) ? "Add the merchant to save." : nil) {
                    TextField("", text: typed(.merchant, $merchant), prompt: .placeholder("Where it was bought"))
                        .font(Theme.font(16)).multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                        .focused($focus, equals: .merchant)
                        .accessibilityLabel("Merchant")
                        .accessibilityIdentifier("receipts-merchant")
                }
                WellDivider(leading: 16)
                inlineRow("Total", problem: missing.contains(.total) ? "Enter the total, like 46.80." : nil) {
                    TextField("", text: typed(.total, $totalText), prompt: .placeholder("0.00"))
                        .font(Theme.font(16)).monospacedDigit().multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .focused($focus, equals: .total)
                        .accessibilityLabel("Total in dollars")
                        .accessibilityIdentifier("receipts-total")
                }
                WellDivider(leading: 16)
                inlineRow("Date", problem: nil) {
                    DatePicker("Date", selection: Binding(get: { date }, set: { date = $0; dateTouched = true }),
                               in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                        .tint(Theme.brand)
                        .accessibilityIdentifier("receipts-date")
                }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
    }

    private func inlineRow<Answer: View>(_ label: String, problem: String?, @ViewBuilder answer: () -> Answer) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(label).font(Theme.font(16)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                answer()
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
            names.append("merchant")
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
