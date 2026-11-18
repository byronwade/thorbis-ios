import SwiftUI

/// Sign-on-glass for an estimate approval or invoice authorization. The drawing is uploaded as
/// job media (PNG, tagged "signature") and its id goes with the approval, so the signature is
/// kept with the job and shows on the document.
/// One row of the "Estimate summary" card above the signature (Paper 36): the line's name, a quiet
/// word under it, and its amount as the caller already formats it.
struct SignatureSummaryLine: Identifiable {
    let id: String
    let title: String
    var detail: String? = nil
    let amount: String
}

struct SignatureCaptureSheet: View {
    let title: String
    let summary: String
    let jobID: String
    var suggestedName = ""
    /// Paper 36's 34 Bold heading: "Sign estimate" for an estimate, "Sign invoice" for an invoice.
    var heading = "Sign invoice"
    /// Paper 36 "Estimate summary": the section label, the document's number at its trailing edge,
    /// the lines and the total. The card shows only when the caller passes lines.
    var summaryTitle = "Estimate summary"
    var reference: String? = nil
    var lines: [SignatureSummaryLine] = []
    var totalText: String? = nil
    /// Saves the ink on the phone to send once online (OF-01); nil where signing needs signal.
    var queueOffline: (@MainActor (_ png: Data, _ clientAssetID: String, _ signerName: String, _ signedAt: String) -> Bool)? = nil
    /// Runs the approval or authorization with the uploaded signature; returns an error message on failure.
    let submit: (FieldSignatureInput) async -> String?
    /// What `submit` returns when the request failed for lack of signal, so the sheet can still
    /// save the ink for later instead of losing it.
    static let noSignal = "signature.no-signal"
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var strokes: [[CGPoint]] = []
    @State private var busy = false
    @State private var error: String?
    /// Kept across retries so a second tap reuses the same uploaded image.
    @State private var uploaded: (key: String, mediaID: String)?
    @State private var clientAssetID = UUID().uuidString
    /// Set when the commit is pressed with the name or signature missing, so it says which.
    @State private var attempted = false
    /// True while a finger is drawing, so the page under the pad holds still.
    @State private var drawing = false
    @FocusState private var nameFocused: Bool

    private var hasInk: Bool { SignatureInk.hasInk(strokes) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var blockedReason: String? {
        // A signature authorizes charges or approves work, so it is never kept to send later:
        // say so before the customer signs, not after.
        if session.isOffline { return "Signing needs a connection. The customer can sign once you have signal." }
        if trimmedName.isEmpty { return "Add the customer's name to continue." }
        if trimmedName.count > 120 { return "Shorten the name to 120 characters." }
        if !hasInk { return "Have the customer sign above the line." }
        return nil
    }
    private var canSubmit: Bool { hasInk && !trimmedName.isEmpty && trimmedName.count <= 120 && !busy && !session.isOffline }

    /// Paper 36: the 34 Bold heading, the summary of what is signed, the signer's name, "Sign to
    /// approve" with Clear, the pad with the signer under its line, then what signing means and
    /// the commit.
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                if lines.isEmpty {
                    form
                    Spacer(minLength: 0)
                } else {
                    // With the summary the page is taller than a small phone, so it scrolls. A
                    // stroke on the pad stops the scroll until the finger lifts, so signing never
                    // drags the page.
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) { form }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .scrollDisabled(drawing)
                    .scrollDismissesKeyboard(.interactively)
                }
                Text(summary)
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.gutter).padding(.vertical, 16)
                // Not pre-disabled for a missing name or signature: pressing says which, under it.
                // Offline it stays off (a signature is never kept to send later), and says why.
                VStack(spacing: 8) {
                    PrimaryButton(title: title, icon: "checkmark", busy: busy) {
                        guard canSubmit else {
                            attempted = true
                            if trimmedName.isEmpty || trimmedName.count > 120 { nameFocused = true }
                            return
                        }
                        Task { await sign() }
                    }
                    .disabled(busy || session.isOffline)
                    if !busy, session.isOffline || attempted, let reason = blockedReason {
                        Group {
                            if session.isOffline {
                                Text(reason).font(Theme.font(13)).foregroundStyle(Theme.muted)
                            } else {
                                FieldProblem(message: reason)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.canvas)
            .paperPageGround()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ThorbisToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { PaperCircleLabel(symbol: "xmark", size: 44, fill: Theme.card) }
                        .buttonStyle(PressStyle())
                        .disabled(busy)
                        .accessibilityLabel("Cancel")
                }
                // Paper 36: "Sign later" in quiet type opposite the close circle; it leaves the
                // sheet without signing, the same as Cancel.
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Text("Sign later").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.muted)
                            .padding(.horizontal, 4)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .disabled(busy)
                }
            }
            .onAppear { if name.isEmpty { name = suggestedName } }
        }
        .interactiveDismissDisabled(busy)
    }

    /// Everything above the consent sentence: heading, summary, name, and the pad.
    @ViewBuilder private var form: some View {
        PaperPageTitle(title: heading)
        if !lines.isEmpty { summaryCard }
        VStack(alignment: .leading, spacing: 8) {
            Text("Customer's name").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                .padding(.horizontal, 4)
                .accessibilityHidden(true)
            TextField("Customer's full name", text: $name, prompt: .placeholder("Customer's full name"))
                .focused($nameFocused)
                .textContentType(.name)
                .submitLabel(.done)
                .font(Theme.font(17))
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 22)
        HStack(alignment: .center) {
            Text("Sign to approve").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if hasInk {
                Button("Clear") { strokes = []; uploaded = nil; clientAssetID = UUID().uuidString }
                    .font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.brandText)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Clear signature")
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, Theme.gutter).padding(.top, 14)
        ZStack(alignment: .bottom) {
            pad
            // Paper 36: a hairline to sign on, with who signs centred under it.
            VStack(spacing: 10) {
                Rectangle().fill(Theme.hairline).frame(height: 1)
                Text(trimmedName.isEmpty ? "Customer" : "\(trimmedName) \u{00B7} Customer")
                    .font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 24).padding(.bottom, 20)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityLabel("Signature pad")
        .padding(.horizontal, PaperCardMetrics.margin)
        if let error {
            ListErrorRow(message: error).padding(.horizontal, PaperCardMetrics.margin).padding(.top, 12)
        }
    }

    /// Paper 36 "Estimate summary": 64pt rows (16 Medium name, 14 muted word, 16 Medium amount) with
    /// hairlines between, then Total in 16 Semibold against the amount in 28 Bold.
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(summaryTitle).font(Theme.font(13, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let reference { Text(reference).font(Theme.monoFont(13)) }
            }
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                    if index > 0 { WellDivider(leading: 0) }
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(line.title).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                                .fixedSize(horizontal: false, vertical: true)
                            if let detail = line.detail, !detail.isEmpty {
                                Text(detail).font(Theme.font(14)).foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(line.amount).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                            .fixedSize()
                    }
                    .padding(.vertical, 10)
                    .frame(minHeight: 64)
                    .accessibilityElement(children: .combine)
                }
                if let totalText {
                    WellDivider(leading: 0)
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Total").font(Theme.font(16, weight: .semibold))
                        Spacer(minLength: 8)
                        Text(totalText).font(Theme.heading()).tracking(-0.56)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(Theme.foreground)
                    .padding(.top, 14).padding(.bottom, 16)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, PaperCardMetrics.inset)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 22)
    }

    private var pad: some View {
        // Paper 36: brand ink on the card. The saved image stays black on white (SignatureInk.png).
        SignaturePad(strokes: $strokes, ink: Theme.brand, surface: Theme.card,
                     onStroke: {
                         uploaded = nil
                         clientAssetID = UUID().uuidString
                     },
                     onDrawing: { active in drawing = active })
    }

    /// OF-01: without signal the ink is saved on the phone and sent once online, when the caller
    /// allows it. Returns true when it was saved.
    private func saveForLater(key: String) -> Bool {
        guard let queueOffline, let png = SignatureInk.png(strokes) else { return false }
        return queueOffline(png, key, trimmedName, ISO8601DateFormatter().string(from: Date()))
    }

    private func sign() async {
        busy = true
        defer { busy = false }
        error = nil
        // An image already uploaded for this ink is reused by its client asset id once online.
        if session.isOffline, saveForLater(key: clientAssetID) {
            dismiss()
            return
        }
        do {
            let key = clientAssetID
            let mediaID: String
            if let uploaded, uploaded.key == key {
                mediaID = uploaded.mediaID
            } else {
                guard let data = SignatureInk.png(strokes) else {
                    error = "The signature could not be saved. Try again."
                    return
                }
                let asset = try await MediaTransfer(api: api).upload(jobID: jobID, clientAssetID: key, kind: "photo", mime: "image/png",
                                                                     originalFilename: "signature.png", data: data, tags: ["signature"])
                mediaID = asset.id
                uploaded = (key, mediaID)
            }
            let input = FieldSignatureInput(signerName: trimmedName,
                                            signedAt: ISO8601DateFormatter().string(from: Date()), imageMediaId: mediaID)
            switch await submit(input) {
            case nil: dismiss()
            case Self.noSignal?:
                if saveForLater(key: key) { dismiss() } else { error = "Signing needs a connection. Try again when you have signal." }
            case let message?: error = message
            }
        } catch is CancellationError {
        } catch {
            if error.isConnectivityFailure, saveForLater(key: clientAssetID) {
                dismiss()
                return
            }
            self.error = error.isConnectivityFailure ? "Signing needs a connection. Try again when you have signal." : error.localizedDescription
        }
    }
}

/// The drawing surface for a finger signature. Paper draws it in brand ink on the card, so callers
/// pass `ink` and `surface`; the saved image is always black on white (`SignatureInk.png`).
/// `onStroke` runs after each finished stroke so a caller can drop an upload made for older ink.
/// `onDrawing` says when a finger goes down on the pad and when it lifts (or the touch is taken
/// away), so a pad inside a scroll view can hold the page still while someone signs.
struct SignaturePad: View {
    @Binding var strokes: [[CGPoint]]
    var ink: Color = .black
    var surface: Color = .white
    var onStroke: () -> Void = {}
    var onDrawing: (Bool) -> Void = { _ in }
    @State private var current: [CGPoint] = []
    /// Resets by itself when the touch ends or is cancelled.
    @GestureState private var touching = false

    var body: some View {
        Canvas { context, _ in
            for stroke in strokes + [current] where stroke.count > 1 {
                context.stroke(SignatureInk.path(stroke), with: .color(ink), style: SignatureInk.style)
            }
        }
        .background(surface)
        .gesture(DragGesture(minimumDistance: 0)
            .updating($touching) { _, state, _ in state = true }
            .onChanged { current.append($0.location) }
            .onEnded { _ in
                strokes.append(current)
                current = []
                onStroke()
            })
        .onChange(of: touching) { _, active in
            onDrawing(active)
            // A touch the system took away never reaches onEnded: keep what was drawn.
            if !active, current.count > 1 {
                strokes.append(current)
                current = []
                onStroke()
            }
        }
        .onDisappear { onDrawing(false) }
    }
}

enum SignatureInk {
    static let style = StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)

    static func path(_ stroke: [CGPoint]) -> Path {
        var path = Path()
        path.addLines(stroke)
        return path
    }

    static func hasInk(_ strokes: [[CGPoint]]) -> Bool { strokes.contains { $0.count > 1 } }

    /// The drawing as a PNG, cropped to the ink's extent plus a margin.
    @MainActor static func png(_ strokes: [[CGPoint]]) -> Data? {
        let maxX = strokes.flatMap { $0 }.map(\.x).max() ?? 320
        let maxY = strokes.flatMap { $0 }.map(\.y).max() ?? 200
        let size = CGSize(width: max(maxX + 16, 200), height: max(maxY + 16, 120))
        let drawing = Canvas { context, _ in
            for stroke in strokes where stroke.count > 1 {
                context.stroke(path(stroke), with: .color(.black), style: style)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Color.white)
        let renderer = ImageRenderer(content: drawing)
        renderer.scale = 2
        return renderer.uiImage?.pngData()
    }
}

/// "Signed by Dana Customer · Oct 27, 3:00 PM" under an approved estimate or authorized invoice.
struct SignatureBadge: View {
    let label: String
    let signature: FieldSignatureRecord
    var body: some View {
        Label {
            Text("\(label) \(signature.signerName)\(JobFiltering.date(signature.signedAt).map { " · " + $0.stampLabel() } ?? "")")
        } icon: {
            Image(systemName: "signature")
        }
        .font(Theme.font(13, weight: .medium))
        .foregroundStyle(Theme.success)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelBackground(cornerRadius: Theme.cardRadius)
    }
}
