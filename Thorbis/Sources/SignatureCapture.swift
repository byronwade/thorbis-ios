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
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []
    @State private var busy = false
    @State private var error: String?
    /// Kept across retries so a second tap reuses the same uploaded image.
    @State private var uploaded: (key: String, mediaID: String)?
    @State private var clientAssetID = UUID().uuidString

    private var hasInk: Bool { strokes.contains { $0.count > 1 } }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSubmit: Bool { hasInk && !trimmedName.isEmpty && trimmedName.count <= 120 && !busy }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(summary)
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Customer's full name", text: $name)
                    .textContentType(.name)
                    .font(Theme.font(17))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10))
                ZStack(alignment: .bottomLeading) {
                    pad
                    HStack {
                        Text("Sign here").font(Theme.font(12)).foregroundStyle(.black.opacity(0.35))
                        Spacer()
                        if hasInk {
                            Button("Clear") { strokes = []; uploaded = nil; clientAssetID = UUID().uuidString }
                                .font(Theme.font(13, weight: .medium))
                                .frame(minWidth: 44, minHeight: 44)
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                .accessibilityLabel("Signature pad")
                if let error { Text(error).font(Theme.font(13)).foregroundStyle(Theme.destructive) }
                Spacer(minLength: 0)
                PrimaryButton(title: title, busy: busy) { Task { await sign() } }
                    .disabled(!canSubmit)
            }
            .padding(20)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Customer signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() }.disabled(busy) }
            }
            .onAppear { if name.isEmpty { name = suggestedName } }
        }
        .interactiveDismissDisabled(busy)
    }

    private var pad: some View {
        Canvas { context, _ in
            for stroke in strokes + [current] where stroke.count > 1 {
                var path = Path()
                path.addLines(stroke)
                context.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
            }
        }
        .background(Color.white)
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { current.append($0.location) }
            .onEnded { _ in
                strokes.append(current)
                current = []
                uploaded = nil
                clientAssetID = UUID().uuidString
            })
    }

    @MainActor private func png(size: CGSize) -> Data? {
        let drawing = Canvas { context, _ in
            for stroke in strokes where stroke.count > 1 {
                var path = Path()
                path.addLines(stroke)
                context.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Color.white)
        let renderer = ImageRenderer(content: drawing)
        renderer.scale = 2
        return renderer.uiImage?.pngData()
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
                let maxX = strokes.flatMap { $0 }.map(\.x).max() ?? 320
                let maxY = strokes.flatMap { $0 }.map(\.y).max() ?? 200
                guard let data = png(size: CGSize(width: max(maxX + 16, 200), height: max(maxY + 16, 120))) else {
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

/// "Signed by Dana Customer · Oct 27, 3:00 PM" under an approved estimate or authorized invoice.
struct SignatureBadge: View {
    let label: String
    let signature: FieldSignatureRecord
    var body: some View {
        Label {
            Text("\(label) \(signature.signerName)\(JobFiltering.date(signature.signedAt).map { " · " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "")")
        } icon: {
            Image(systemName: "signature")
        }
        .font(Theme.font(13, weight: .medium))
        .foregroundStyle(Theme.success)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }
}
