import SwiftUI
import PencilKit

/// Flattens a PencilKit drawing onto a photo into a brand-new image. The original is only read.
enum PhotoMarkupFlattener {
    /// `canvasSize` is the on-screen size the drawing was made at (the photo's fitted rect).
    static func flatten(_ image: UIImage, drawing: PKDrawing, canvasSize: CGSize) -> UIImage {
        let size = image.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let scale = canvasSize.width > 0 ? size.width / canvasSize.width : 1
        var ink: UIImage?
        // Render ink with light traits so dark mode never inverts the chosen colors.
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            ink = drawing.image(from: CGRect(origin: .zero, size: canvasSize), scale: scale)
        }
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
            ink?.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// The largest rect with the image's aspect ratio that fits in `container`, centred.
    static func fittedRect(for imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2,
                      width: size.width, height: size.height)
    }
}

@MainActor
final class PhotoMarkupCanvas: ObservableObject {
    let canvas = PKCanvasView()
    let toolPicker = PKToolPicker()
    @Published var hasStrokes = false
    @Published var canUndo = false

    func undo() {
        canvas.undoManager?.undo()
        refresh()
    }

    func refresh() {
        hasStrokes = !canvas.drawing.strokes.isEmpty
        canUndo = canvas.undoManager?.canUndo ?? false
    }
}

private struct MarkupCanvasRepresentable: UIViewRepresentable {
    @ObservedObject var model: PhotoMarkupCanvas

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = model.canvas
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.overrideUserInterfaceStyle = .light
        canvas.minimumZoomScale = 1
        canvas.maximumZoomScale = 1
        canvas.isScrollEnabled = false
        canvas.tool = PKInkingTool(.pen, color: .systemRed, width: 6)
        canvas.delegate = context.coordinator
        canvas.accessibilityLabel = "Drawing area"
        let picker = model.toolPicker
        picker.selectedTool = canvas.tool
        picker.addObserver(canvas)
        DispatchQueue.main.async {
            picker.setVisible(true, forFirstResponder: canvas)
            canvas.becomeFirstResponder()
        }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {}

    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.model.toolPicker.setVisible(false, forFirstResponder: canvas)
        coordinator.model.toolPicker.removeObserver(canvas)
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let model: PhotoMarkupCanvas
        init(model: PhotoMarkupCanvas) { self.model = model }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { model.refresh() }
    }
}

/// Full-screen PencilKit markup over a job photo (pen, highlighter, eraser via the system tool
/// picker). Save hands back a NEW flattened image; the caller files it as a separate photo.
struct PhotoMarkupView: View {
    let image: UIImage
    /// Saves the flattened image. Throwing keeps the canvas open with the error shown.
    let onSave: (UIImage) throws -> Void
    let onCancel: () -> Void
    @StateObject private var model = PhotoMarkupCanvas()
    @State private var canvasSize: CGSize = .zero
    @State private var confirmDiscard = false
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("Cancel") {
                    if model.hasStrokes { confirmDiscard = true } else { onCancel() }
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("markup-cancel")
                Spacer()
                Button { model.undo() } label: {
                    Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44)
                }
                .disabled(!model.canUndo)
                .accessibilityLabel("Undo")
                Button(saving ? "Saving…" : "Save") { save() }
                    .font(Theme.font(17, weight: .semibold))
                    .frame(minHeight: 44)
                    .disabled(!model.hasStrokes || saving)
                    .accessibilityIdentifier("markup-save")
            }
            .font(Theme.font(17))
            .foregroundStyle(Theme.foreground)
            .tint(Theme.brandText)
            .padding(.horizontal, Theme.gutter)
            if let error {
                ErrorBanner(message: error)
            }
            GeometryReader { proxy in
                let rect = PhotoMarkupFlattener.fittedRect(for: image.size, in: proxy.size)
                ZStack(alignment: .topLeading) {
                    Image(uiImage: image).resizable().frame(width: rect.width, height: rect.height)
                        .accessibilityLabel("Photo being marked up")
                    MarkupCanvasRepresentable(model: model).frame(width: rect.width, height: rect.height)
                }
                .offset(x: rect.minX, y: rect.minY)
                .onAppear { canvasSize = rect.size }
                .onChange(of: rect.size) { _, size in canvasSize = size }
            }
            Text("Draw with your finger or Apple Pencil. The original photo stays as it is.")
                .font(Theme.font(12)).foregroundStyle(Theme.muted)
                .padding(.horizontal, Theme.gutter).padding(.vertical, 8)
        }
        .background(Theme.background)
        .thorbisConfirm("Discard your markup?", message: "The original photo stays on the job.",
                        isPresented: $confirmDiscard,
                        actions: [ThorbisConfirmAction("Discard markup", role: .destructive) { onCancel() }])
    }

    private func save() {
        guard model.hasStrokes, canvasSize.width > 0 else { return }
        saving = true
        defer { saving = false }
        let flattened = PhotoMarkupFlattener.flatten(image, drawing: model.canvas.drawing, canvasSize: canvasSize)
        do {
            try onSave(flattened)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
