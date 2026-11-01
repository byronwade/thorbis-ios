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
    @State private var logo: UIImage?
    @State private var uploading = false
    @State private var error: String?
    @State private var uploaded = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Logo").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
            HStack(spacing: 12) {
                Group {
                    if let logo {
                        Image(uiImage: logo).resizable().scaledToFit().accessibilityLabel("Your logo")
                    } else {
                        Image(systemName: "photo").font(.system(size: 20)).foregroundStyle(Theme.muted)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: 56, height: 56)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.border))
                PhotosPicker(selection: $selection, matching: .images) {
                    HStack(spacing: 6) {
                        if uploading { ProgressView() }
                        Text(uploading ? "Uploading…" : logo == nil ? "Choose logo" : "Change logo")
                    }
                    .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.brandText)
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .disabled(uploading)
                Spacer(minLength: 0)
            }
            if let error {
                InlineProblem(message: error).font(Theme.font(13))
            } else {
                Text("A square PNG or JPEG works best.").font(Theme.font(13)).foregroundStyle(Theme.muted)
            }
        }
        .sensoryFeedback(.success, trigger: uploaded)
        .task { if let data = try? await api.logoData() { logo = UIImage(data: data) } }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
    }

    private func upload(_ item: PhotosPickerItem) async {
        uploading = true
        defer { uploading = false; selection = nil }
        do {
            guard let picked = try await item.loadTransferable(type: Data.self),
                  let prepared = CompanyLogoImage.prepare(picked) else {
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
