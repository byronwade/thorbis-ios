import AVFoundation
import PhotosUI
import SwiftUI
import ThorbisCore
import UIKit

/// Photos are append-only field testimony (domains/jobs). Uploads keep their
/// state on screen until the server confirms them; a failure stays retryable (HIG-015, HIG-019).
struct JobPhotosSection: View {
    @Environment(AppModel.self) private var model
    let jobId: String
    @Binding var photos: [JobPhoto]
    var loadError: String?
    var retry: (() async -> Void)?

    @State private var picked: [PhotosPickerItem] = []
    @State private var pending: [PendingUpload] = []
    @State private var showingCamera = false
    @State private var cameraDenied = false
    @State private var viewing: JobPhoto?

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: Theme.Space.s)]

    var body: some View {
        Section {
            if let loadError {
                InlineError(message: loadError, retry: retry).sheetRow()
            }
            if photos.isEmpty, pending.isEmpty {
                if loadError == nil { Text("No photos yet.").foregroundStyle(Theme.inkQuiet).sheetRow() }
            } else {
                LazyVGrid(columns: columns, spacing: Theme.Space.s) {
                    ForEach(photos) { photo in
                        Button { viewing = photo } label: {
                            PhotoThumbnail(jobId: jobId, photo: photo)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Photo added \(Format.relative(Timestamp.parse(photo.createdAt)))")
                    }
                    ForEach(pending) { upload in
                        PendingThumbnail(upload: upload) { Task { await retry(upload) } }
                    }
                }
                .padding(.vertical, Theme.Space.xs)
                .sheetRow()
            }
            HStack(spacing: Theme.Space.m) {
                PhotosPicker(selection: $picked, maxSelectionCount: 10, matching: .images) {
                    Label("Library", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.rim)
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { openCamera() } label: {
                        Label("Camera", systemImage: "camera").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.rim)
                }
            }
            .sheetRow()
        } header: {
            Text("Photos")
        } footer: {
            if cameraDenied {
                Text("Camera access is off for Thorbis. Turn it on in Settings › Privacy & Security › Camera, or add photos from your library.")
            }
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            Task { await upload(items) }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraCapture { image in
                Task { await upload(image: image) }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $viewing) { photo in
            PhotoViewer(jobId: jobId, photo: photo)
        }
    }

    private func openCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showingCamera = true
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                cameraDenied = !granted
                showingCamera = granted
            }
        default:
            cameraDenied = true
        }
    }

    private func upload(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { continue }
            await upload(image: image)
        }
    }

    private func upload(image: UIImage) async {
        guard let jpeg = PhotoEncoding.jpeg(image) else { return }
        let upload = PendingUpload(data: jpeg, preview: image.preparingThumbnail(of: CGSize(width: 240, height: 240)) ?? image)
        pending.append(upload)
        await send(upload)
    }

    private func retry(_ upload: PendingUpload) async {
        guard let index = pending.firstIndex(where: { $0.id == upload.id }) else { return }
        pending[index].failure = nil
        await send(pending[index])
    }

    private func send(_ upload: PendingUpload) async {
        do {
            let photo = try await model.api.uploadPhoto(job: jobId, data: upload.data, contentType: "image/jpeg")
            pending.removeAll { $0.id == upload.id }
            photos.append(photo)
        } catch {
            if let index = pending.firstIndex(where: { $0.id == upload.id }) {
                pending[index].failure = model.message(for: error) ?? "Upload stopped."
            }
        }
    }
}

struct PendingUpload: Identifiable {
    let id = UUID()
    let data: Data
    let preview: UIImage
    var failure: String?
}

enum PhotoEncoding {
    /// Long edge 2048pt, JPEG 0.8: well under the 15 MB cap and fast on a weak signal.
    static func jpeg(_ image: UIImage, maxEdge: CGFloat = 2048) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxEdge ? maxEdge / longest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}

/// Thumbnails decode at display size, never the full image in a scrolling list (HIG-019).
struct PhotoThumbnail: View {
    @Environment(AppModel.self) private var model
    let jobId: String
    let photo: JobPhoto
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Theme.field
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed {
                Image(systemName: "photo").foregroundStyle(Theme.inkQuiet)
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: 96, minHeight: 96)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small).strokeBorder(Theme.rim))
        .task(id: photo.id) {
            do {
                let data = try await model.api.photoData(job: jobId, photo: photo.id)
                image = await Task.detached { UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 288, height: 288)) }.value
                failed = image == nil
            } catch {
                failed = true
            }
        }
    }
}

struct PendingThumbnail: View {
    let upload: PendingUpload
    let retry: () -> Void

    var body: some View {
        ZStack {
            Image(uiImage: upload.preview).resizable().scaledToFill().opacity(0.5)
            if upload.failure != nil {
                Button(action: retry) {
                    Label("Retry upload", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                        .frame(width: Theme.minimumHit, height: Theme.minimumHit)
                        .background(Theme.sheet, in: Circle())
                }
                .accessibilityLabel("Upload failed. Retry")
            } else {
                ProgressView().accessibilityLabel("Uploading")
            }
        }
        .frame(minWidth: 96, minHeight: 96)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small).strokeBorder(upload.failure == nil ? Theme.rim : Theme.danger))
    }
}

struct PhotoViewer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let jobId: String
    let photo: JobPhoto
    @State private var image: UIImage?
    @State private var error: String?
    @State private var attempt = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .accessibilityLabel("Job photo")
                } else if let error {
                    ContentUnavailableView {
                        Label("Couldn't load photo", systemImage: "photo.badge.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try again") { attempt += 1 }.buttonStyle(.rim).fixedSize()
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(Format.relative(Timestamp.parse(photo.createdAt)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if let image {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(item: Image(uiImage: image), preview: SharePreview("Job photo", image: Image(uiImage: image)))
                    }
                }
            }
            .task(id: attempt) { await load() }
        }
    }
}

extension PhotoViewer {
    private func load() async {
        error = nil
        do {
            let data = try await model.api.photoData(job: jobId, photo: photo.id)
            guard let decoded = UIImage(data: data) else {
                error = "This photo couldn't be opened."
                return
            }
            image = decoded
        } catch {
            self.error = model.message(for: error)
        }
    }
}

/// The system camera (HIG-003): no custom capture UI.
struct CameraCapture: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCapture
        init(_ parent: CameraCapture) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onCapture(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
