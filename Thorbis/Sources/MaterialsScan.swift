import SwiftUI
import PhotosUI
import VisionKit
import AVFoundation

// Paper 30 "Add materials · Scan" and the sheet that holds Scan and Paste (Paper 32). A barcode, or a
// part number tapped in the camera, is looked up in the cached price book with the same on-device
// search as the price book picker, and staged as a line. "Add 2 items · $110.00" hands each unit
// to the builder through the same `addItem` closure the picker takes, one unit at a time.
//
// Price book items have no barcode or SKU field, so a code only matches when it appears in an
// item's name. Live scanning uses VisionKit's DataScanner (as DataPlateScanner does); where it isn't
// available a photo is read with Vision instead.

enum AddMaterialsMode: String, CaseIterable, Identifiable {
    case scan, paste

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scan: "Scan"
        case .paste: "Paste"
        }
    }
}

private struct MaterialsLoadScope: Equatable {
    let context: PriceBookCatalogContext
    let apiGeneration: UUID
}

/// Entry point. Present as a sheet from the builder's add-item area, with the same values the
/// price book picker gets:
///
///     .sheet(isPresented: $showMaterials) { SheetSurface {
///         AddMaterialsSheet(initialMode: .scan, canUsePriceBook: canUsePriceBook,
///                           addItem: addCatalogItem, refresh: { await refreshCatalog(force: $0) },
///                           openPriceBook: { showPriceBook = true })
///         .environmentObject(session).environmentObject(api)
///     } }
///
/// `addItem` returns nil when the builder took one unit, else the reason it refused (shown here).
/// `openPriceBook`, when given, adds Paper's "Price book" segment; it runs after this sheet closes.
struct AddMaterialsSheet: View {
    let canUsePriceBook: Bool
    let unavailableReason: String?
    /// A limit that still applies while adding (e.g. a draft that can't be saved yet).
    let notice: String?
    let addItem: (PriceBookListItem) -> String?
    let refresh: (_ force: Bool) async -> Void
    let openPriceBook: (() -> Void)?

    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var catalog = PriceBookCatalog.shared
    @State private var mode: AddMaterialsMode
    @State private var tab: String
    @State private var scanRows: [StagedMaterial] = []
    @State private var pasteRows: [StagedMaterial] = []
    @State private var pasteText = ""
    @State private var pasteEdited = false

    init(initialMode: AddMaterialsMode = .scan,
         canUsePriceBook: Bool,
         unavailableReason: String? = nil,
         notice: String? = nil,
         addItem: @escaping (PriceBookListItem) -> String?,
         refresh: @escaping (_ force: Bool) async -> Void,
         openPriceBook: (() -> Void)? = nil) {
        self.canUsePriceBook = canUsePriceBook
        self.unavailableReason = unavailableReason
        self.notice = notice
        self.addItem = addItem
        self.refresh = refresh
        self.openPriceBook = openPriceBook
        _mode = State(initialValue: initialMode)
        _tab = State(initialValue: initialMode.title)
    }

    private static let priceBookTab = "Price book"

    private var tabOptions: [String] {
        var options = AddMaterialsMode.allCases.map { $0.title }
        if openPriceBook != nil { options.append(Self.priceBookTab) }
        return options
    }

    private var context: PriceBookCatalogContext {
        .init(organizationID: session.activeOrganization?.id, sessionGeneration: session.generation,
              authority: session.priceBookAuthority)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let notice {
                ErrorBanner(message: notice, outer: PaperCardMetrics.margin)
            }
            if !canUsePriceBook {
                ErrorBanner(message: unavailableReason ?? "This account cannot select Price Book items.",
                            symbol: "book.closed", tint: Theme.muted, outer: PaperCardMetrics.margin)
            } else if let error = catalog.error {
                ErrorBanner(message: error, action: ErrorBanner.Action(title: "Try again") { await refresh(true) },
                            outer: PaperCardMetrics.margin)
            }
            switch mode {
            case .scan:
                MaterialsScanView(canAdd: canUsePriceBook, rows: $scanRows, add: addOne, finish: { dismiss() })
            case .paste:
                MaterialsPasteView(canAdd: canUsePriceBook, text: $pasteText, rows: $pasteRows, edited: $pasteEdited,
                                   add: addOne, finish: { dismiss() })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.canvas)
        .paperPageGround()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task(id: MaterialsLoadScope(context: context, apiGeneration: api.requestGeneration)) {
            await refresh(false)
        }
        .onChange(of: tab) { _, value in
            if value == Self.priceBookTab {
                // Tell the host first, so it opens the price book once this sheet has closed.
                openPriceBook?()
                dismiss()
            } else if let picked = AddMaterialsMode.allCases.first(where: { $0.title == value }) {
                mode = picked
            }
        }
    }

    /// Paper 30/32: the 44 close circle, "Add materials" at 34 Bold, then the segments.
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperCircleButton(symbol: "xmark", label: "Close", size: 44, fill: Theme.card, action: { dismiss() })
                .accessibilityIdentifier("materials-close")
                .padding(.horizontal, PaperCardMetrics.margin)
            Text("Add materials").font(Theme.font(34, weight: .bold)).tracking(-0.85)
                .foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.gutter).padding(.top, 14)
            if tabOptions.count > 1 {
                PaperTabs(options: tabOptions, selection: $tab)
                    .padding(.top, 16)
                    .accessibilityIdentifier("materials-mode")
            }
        }
        .padding(.top, 14)
    }

    /// One unit to the builder, behind the same checks as the price book picker's "+".
    private func addOne(_ item: PriceBookListItem) -> String? {
        let current = context
        guard canUsePriceBook, session.can("pricebook.view", feature: "price_book"),
              session.priceBookAuthority == current.authority,
              catalog.isCurrent(current, api: api) else {
            return "The price book is still loading or has changed. Try again in a moment."
        }
        // Staged lines hold the item as it was when matched; hand the builder the current revision.
        guard let fresh = catalog.item(id: item.id), fresh.archivedAt == nil else {
            return "\(item.description) is no longer in the price book."
        }
        if let message = addItem(fresh) { return message }
        catalog.recordUse(fresh.id)
        return nil
    }
}

// MARK: - Scan

/// Paper 30's body: the camera frame, then "Scanned just now" and the commit.
struct MaterialsScanView: View {
    let canAdd: Bool
    @Binding var rows: [StagedMaterial]
    let add: (PriceBookListItem) -> String?
    let finish: () -> Void

    @ObservedObject private var catalog = PriceBookCatalog.shared
    @State private var typing = false
    @State private var typedCode = ""
    @State private var reviewing: StagedMaterial?
    @State private var problem: String?
    @State private var photo: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showPicker = false
    @State private var reading = false
    @State private var addedUnits = 0
    @FocusState private var codeFocused: Bool

    init(canAdd: Bool, rows: Binding<[StagedMaterial]>, add: @escaping (PriceBookListItem) -> String?,
         finish: @escaping () -> Void) {
        self.canAdd = canAdd
        _rows = rows
        self.add = add
        self.finish = finish
    }

    private var cameraDenied: Bool {
        [.denied, .restricted].contains(AVCaptureDevice.authorizationStatus(for: .video))
    }

    private var liveAvailable: Bool {
        !cameraDenied && DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    private var unresolvedCount: Int { rows.filter { !$0.isResolved }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                viewfinder
                    .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 16)
                if cameraDenied {
                    PermissionNotice(permission: .camera, purpose: "scan barcodes", outer: PaperCardMetrics.margin)
                }
                photoFallback
                if typing {
                    codeField
                }
                if catalog.loading, catalog.index.count == 0 {
                    ThorbisLoadingLine(message: "Loading the price book\u{2026}")
                        .padding(.horizontal, Theme.gutter).padding(.top, 12)
                }
                if let problem {
                    ErrorBanner(message: problem, outer: PaperCardMetrics.margin)
                }
                if !rows.isEmpty {
                    scannedSection
                }
            }
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { commitBar }
        .sensoryFeedback(.success, trigger: addedUnits)
        .sensoryFeedback(.selection, trigger: rows.count)
        .onChange(of: catalog.index.count) { _, _ in
            rows = MaterialsMatcher.reclassifyUnresolved(rows, index: catalog.index)
        }
        .photosPicker(isPresented: $showPicker, selection: $photo, matching: .images)
        .fullScreenCover(isPresented: $showCamera) {
            CameraCapture { image in
                showCamera = false
                if let image { Task { await read(image) } }
            }
            .ignoresSafeArea()
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                defer { photo = nil }
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                    problem = "That photo couldn\u{2019}t be opened."
                    return
                }
                await read(image)
            }
        }
        .sheet(item: $reviewing) { line in
            MaterialsChooseSheet(line: line, index: catalog.index,
                                 choose: { item in resolve(line.id, with: item) },
                                 skip: { remove(line.id) })
        }
    }

    // MARK: Capture

    /// Paper 30: a dark 240pt frame, radius 22, blue corner marks and scan line, the hint at its foot.
    private var viewfinder: some View {
        ZStack {
            Color.black
            if liveAvailable {
                LiveMaterialsScanner { code in stage(code) }
                    .accessibilityLabel("Camera. Point it at a barcode or a part number, or tap a part number to look it up.")
            }
            MaterialsViewfinderCorners()
                .stroke(Theme.brand, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .padding(.leading, 48).padding(.trailing, 48).padding(.top, 36).padding(.bottom, 64)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            Capsule().fill(Theme.brand).frame(height: 2).opacity(0.9)
                .padding(.horizontal, 70)
                .offset(y: -14)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .bottom) {
            Text("Point at a barcode or the item itself")
                .font(Theme.font(14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16).padding(.bottom, 18)
                .allowsHitTesting(false)
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityIdentifier("materials-viewfinder")
    }

    /// The phone can take a photo here (a camera, and it isn't turned off for Thorbis).
    private var cameraUsable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera) && !cameraDenied
    }

    /// Paper 30's "No barcode?" card: a photo is read on this phone for a barcode, or for a printed
    /// line that names one price book item. Where there is no live scanner (simulator, older phones,
    /// camera off) a line under the card says so, and a photo can also be chosen from the library.
    private var photoFallback: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if cameraUsable { showCamera = true } else { showPicker = true }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "camera").font(.system(size: 18)).foregroundStyle(Theme.subtle)
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("No barcode?").font(Theme.font(16, weight: .medium)).tracking(-0.16)
                            .foregroundStyle(Theme.foreground)
                        Text("Thorbis reads the label from a photo")
                            .font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if reading {
                        ProgressView()
                    } else {
                        Text(cameraUsable ? "Photograph" : "Choose photo")
                            .font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.brandText)
                    }
                }
                .multilineTextAlignment(.leading)
                .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 11)
                .frame(minHeight: 64)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .disabled(reading)
            .accessibilityIdentifier("materials-take-photo")
            if !liveAvailable {
                Text(cameraDenied
                     ? "Live scanning needs the camera. You can still read a barcode from a photo."
                     : "Live scanning isn\u{2019}t available on this device. Thorbis reads the barcode from a photo instead, on this phone.")
                    .font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                if cameraUsable {
                    Button { showPicker = true } label: {
                        MaterialsCapsuleLabel(title: "Choose photo", symbol: "photo.on.rectangle")
                    }
                    .buttonStyle(PressStyle())
                    .disabled(reading)
                }
            }
        }
        .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 12)
        .accessibilityIdentifier("materials-photo-fallback")
    }

    /// The keyboard button's field: type the code printed under the barcode, or a part number.
    private var codeField: some View {
        HStack(spacing: 8) {
            Image(systemName: "number").foregroundStyle(Theme.muted).accessibilityHidden(true)
            TextField("Part number or barcode", text: $typedCode, prompt: .placeholder("Part number or barcode"))
                .font(Theme.font(17))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($codeFocused)
                .onSubmit { stageTyped() }
                .accessibilityLabel("Part number or barcode")
                .accessibilityIdentifier("materials-code-field")
            if !typedCode.trimmingCharacters(in: .whitespaces).isEmpty {
                Button { stageTyped() } label: {
                    Text("Look up").font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.brandText)
                        .frame(minHeight: 44).padding(.horizontal, 4).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(.leading, 14).padding(.trailing, 10)
        .frame(minHeight: 48)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 12)
    }

    private var scannedSection: some View {
        let list = rows
        let missing = list.contains { $0.status == .notFound && !$0.isResolved }
        return VStack(alignment: .leading, spacing: 8) {
            PaperSection("Scanned just now", count: list.count) {
                ForEach(list) { row in
                    if row.id != list.first?.id { WellDivider(leading: 48) }
                    if let item = row.item {
                        MaterialAddedRow(item: item, quantity: row.quantity,
                                         decrease: { change(row.id, by: -1) },
                                         increase: { change(row.id, by: 1) })
                    } else {
                        MaterialReviewRow(line: row) { reviewing = row }
                    }
                }
            }
            if missing {
                Text("Price book items don\u{2019}t store barcodes, so a code only matches when it\u{2019}s in the item\u{2019}s name.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 22)
        .accessibilityIdentifier("materials-scanned")
    }

    private var commitBar: some View {
        PaperActionBar(title: MaterialsCart.commitTitle(rows),
                       disabled: unresolvedCount > 0 || !canAdd,
                       identifier: "materials-scan-commit",
                       action: commit) {
            MaterialsKeyboardButton(label: typing ? "Hide part number field" : "Type a part number") {
                typing = !typing
                codeFocused = typing
            }
        }
    }

    // MARK: Actions

    /// Stages a scanned or typed code once; scanning the same code again doesn't add another.
    private func stage(_ raw: String) {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, code.count <= 80 else { return }
        guard !rows.contains(where: { $0.source.caseInsensitiveCompare(code) == .orderedSame }) else { return }
        let match = MaterialsMatcher.classify(code, index: catalog.index)
        rows.insert(StagedMaterial(source: code, quantity: 1, match: match), at: 0)
        problem = nil
    }

    private func stageTyped() {
        stage(typedCode)
        typedCode = ""
    }

    private func read(_ image: UIImage) async {
        reading = true
        defer { reading = false }
        let found = await DataPlateOCR.read(image)
        if !found.barcodes.isEmpty {
            for code in found.barcodes { stage(code) }
            return
        }
        // No barcode: a printed line is staged only when it names exactly one price book item.
        var staged = 0
        for line in found.lines {
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 3, text.count <= 80 else { continue }
            guard MaterialsMatcher.classify(text, index: catalog.index).status == .matched else { continue }
            stage(text)
            staged += 1
            if staged == 5 { break }
        }
        if staged == 0 {
            problem = "Nothing in that photo matched the price book. Get closer to the barcode or label, or type the part number."
        }
    }

    private func change(_ id: UUID, by step: Int) {
        guard let position = rows.firstIndex(where: { $0.id == id }) else { return }
        let next = rows[position].quantity + step
        if next < 1 {
            rows.remove(at: position)
        } else {
            rows[position].quantity = min(MaterialsListParser.maximumQuantity, next)
        }
    }

    private func resolve(_ id: UUID, with item: PriceBookListItem) {
        guard let position = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[position].item = item
    }

    private func remove(_ id: UUID) {
        rows.removeAll { $0.id == id }
    }

    private func commit() {
        guard canAdd else { return }
        guard !rows.isEmpty else {
            problem = "Scan a barcode or type a part number first."
            return
        }
        let result = MaterialsCart.commit(rows, add: add)
        rows = result.remaining
        addedUnits += result.unitsAdded
        if let refusal = result.refusal {
            problem = refusal
            return
        }
        problem = nil
        finish()
    }
}

/// A quiet capsule action on the field fill, for the photo fallback's two choices.
private struct MaterialsCapsuleLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium)).accessibilityHidden(true)
            Text(title).font(Theme.font(15, weight: .medium))
        }
        .foregroundStyle(Theme.foreground)
        .padding(.horizontal, 14).frame(minHeight: 44)
        .background(Theme.fill, in: Capsule())
    }
}

/// Paper 30's four corner marks: 34pt arms with a 10pt round corner.
struct MaterialsViewfinderCorners: Shape {
    var arm: CGFloat = 34
    var radius: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Top left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + arm))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))
        // Top right
        path.move(to: CGPoint(x: rect.maxX - arm, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm))
        // Bottom right
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))
        // Bottom left
        path.move(to: CGPoint(x: rect.minX + arm, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - arm))
        return path
    }
}

/// VisionKit's live scanner. A barcode is reported once when it is first recognised; text is only
/// reported when tapped, so a frame full of words doesn't stage noise.
private struct LiveMaterialsScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(), .text()], qualityLevel: .balanced,
                                                recognizesMultipleItems: true, isHighFrameRateTrackingEnabled: false,
                                                isPinchToZoomEnabled: true, isGuidanceEnabled: false, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                switch item {
                case .barcode(let code):
                    if let payload = code.payloadStringValue { onCode(payload) }
                case .text:
                    break
                @unknown default:
                    break
                }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            switch item {
            case .barcode(let code):
                if let payload = code.payloadStringValue { onCode(payload) }
            case .text(let text):
                if let line = text.transcript.split(whereSeparator: { $0.isNewline }).first {
                    onCode(String(line))
                }
            @unknown default:
                break
            }
        }
    }
}
