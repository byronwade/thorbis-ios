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

/// The drawing tools of Paper 21D's toolbar that PencilKit can draw.
enum PhotoMarkupTool: String, CaseIterable, Identifiable {
    case pen, marker, eraser

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .pen: return "pencil.tip"
        case .marker: return "highlighter"
        case .eraser: return "eraser"
        }
    }

    var label: String {
        switch self {
        case .pen: return "Pen"
        case .marker: return "Highlighter"
        case .eraser: return "Eraser"
        }
    }
}

@MainActor
final class PhotoMarkupCanvas: ObservableObject {
    /// Paper 21D's ink swatches: brand, red, amber, white, black. Ink on a photo, not app chrome.
    static let inks: [UIColor] = [
        UIColor(red: 0.184, green: 0.420, blue: 1.0, alpha: 1),
        UIColor(red: 0.890, green: 0.0, blue: 0.086, alpha: 1),
        UIColor(red: 0.949, green: 0.651, blue: 0.094, alpha: 1),
        UIColor.white,
        UIColor(red: 0.078, green: 0.071, blue: 0.063, alpha: 1),
    ]
    static let inkNames: [String] = ["Blue", "Red", "Amber", "White", "Black"]

    let canvas = PKCanvasView()
    @Published var hasStrokes = false
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var tool: PhotoMarkupTool = .pen
    @Published var inkIndex = 0

    func undo() {
        canvas.undoManager?.undo()
        refresh()
    }

    func redo() {
        canvas.undoManager?.redo()
        refresh()
    }

    func refresh() {
        hasStrokes = !canvas.drawing.strokes.isEmpty
        canUndo = canvas.undoManager?.canUndo ?? false
        canRedo = canvas.undoManager?.canRedo ?? false
    }

    func choose(_ next: PhotoMarkupTool) {
        tool = next
        applyTool()
    }

    func chooseInk(_ index: Int) {
        guard Self.inks.indices.contains(index) else { return }
        inkIndex = index
        // Picking a colour while erasing means "draw in this colour".
        if tool == .eraser { tool = .pen }
        applyTool()
    }

    func applyTool() {
        let ink = Self.inks[inkIndex]
        switch tool {
        case .pen: canvas.tool = PKInkingTool(.pen, color: ink, width: 6)
        case .marker: canvas.tool = PKInkingTool(.marker, color: ink, width: 18)
        case .eraser: canvas.tool = PKEraserTool(.vector)
        }
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
        model.applyTool()
        canvas.delegate = context.coordinator
        canvas.accessibilityLabel = "Drawing area"
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let model: PhotoMarkupCanvas
        init(model: PhotoMarkupCanvas) { self.model = model }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { model.refresh() }
    }
}

/// Full-screen PencilKit markup over a job photo with Paper 21D's own toolbar: pen, highlighter
/// and eraser, five inks, undo and redo. Save hands back a NEW flattened image; the caller files
/// it as a separate photo.
struct PhotoMarkupView: View {
    let image: UIImage
    /// The photo's stage ("Before", "After"), shown as a chip beside the title when known.
    var stage: String? = nil
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
            // Paper 21D "Edit photo": a 44pt card close circle, the title 17 Semibold with the
            // photo's stage as a card chip, and Done as the 44pt brand pill (15 Semibold).
            HStack(spacing: 8) {
                Button {
                    if model.hasStrokes { confirmDiscard = true } else { onCancel() }
                } label: { CreamCircleLabel(symbol: "xmark") }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Cancel")
                .accessibilityIdentifier("markup-cancel")
                Spacer(minLength: 0)
                Text("Edit photo").font(Theme.font(17, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                if let stage {
                    Text(stage).font(Theme.font(13, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Theme.card, in: Capsule())
                }
                Spacer(minLength: 0)
                Button { save() } label: {
                    Text(saving ? "Saving…" : "Done").font(Theme.font(15, weight: .semibold)).foregroundStyle(Color.white)
                        .padding(.horizontal, 18).frame(minHeight: 44)
                        .background(Theme.brand.opacity(!model.hasStrokes || saving ? 0.5 : 1), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .disabled(!model.hasStrokes || saving)
                .accessibilityIdentifier("markup-save")
            }
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, PaperCardMetrics.margin).padding(.vertical, 8)
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
            toolbar
        }
        .background(Theme.canvas)
        .thorbisConfirm("Discard your markup?", message: "The original photo stays on the job.",
                        isPresented: $confirmDiscard,
                        actions: [ThorbisConfirmAction("Discard", role: .destructive) { onCancel() }])
    }

    /// Paper 21D's toolbar: the tools as 44pt card circles (the chosen one on brand surface), then
    /// undo, the ink swatches and redo.
    private var toolbar: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ForEach(PhotoMarkupTool.allCases) { tool in
                    MarkupToolButton(tool: tool, selected: model.tool == tool) { model.choose(tool) }
                }
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 0) {
                Button { model.undo() } label: { CreamCircleLabel(symbol: "arrow.uturn.backward") }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Undo")
                    .disabled(!model.canUndo)
                    .opacity(model.canUndo ? 1 : 0.4)
                Spacer(minLength: 0)
                ForEach(0..<PhotoMarkupCanvas.inks.count, id: \.self) { index in
                    MarkupInkSwatch(color: Color(uiColor: PhotoMarkupCanvas.inks[index]),
                                    name: PhotoMarkupCanvas.inkNames[index],
                                    selected: model.inkIndex == index && model.tool != .eraser,
                                    rimmed: index == PhotoMarkupCanvas.inks.count - 1) {
                        model.chooseInk(index)
                    }
                }
                Spacer(minLength: 0)
                Button { model.redo() } label: { CreamCircleLabel(symbol: "arrow.uturn.forward") }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Redo")
                    .disabled(!model.canRedo)
                    .opacity(model.canRedo ? 1 : 0.4)
            }
        }
        .foregroundStyle(Theme.foreground)
        .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 6).padding(.bottom, 12)
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

/// Paper 21D: one tool as a 44pt card circle; the chosen one on brand surface in brand text.
private struct MarkupToolButton: View {
    let tool: PhotoMarkupTool
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: tool.symbol).font(.system(size: 18, weight: .medium))
                .foregroundStyle(selected ? Theme.brandText : Theme.subtle)
                .frame(width: 44, height: 44)
                .background(selected ? Theme.brandSurface : Theme.card, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(tool.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("markup-tool-\(tool.rawValue)")
    }
}

/// Paper 21D: one ink as a 28pt dot; the chosen one a 24pt dot inside a 34pt ring. The dark ink
/// keeps a light rim so it shows on the dark canvas.
private struct MarkupInkSwatch: View {
    let color: Color
    let name: String
    let selected: Bool
    let rimmed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if selected {
                    Circle().strokeBorder(Theme.foreground, lineWidth: 2).frame(width: 34, height: 34)
                    Circle().fill(color).frame(width: 24, height: 24)
                } else {
                    Circle().fill(color).frame(width: 28, height: 28)
                    if rimmed {
                        Circle().strokeBorder(Theme.foreground.opacity(0.45), lineWidth: 1.5).frame(width: 28, height: 28)
                    }
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(name) ink")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
