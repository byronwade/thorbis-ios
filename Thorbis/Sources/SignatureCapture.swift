import SwiftUI

/// Sign-on-glass for an estimate approval or invoice authorization. The drawing is uploaded as
/// job media (PNG, tagged "signature") and its id goes with the approval, so the signature is
/// kept with the job and shows on the document.
struct SignatureCaptureSheet: View {
    let title: String
    let summary: String
    let jobID: String
    var suggestedName = ""
    /// Runs the approval or authorization with the uploaded signature; returns an error message on failure.
    let submit: (FieldSignatureInput) async -> String?
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

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(summary)
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Customer's full name", text: $name)
                    .textContentType(.name)
                    .submitLabel(.done)
                    .font(Theme.font(17))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                ZStack(alignment: .bottomLeading) {
                    pad
                    // A signature line, like the paper form the customer expects.
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("×").font(Theme.font(20)).foregroundStyle(.black.opacity(0.62))
                        Rectangle().fill(.black.opacity(0.2)).frame(height: 1)
                    }
                    .padding(.horizontal, 18).padding(.bottom, 52)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    HStack {
                        Text("Sign above the line").font(Theme.font(13)).foregroundStyle(.black.opacity(0.62))
                        Spacer()
                        if hasInk {
                            Button("Clear") { strokes = []; uploaded = nil; clientAssetID = UUID().uuidString }
                                .font(Theme.font(13, weight: .medium))
                                .frame(minWidth: 44, minHeight: 44)
                        }
                    }
                    .padding(.horizontal, 14).padding(.bottom, 6)
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border))
                .accessibilityLabel("Signature pad")
                if let error { ListErrorRow(message: error) }
                Spacer(minLength: 0)
                PrimaryButton(title: title, busy: busy) { Task { await sign() } }
                    .disabled(!canSubmit)
                // MA-08: a disabled commit says why, in words under it.
                if !canSubmit && !busy, let reason = blockedReason {
                    Text(reason).font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Customer signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ThorbisToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() }.disabled(busy) }
            }
            .onAppear { if name.isEmpty { name = suggestedName } }
        }
        .interactiveDismissDisabled(busy)
    }

    private var pad: some View {
        SignaturePad(strokes: $strokes) {
            uploaded = nil
            clientAssetID = UUID().uuidString
        }
    }

    private func sign() async {
        busy = true
        defer { busy = false }
        error = nil
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
            if let message = await submit(input) { error = message } else { dismiss() }
        } catch is CancellationError {
        } catch {
            self.error = error.isConnectivityFailure ? "Signing needs a connection. Try again when you have signal." : error.localizedDescription
        }
    }
}

/// The drawing surface for a finger signature: black ink on white in light and dark mode.
/// `onStroke` runs after each finished stroke so a caller can drop an upload made for older ink.
struct SignaturePad: View {
    @Binding var strokes: [[CGPoint]]
    var onStroke: () -> Void = {}
    @State private var current: [CGPoint] = []

    var body: some View {
        Canvas { context, _ in
            for stroke in strokes + [current] where stroke.count > 1 {
                context.stroke(SignatureInk.path(stroke), with: .color(.black), style: SignatureInk.style)
            }
        }
        .background(Color.white)
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { current.append($0.location) }
            .onEnded { _ in
                strokes.append(current)
                current = []
                onStroke()
            })
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
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}
