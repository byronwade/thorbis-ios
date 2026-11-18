import PhotosUI
import SwiftUI

// The company logo (web onboarding's logo step): `POST /v1/organization/logo` takes the image
// itself, `GET /v1/organization/logo` reads it back. Uploading needs a connection: an image is
// too big to wait in the outbox with the typed details.

enum CompanyLogoImage {
    static let maxSide: CGFloat = 512
    static let maxBytes = 1024 * 1024

    /// Scales a picked image to at most 512 points a side and encodes it as PNG (keeps a
    /// transparent background), or JPEG when the PNG would pass the server's 1 MB limit.
    static func prepare(_ data: Data) -> (data: Data, contentType: String)? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        if let png = resized.pngData(), png.count <= maxBytes { return (png, "image/png") }
        if let jpeg = resized.jpegData(compressionQuality: 0.85), jpeg.count <= maxBytes { return (jpeg, "image/jpeg") }
        return nil
    }
}

/// The logo row in guided setup and Company details: the current logo and a way to change it.
struct CompanyLogoPicker: View {
    @EnvironmentObject private var api: APIClient
    @State private var selection: PhotosPickerItem?
    @State private var showPicker = false
    @State private var logo: UIImage?
    @State private var uploading = false
    @State private var error: String?
    @State private var uploaded = 0
    /// The picked image waiting in the crop step (Paper 09B).
    @State private var draft: LogoCropDraft?
    /// "Choose a different file" closes the crop step and opens Photos again.
    @State private var reopenPicker = false
    /// Paper 61B: the logo as the head of Company profile (a 56pt tile, the company's name and
    /// trade, and a "Change logo" pill). Nil draws setup's row (Paper 09).
    var profile: (name: String, detail: String?)? = nil
    var canEdit = true

    var body: some View {
        Group {
            if let profile { card(profile.name, profile.detail) } else { setupRow }
        }
        .sensoryFeedback(.success, trigger: uploaded)
        .photosPicker(isPresented: $showPicker, selection: $selection, matching: .images)
        .task { if let data = try? await api.logoData() { logo = UIImage(data: data) } }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .fullScreenCover(item: $draft, onDismiss: reopenIfAsked) { picked in
            LogoCropEditor(
                image: picked.image,
                use: { cropped in
                    draft = nil
                    Task { await upload(cropped) }
                },
                chooseAnother: {
                    reopenPicker = true
                    draft = nil
                },
                cancel: { draft = nil }
            )
        }
    }

    private func card(_ name: String, _ detail: String?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 14) {
                Group {
                    if uploading {
                        ProgressView().frame(width: 56, height: 56).background(Theme.fill, in: shape)
                    } else if let logo {
                        Image(uiImage: logo).resizable().scaledToFit().padding(4)
                            .frame(width: 56, height: 56).background(Theme.fill, in: shape).clipShape(shape)
                    } else {
                        Text(String(name.prefix(1)).uppercased()).font(Theme.font(26, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 56, height: 56).background(Theme.brand, in: shape)
                            .dynamicTypeSize(...DynamicTypeSize.large)
                    }
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(Theme.font(17, weight: .semibold)).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail, !detail.isEmpty {
                        Text(detail).font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if canEdit {
                    Button { showPicker = true } label: {
                        Text(uploading ? "Uploading…" : logo == nil ? "Add logo" : "Change logo")
                            .font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.foreground)
                            .padding(.horizontal, 14).frame(minHeight: 36)
                            .background(Theme.fill, in: Capsule())
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .disabled(uploading)
                    .accessibilityIdentifier("company-profile-logo")
                }
            }
            if let error { InlineProblem(message: error).font(Theme.font(13)) }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Paper 09: a 50pt tile (the logo, or a dashed + on the card) beside "Upload logo" and one
    /// muted line; the whole row opens Photos, and the picked image goes to the crop step (09B).
    private var setupRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { showPicker = true } label: {
                HStack(spacing: 12) {
                    tile
                    VStack(alignment: .leading, spacing: 0) {
                        Text(uploading ? "Uploading…" : logo == nil ? "Upload logo" : "Change logo")
                            .font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                        Text("Optional — shown on customer-facing docs")
                            .font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .disabled(uploading)
            .accessibilityLabel(logo == nil ? "Upload logo" : "Change logo")
            .accessibilityValue(uploading ? "Uploading" : (logo == nil ? "No logo yet" : "Logo added"))
            if let error {
                InlineProblem(message: error).font(Theme.font(13))
            }
        }
    }

    private func reopenIfAsked() {
        guard reopenPicker else { return }
        reopenPicker = false
        showPicker = true
    }

    @ViewBuilder private var tile: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        if uploading {
            ProgressView()
                .frame(width: 50, height: 50)
                .background(Theme.card, in: shape)
        } else if let logo {
            Image(uiImage: logo).resizable().scaledToFit()
                .padding(4)
                .frame(width: 50, height: 50)
                .background(Theme.card, in: shape)
                .clipShape(shape)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "plus").font(.system(size: 18, weight: .medium)).foregroundStyle(Theme.muted)
                .frame(width: 50, height: 50)
                .background(Theme.card, in: shape)
                .overlay(shape.strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                .accessibilityHidden(true)
        }
    }

    /// Reads the picked image and opens the crop step; nothing is uploaded until "Use logo".
    private func load(_ item: PhotosPickerItem) async {
        defer { selection = nil }
        do {
            guard let picked = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: picked), image.size.width > 0, image.size.height > 0 else {
                error = "That image couldn't be used. Try a PNG or JPEG."
                return
            }
            error = nil
            draft = LogoCropDraft(image: image)
        } catch is CancellationError {
        } catch {
            self.error = "That image couldn't be used. Try a PNG or JPEG."
        }
    }

    private func upload(_ cropped: Data) async {
        uploading = true
        defer { uploading = false }
        do {
            guard let prepared = CompanyLogoImage.prepare(cropped) else {
                error = "That image couldn't be used. Try a PNG or JPEG."
                return
            }
            try await api.uploadLogo(prepared.data, contentType: prepared.contentType)
            logo = UIImage(data: prepared.data)
            error = nil
            uploaded += 1
        } catch is CancellationError {
        } catch {
            self.error = error.isConnectivityFailure
                ? "Uploading the logo needs a connection. Try again when you're back online."
                : error.localizedDescription
        }
    }
}

// MARK: - Crop step (Paper 09B)

struct LogoCropDraft: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Where the picked image sits in the square: how far it is zoomed past "fits" and how far it
/// has been dragged, measured on a square `side` points wide.
enum LogoCrop {
    static let side: CGFloat = 210
    static let maxZoom: CGFloat = 3

    /// The image's size when it just fits a square `side` wide, times `zoom`.
    static func shownSize(_ image: CGSize, side: CGFloat, zoom: CGFloat) -> CGSize {
        guard image.width > 0, image.height > 0 else { return .zero }
        let fit = min(side / image.width, side / image.height)
        return CGSize(width: image.width * fit * zoom, height: image.height * fit * zoom)
    }

    /// Keeps the drag inside what the zoom allows: an edge of the image never passes the far
    /// edge of the square, and an image smaller than the square stays centred.
    static func clamp(_ offset: CGSize, image: CGSize, zoom: CGFloat) -> CGSize {
        let shown = shownSize(image, side: side, zoom: zoom)
        let x = max(0, (shown.width - side) / 2)
        let y = max(0, (shown.height - side) / 2)
        return CGSize(width: min(x, max(-x, offset.width)), height: min(y, max(-y, offset.height)))
    }

    /// The square as a 512-pixel PNG with a clear background where the image doesn't reach.
    static func render(_ image: UIImage, zoom: CGFloat, offset: CGSize) -> Data? {
        let out = CompanyLogoImage.maxSide
        let k = out / side
        let shown = shownSize(image.size, side: side, zoom: zoom)
        guard shown.width > 0, shown.height > 0 else { return nil }
        let rect = CGRect(x: ((side - shown.width) / 2 + offset.width) * k,
                          y: ((side - shown.height) / 2 + offset.height) * k,
                          width: shown.width * k, height: shown.height * k)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let square = UIGraphicsImageRenderer(size: CGSize(width: out, height: out), format: format).image { _ in
            image.draw(in: rect)
        }
        return square.pngData()
    }
}

/// The image at its zoom and drag, clipped to a square `side` wide. The crop frame and both
/// previews draw the same thing at different sizes.
private struct LogoCropCanvas: View {
    let image: UIImage
    let zoom: CGFloat
    let offset: CGSize
    let side: CGFloat

    var body: some View {
        let shown = LogoCrop.shownSize(image.size, side: side, zoom: zoom)
        let k = side / LogoCrop.side
        Image(uiImage: image).resizable()
            .frame(width: shown.width, height: shown.height)
            .offset(x: offset.width * k, y: offset.height * k)
            .frame(width: side, height: side)
            .clipped()
            .accessibilityHidden(true)
    }
}

/// Paper 09B "Your logo": drag and zoom the picked image inside the square, see it on an
/// invoice and in a text, then "Use logo". Local image work only; the upload happens after.
struct LogoCropEditor: View {
    let image: UIImage
    let use: (Data) -> Void
    let chooseAnother: () -> Void
    let cancel: () -> Void

    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize?
    @State private var pinchStart: CGFloat?
    @State private var failed = false
    /// Set by the setup wizard ("Step 2 / 10"); nil when the logo is changed from settings.
    @Environment(\.setupStepLabel) private var stepLabel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: cancel) { CreamCircleLabel(symbol: "chevron.left") }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Back")
                Spacer()
                if let stepLabel {
                    Text(stepLabel).font(Theme.font(14, weight: .medium)).monospacedDigit().foregroundStyle(Theme.muted)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 16).padding(.top, 2)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your logo").font(Theme.heading()).foregroundStyle(Theme.foreground)
                            .accessibilityAddTraits(.isHeader)
                        Text("Drag to fit it in the square. It shows on estimates, invoices and texts.")
                            .font(Theme.font(15)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20).padding(.top, 14)
                    VStack(spacing: 14) {
                        cropCard
                        zoomRow
                    }
                    .padding(.horizontal, 16).padding(.top, 18)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preview").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                            .padding(.horizontal, 4)
                            .accessibilityAddTraits(.isHeader)
                        HStack(alignment: .top, spacing: 8) {
                            invoicePreview
                            textPreview
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 18)
                    if failed {
                        InlineProblem(message: "That image couldn't be used. Choose a different file.")
                            .font(Theme.font(13))
                            .padding(.horizontal, 20).padding(.top, 12)
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: 4) {
                Button(action: commit) {
                    Text("Use logo").inkCommit()
                }
                .buttonStyle(PressStyle())
                Button(action: chooseAnother) {
                    Text("Choose a different file")
                        .font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.subtle)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
        }
        .background(Theme.background.ignoresSafeArea())
    }

    private func commit() {
        if let data = LogoCrop.render(image, zoom: zoom, offset: offset) {
            use(data)
        } else {
            failed = true
        }
    }

    /// The card with the square: a 2pt ink frame on the field fill; the image moves under it.
    private var cropCard: some View {
        let frame = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return LogoCropCanvas(image: image, zoom: zoom, offset: offset, side: LogoCrop.side)
            .background(Theme.fill)
            .clipShape(frame)
            .overlay(frame.strokeBorder(Theme.foreground, lineWidth: 2))
            .contentShape(Rectangle())
            .gesture(drag)
            .simultaneousGesture(pinch)
            .frame(maxWidth: .infinity, minHeight: 250, maxHeight: 250)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Logo in the square")
            .accessibilityHint("Drag to move it. Use the zoom slider to make it bigger or smaller.")
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStart ?? offset
                dragStart = start
                let moved = CGSize(width: start.width + value.translation.width,
                                   height: start.height + value.translation.height)
                offset = LogoCrop.clamp(moved, image: image.size, zoom: zoom)
            }
            .onEnded { _ in dragStart = nil }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? zoom
                pinchStart = start
                setZoom(start * value.magnification)
            }
            .onEnded { _ in pinchStart = nil }
    }

    private func setZoom(_ value: CGFloat) {
        zoom = min(LogoCrop.maxZoom, max(1, value))
        offset = LogoCrop.clamp(offset, image: image.size, zoom: zoom)
    }

    private var zoomValue: Binding<Double> {
        Binding(get: { Double(zoom) }, set: { setZoom(CGFloat($0)) })
    }

    /// Small square, the track, big square: smaller to larger.
    private var zoomRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "square").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.muted)
                .frame(width: 16).accessibilityHidden(true)
            Slider(value: zoomValue, in: 1...Double(LogoCrop.maxZoom))
                .tint(Theme.brand)
                .accessibilityLabel("Zoom")
            Image(systemName: "square").font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.muted)
                .frame(width: 20).accessibilityHidden(true)
        }
        .padding(.horizontal, 6)
    }

    private var invoicePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                LogoCropCanvas(image: image, zoom: zoom, offset: offset, side: 26)
                    .background(Theme.fill)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text("Invoice").font(Theme.font(12, weight: .semibold)).foregroundStyle(Theme.foreground)
                    .lineLimit(1)
            }
            Capsule().fill(Theme.fill).frame(height: 6).padding(.trailing, 28)
            Capsule().fill(Theme.fill).frame(height: 6).padding(.trailing, 56)
            Text("On invoices").font(Theme.font(12)).foregroundStyle(Theme.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview on invoices")
    }

    private var textPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                LogoCropCanvas(image: image, zoom: zoom, offset: offset, side: 26)
                    .background(Theme.fill)
                    .clipShape(Circle())
                Text("Your company").font(Theme.font(12, weight: .semibold)).foregroundStyle(Theme.foreground)
                    .lineLimit(1)
            }
            Text("Your tech is on the way").font(Theme.font(12)).foregroundStyle(Theme.foreground)
                .padding(.vertical, 6).padding(.horizontal, 9)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text("In texts").font(Theme.font(12)).foregroundStyle(Theme.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview in texts")
    }
}
