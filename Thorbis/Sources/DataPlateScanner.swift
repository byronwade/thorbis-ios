import SwiftUI
import PhotosUI
import VisionKit
import Vision
import AVFoundation

// Data-plate / serial scan: the technician points the phone at the equipment tag, picks the model,
// serial and date it read, and the result goes on the job as a note (offline-safe) and, for roles
// that edit equipment, into the equipment form. Live scanning uses VisionKit's DataScanner; where
// it isn't available (simulator, older phones, camera denied) a photo is read with Vision instead.

/// What a tag said, as candidates in reading order. Nothing is guessed: a date is only offered when
/// the tag prints one beside a date label (serial-number date codes differ by brand).
struct DataPlateReading: Equatable {
    var brands: [String] = []
    var models: [String] = []
    var serials: [String] = []
    var dates: [String] = []

    var isEmpty: Bool { brands.isEmpty && models.isEmpty && serials.isEmpty && dates.isEmpty }
}

enum DataPlateParser {
    /// Common HVAC, water-heater, plumbing and electrical makers. Edit freely; matching is whole-word.
    static let brands = [
        "American Standard", "A.O. Smith", "AO Smith", "Amana", "Armstrong", "Bosch", "Bradford White", "Bryant", "Burnham",
        "Carrier", "Coleman", "Comfortmaker", "Daikin", "Ducane", "Eaton", "Friedrich", "Fujitsu", "Generac", "Gibson",
        "Goodman", "Heil", "Honeywell", "Kohler", "Lennox", "LG", "Mitsubishi", "Navien", "Noritz", "Nordyne", "Payne",
        "Rheem", "Rinnai", "Ruud", "Siemens", "Square D", "Tempstar", "Trane", "Weil-McLain", "York",
    ]

    private static let modelLabel = #"(?:\bMODEL(?:\s*(?:NO|NUMBER|NUM|#))?\.?|\bM\s*/\s*N\b|\bMOD\.|\bMDL\b)"#
    private static let serialLabel = #"(?:\bSERIAL(?:\s*(?:NO|NUMBER|NUM|#))?\.?|\bS\s*/\s*N\b|\bSER\.?\s*NO\.?)"#
    private static let dateLabel = #"(?:\bMFG\.?\s*DATE|\bDATE\s*(?:OF\s*)?(?:MFG|MANUFACTURE|MFD)\.?|\bMFR\.?\s*DATE|\bMANUFACTURED(?:\s*ON)?|\bMFD\.?|\bDATE\s*CODE|\bMFG\.?)"#
    /// A model or serial value: starts and ends alphanumeric, may carry - / . inside.
    private static let token = #"^[\s:#.\-]*([A-Z0-9][A-Z0-9\-/.]*[A-Z0-9])"#
    private static let date = #"\b(\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}|\d{1,2}[/\-.]\d{4}|\d{4}[/\-.]\d{1,2}(?:[/\-.]\d{1,2})?|(?:JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)[A-Z]*\.?\s*\d{4}|(?:19[7-9]\d|20\d\d))\b"#

    static func parse(lines raw: [String], barcodes: [String] = []) -> DataPlateReading {
        let lines = raw.map { $0.uppercased().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var reading = DataPlateReading()
        for (index, line) in lines.enumerated() {
            let next = lines.indices.contains(index + 1) ? lines[index + 1] : nil
            reading.models += values(after: modelLabel, in: line, next: next)
            reading.serials += values(after: serialLabel, in: line, next: next)
            reading.dates += dates(after: dateLabel, in: line, next: next)
            for brand in brands where line.range(of: #"(?<![A-Z0-9])"# + NSRegularExpression.escapedPattern(for: brand.uppercased()) + #"(?![A-Z0-9])"#,
                                                  options: .regularExpression) != nil {
                reading.brands.append(brand == "AO Smith" ? "A.O. Smith" : brand)
            }
        }
        for code in barcodes {
            let payload = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard (6...30).contains(payload.count), payload.range(of: #"^[A-Z0-9\-]+$"#, options: .regularExpression) != nil,
                  payload.contains(where: \.isNumber), !reading.models.contains(payload) else { continue }
            reading.serials.append(payload)
        }
        reading.brands = unique(reading.brands)
        reading.models = unique(reading.models)
        reading.serials = unique(reading.serials).filter { !reading.models.contains($0) }
        reading.dates = unique(reading.dates)
        return reading
    }

    /// One line of the job note, e.g. "Data plate: Carrier 24ACC636A003, S/N 1234E56789, made 03/2019".
    static func note(brand: String, model: String, serial: String, made: String) -> String? {
        let clean = { (value: String) in value.trimmingCharacters(in: .whitespacesAndNewlines) }
        var parts: [String] = []
        let unit = [clean(brand), clean(model)].filter { !$0.isEmpty }.joined(separator: " ")
        if !unit.isEmpty { parts.append(unit) }
        if !clean(serial).isEmpty { parts.append("S/N \(clean(serial))") }
        if !clean(made).isEmpty { parts.append("made \(clean(made))") }
        return parts.isEmpty ? nil : "Data plate: " + parts.joined(separator: ", ")
    }

    private static func values(after label: String, in line: String, next: String?) -> [String] {
        var found: [String] = []
        for remainder in remainders(after: label, in: line) {
            if let value = firstToken(remainder) { found.append(value) }
            else if let next, let value = firstToken(next) { found.append(value) }
        }
        return found
    }

    private static func dates(after label: String, in line: String, next: String?) -> [String] {
        var found: [String] = []
        for remainder in remainders(after: label, in: line) {
            if let value = firstDate(remainder) ?? next.flatMap(firstDate) { found.append(value) }
        }
        return found
    }

    /// The text after each occurrence of the label, up to the next label of any kind.
    private static func remainders(after label: String, in line: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: label) else { return [] }
        let text = line as NSString
        return expression.matches(in: line, range: NSRange(location: 0, length: text.length)).map { match in
            var rest = text.substring(from: match.range.location + match.range.length)
            for other in [modelLabel, serialLabel, dateLabel] {
                if let cut = rest.range(of: other, options: .regularExpression), cut.lowerBound > rest.startIndex {
                    rest = String(rest[..<cut.lowerBound])
                }
            }
            return rest
        }
    }

    private static func firstToken(_ text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: token),
              let match = expression.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) else { return nil }
        let value = (text as NSString).substring(with: match.range(at: 1))
        // A label word read as a value ("NO", "NUMBER") or something too short to be a part number.
        guard (4...30).contains(value.count), value.contains(where: \.isNumber) else { return nil }
        return value
    }

    private static func firstDate(_ text: String) -> String? {
        guard let range = text.range(of: date, options: .regularExpression) else { return nil }
        return String(text[range])
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

/// Reads a still photo of a tag with Vision: text lines (row by row, left to right) and any barcodes.
enum DataPlateOCR {
    struct Result: Sendable { let lines: [String]; let barcodes: [String] }

    static func read(_ image: UIImage) async -> Result {
        guard let cgImage = image.cgImage else { return Result(lines: [], barcodes: []) }
        let orientation = CGImagePropertyOrientation(dataPlate: image.imageOrientation)
        return await Task.detached(priority: .userInitiated) { recognize(cgImage, orientation: orientation) }.value
    }

    private nonisolated static func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation) -> Result {
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        // Serial numbers aren't words; correction "fixes" them.
        text.usesLanguageCorrection = false
        let codes = VNDetectBarcodesRequest()
        try? VNImageRequestHandler(cgImage: image, orientation: orientation).perform([text, codes])
        let observed = (text.results ?? []).compactMap { observation -> (box: CGRect, string: String)? in
            observation.topCandidates(1).first.map { (observation.boundingBox, $0.string) }
        }
        // Vision's origin is bottom-left: group pieces whose centres share a row, top row first.
        var rows: [(midY: CGFloat, height: CGFloat, pieces: [(x: CGFloat, string: String)])] = []
        for piece in observed.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let last = rows.indices.last, abs(rows[last].midY - piece.box.midY) < max(rows[last].height, piece.box.height) * 0.5 {
                rows[last].pieces.append((piece.box.minX, piece.string))
            } else {
                rows.append((piece.box.midY, piece.box.height, [(piece.box.minX, piece.string)]))
            }
        }
        let lines = rows.map { $0.pieces.sorted { $0.x < $1.x }.map(\.string).joined(separator: " ") }
        let barcodes = (codes.results ?? []).compactMap(\.payloadStringValue)
        return Result(lines: lines, barcodes: barcodes)
    }
}

private extension CGImagePropertyOrientation {
    init(dataPlate orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

// MARK: - Sheet

/// Entry point: present as a sheet from the job (`.sheet { DataPlateScannerSheet(job: job) { … } }`).
/// `onDone` runs when the technician closes it; reload notes then.
struct DataPlateScannerSheet: View {
    let jobID: String
    let customerID: String
    let onDone: () -> Void
    /// DEBUG fixtures: canned OCR lines shown as if a photo had been read.
    var previewLines: [String]? = nil

    init(job: JobRecord, onDone: @escaping () -> Void) {
        self.init(jobID: job.id, customerID: job.customerId, onDone: onDone)
    }

    init(jobID: String, customerID: String, previewLines: [String]? = nil, onDone: @escaping () -> Void) {
        self.jobID = jobID
        self.customerID = customerID
        self.previewLines = previewLines
        self.onDone = onDone
    }

    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var outbox: FieldOutbox

    @State private var seenLines: [String] = []
    @State private var seenBarcodes: [String] = []
    @State private var brand = ""
    @State private var model = ""
    @State private var serial = ""
    @State private var made = ""
    @State private var photo: PhotosPickerItem?
    @State private var showCamera = false
    @State private var reading = false
    @State private var torchOn = false
    @State private var busy = false
    @State private var result: JobNotePostResult?
    @State private var equipment: EquipmentEditorItem?
    @State private var locations: [ServiceLocationRecord] = []
    @State private var problem: String?

    private var parsed: DataPlateReading { DataPlateParser.parse(lines: seenLines, barcodes: seenBarcodes) }
    private var liveAvailable: Bool {
        previewLines == nil && DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }
    private var cameraDenied: Bool { [.denied, .restricted].contains(AVCaptureDevice.authorizationStatus(for: .video)) }
    private var noteText: String? { DataPlateParser.note(brand: brand, model: model, serial: serial, made: made) }
    private var canEditEquipment: Bool { session.can("customer.edit", feature: "core_crm") }
    private var saved: Bool { result?.succeeded == true }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if liveAvailable { liveScanner } else { photoFallback }
                    fields
                    if let problem {
                        FieldProblem(message: problem)
                    }
                    if let result {
                        Label(result.message, systemImage: result.succeeded ? (result == .saved ? "checkmark.circle" : "clock.arrow.circlepath") : "exclamationmark.triangle")
                            .font(Theme.font(14)).foregroundStyle(result.succeeded ? Theme.muted : Theme.destructive)
                            .accessibilityIdentifier("data-plate-result")
                    }
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 8).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.canvas)
            .navigationTitle("Scan data plate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ThorbisToolbarItem(placement: .topBarLeading) {
                    Button(saved ? "Done" : "Close", action: finish).accessibilityIdentifier("data-plate-close")
                }
            }
            .safeAreaInset(edge: .bottom) { commitBar }
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
                        problem = "That photo couldn’t be opened."
                        return
                    }
                    await read(image)
                }
            }
            .onChange(of: brand) { _, _ in problem = nil }
            .onChange(of: model) { _, _ in problem = nil }
            .onChange(of: serial) { _, _ in problem = nil }
            .onChange(of: made) { _, _ in problem = nil }
            .sheet(item: $equipment) { item in SheetSurface {
                EquipmentEditor(customerID: customerID, locations: locations, existing: nil, prefill: equipmentPrefill) {}
            } }
            .onAppear {
                if let previewLines, seenLines.isEmpty { absorb(lines: previewLines, barcodes: []) }
            }
            .onDisappear { setTorch(false) }
        }
    }

    // MARK: Capture

    private var liveScanner: some View {
        ZStack(alignment: .topTrailing) {
            LiveDataPlateScanner { lines, barcodes in absorb(lines: lines, barcodes: barcodes) }
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: PaperCardMetrics.radius, style: .continuous))
                .accessibilityLabel("Camera. Point it at the equipment tag.")
            if AVCaptureDevice.default(for: .video)?.hasTorch == true {
                PaperCircleButton(symbol: torchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                                  label: torchOn ? "Turn light off" : "Turn light on", fill: Theme.card) { setTorch(!torchOn) }
                    .padding(6)
            }
        }
        .overlay(alignment: .bottomLeading) {
            Text("Hold steady on the tag. Tap what it found below.")
                .font(Theme.font(13, weight: .medium)).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(10)
        }
    }

    @ViewBuilder private var photoFallback: some View {
        PaperCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Take a photo of the tag").font(Theme.font(16, weight: .medium))
                Text(cameraDenied
                     ? "Live scanning needs the camera. Allow it in Settings › Thorbis, or read a photo of the tag instead."
                     : "Live scanning isn’t available on this device. Thorbis reads the model and serial from a photo instead, on this phone.")
                    .font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) && !cameraDenied {
                        Button { showCamera = true } label: { QuietCapsuleLabel(title: "Take photo", symbol: "camera") }
                            .buttonStyle(PressStyle())
                    }
                    PhotosPicker(selection: $photo, matching: .images) { QuietCapsuleLabel(title: "Choose photo", symbol: "photo.on.rectangle") }
                        .buttonStyle(PressStyle())
                    if reading { ProgressView().padding(.leading, 4) }
                }
                .disabled(reading)
            }
        }
        .accessibilityIdentifier("data-plate-fallback")
        if cameraDenied {
            PermissionNotice(permission: .camera, purpose: "scan data plates live", outer: 0)
        }
    }

    // MARK: Fields

    private var fields: some View {
        let found = parsed
        return VStack(alignment: .leading, spacing: 6) {
            PaperGroupHeader(title: found.isEmpty ? "What the tag says" : "Tap what matches the tag")
                .padding(.horizontal, 4)
            PaperCard {
                field("Brand", text: $brand, candidates: found.brands, capitalization: .words)
                field("Model", text: $model, candidates: found.models)
                field("Serial", text: $serial, candidates: found.serials)
                field("Made", text: $made, candidates: found.dates, placeholder: "Only if the tag prints it")
            }
            Text("Read on this phone. Check each value against the tag before saving.")
                .font(Theme.font(12)).foregroundStyle(Theme.muted).padding(.horizontal, 4).padding(.top, 2)
        }
    }

    private func field(_ title: String, text: Binding<String>, candidates: [String],
                       capitalization: TextInputAutocapitalization = .characters, placeholder: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(title).font(Theme.font(14)).foregroundStyle(Theme.muted).frame(width: 56, alignment: .leading)
                TextField(placeholder ?? title, text: text, prompt: .placeholder(placeholder ?? title))
                    .font(Theme.font(16, weight: .medium)).monospacedDigit()
                    .textInputAutocapitalization(capitalization).autocorrectionDisabled()
                    .accessibilityLabel(title)
                    .accessibilityIdentifier("data-plate-\(title.lowercased())")
            }
            .frame(minHeight: 44)
            if !candidates.isEmpty {
                FlowRow(spacing: 8, lineSpacing: 8) {
                    ForEach(candidates.prefix(6), id: \.self) { value in
                        ThorbisChipToggle(label: value, isOn: text.wrappedValue == value) {
                            text.wrappedValue = text.wrappedValue == value ? "" : value
                            result = nil
                        }
                    }
                }
            }
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 6)
    }

    private var commitBar: some View {
        // Not pre-disabled when nothing has been read yet: pressing says what to do, under the
        // fields. Without the note permission it stays off, and the sentence under it says why.
        PaperActionBar(title: saved ? "Done" : "Add to job notes", symbol: saved ? nil : "text.bubble",
                       busy: busy, disabled: !saved && !JobNotePoster.canPost(session),
                       disabledReason: "Your role can't add job notes. Ask your office.") {
            if saved { finish() }
            else if noteText == nil { problem = "Scan the tag, or type the brand, model or serial, to add a note." }
            else { Task { await saveNote() } }
        } secondary: {
            if canEditEquipment {
                PaperSquareButton(symbol: "wrench.and.screwdriver", label: "Add as equipment") { Task { await openEquipment() } }
                    .disabled(model.isEmpty && serial.isEmpty && brand.isEmpty)
            }
        }
    }

    // MARK: Actions

    private var equipmentPrefill: EquipmentInput {
        let clean = { (value: String) -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let name = [clean(brand), clean(model)].compactMap { $0 }.joined(separator: " ")
        return EquipmentInput(name: name.isEmpty ? "Equipment" : name, brand: clean(brand), model: clean(model),
                              serialNumber: clean(serial), notes: clean(made).map { "Made \($0) (from the data plate)" })
    }

    private func absorb(lines: [String], barcodes: [String]) {
        for line in lines where !seenLines.contains(line) { seenLines.append(line) }
        for code in barcodes where !seenBarcodes.contains(code) { seenBarcodes.append(code) }
        if seenLines.count > 120 { seenLines.removeFirst(seenLines.count - 120) }
        // Fill empty fields with the first candidate; the technician can tap another or type.
        let found = parsed
        if brand.isEmpty, let first = found.brands.first { brand = first }
        if model.isEmpty, let first = found.models.first { model = first }
        if serial.isEmpty, let first = found.serials.first { serial = first }
        if made.isEmpty, let first = found.dates.first { made = first }
    }

    private func read(_ image: UIImage) async {
        reading = true
        defer { reading = false }
        let found = await DataPlateOCR.read(image)
        problem = found.lines.isEmpty && found.barcodes.isEmpty ? "No text was found. Get closer, fill the frame with the tag and try again." : nil
        absorb(lines: found.lines, barcodes: found.barcodes)
    }

    private func saveNote() async {
        guard let noteText else { return }
        busy = true
        defer { busy = false }
        result = await JobNotePoster.post(noteText, jobID: jobID, api: api, session: session, outbox: outbox)
        if result?.succeeded == true { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    private func openEquipment() async {
        if locations.isEmpty, !session.isOffline {
            locations = (try? await api.fieldLocations(customerID))?.filter { $0.customerId == customerID } ?? []
        }
        equipment = EquipmentEditorItem(record: nil)
    }

    private func finish() {
        setTorch(false)
        onDone()
    }

    private func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            torchOn = on
        } catch { torchOn = false }
    }
}

/// A quiet capsule action (field fill), for the photo fallback's two choices.
private struct QuietCapsuleLabel: View {
    let title: String
    let symbol: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium))
            Text(title).font(Theme.font(15, weight: .medium))
        }
        .foregroundStyle(Theme.foreground)
        .padding(.horizontal, 14).frame(minHeight: 44)
        .background(Theme.fill, in: Capsule())
    }
}

/// VisionKit's live scanner for text and barcodes. Reports every line and code it has recognised.
private struct LiveDataPlateScanner: UIViewControllerRepresentable {
    let onRecognized: ([String], [String]) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.text(), .barcode()], qualityLevel: .accurate,
                                                recognizesMultipleItems: true, isHighFrameRateTrackingEnabled: false,
                                                isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onRecognized = onRecognized
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onRecognized: onRecognized) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onRecognized: ([String], [String]) -> Void
        init(onRecognized: @escaping ([String], [String]) -> Void) { self.onRecognized = onRecognized }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            report([item])
        }

        private func report(_ items: [RecognizedItem]) {
            var lines: [String] = []
            var codes: [String] = []
            for item in items {
                switch item {
                case .text(let text): lines += text.transcript.split(whereSeparator: \.isNewline).map(String.init)
                case .barcode(let code): if let payload = code.payloadStringValue { codes.append(payload) }
                @unknown default: break
                }
            }
            onRecognized(lines, codes)
        }
    }
}
