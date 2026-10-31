import SwiftUI
import UIKit

// Capture flow (2026-10-31 media redesign). One full-screen container swaps the camera, the quick
// tag step and markup inside itself, so nothing is dismissed and re-presented between shots.
//
// - Single: system camera, then the tag step (Before / After / Skip, an optional spoken caption),
//   with "Take another" as the commit. The stage stays chosen for the next shot, so a run of
//   Before photos is one tap each.
// - Burst: the camera stays open; every shot is saved at once under the stage chosen on the
//   camera (none by default) and tagged later from the grid.
// - Library: a chosen photo goes through the same tag step, with Save as the commit.
//
// A photo is held in memory only during the tag step. Leaving the app, or the step closing any
// other way, saves it with the stage on screen, so nothing taken is lost.

enum MediaCaptureMode: Equatable {
    case single, burst, library
}

struct MediaCaptureRequest: Identifiable {
    let id = UUID()
    let mode: MediaCaptureMode
    /// The stage preselected in the tag step ("Before", "After", "Other").
    var stage: String
    /// A photo to start on (library pick, or a DEBUG fixture); nil opens the camera.
    var held: Data? = nil
}

/// The stage words in the tag step. "Other" is shown as Skip: the photo is filed with no stage.
enum MediaStageChoice {
    static let all: [(value: String, label: String)] = [("Before", "Before"), ("After", "After"), ("Other", "Skip")]
    static func tags(_ stage: String) -> [String] { stage == "Other" ? [] : [stage] }
}

struct MediaCaptureFlow: View {
    let request: MediaCaptureRequest
    /// Saves one photo (JPEG bytes, tags, caption) to the on-phone queue. Throwing keeps the step open.
    let file: (Data, [String], String?) throws -> Void
    /// Saves a marked-up copy as a new photo.
    let fileMarkup: (UIImage, [String]) throws -> Void
    /// The stage the technician last chose, so the screen preselects it next time.
    let onStage: (String) -> Void
    let onClose: () -> Void

    private enum Phase { case camera, review, markup(UIImage, [String]) }

    @EnvironmentObject private var session: SessionController
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var dictation = NoteDictation()
    @StateObject private var burst = BurstCameraModel()
    @State private var phase: Phase = .camera
    @State private var held: Data?
    @State private var heldImage: UIImage?
    @State private var stage = "Before"
    @State private var caption = ""
    @State private var error: String?
    @State private var filed = 0
    @State private var started = false

    var body: some View {
        Group {
            switch phase {
            case .camera:
                if request.mode == .burst {
                    BurstCamera(model: burst).ignoresSafeArea()
                } else {
                    CameraCapture { image in
                        guard let image else { onClose(); return }
                        hold(JobMediaView.jpeg(image))
                    }
                    .ignoresSafeArea()
                }
            case .review:
                if let heldImage { tagStep(heldImage) } else { Color.black.ignoresSafeArea() }
            case .markup(let image, let tags):
                PhotoMarkupView(image: image, onSave: { flattened in
                    try fileMarkup(flattened, tags)
                    afterMarkup()
                }, onCancel: afterMarkup)
            }
        }
        .onAppear {
            guard !started else { return }
            started = true
            stage = request.stage
            burst.stage = "Other"
            burst.onPhoto = { image in
                guard let data = JobMediaView.jpeg(image) else { burst.problem = "That photo was too large to save."; return }
                do {
                    try file(data, MediaStageChoice.tags(burst.stage), nil)
                    burst.count += 1
                    burst.problem = nil
                } catch { burst.problem = error.localizedDescription }
            }
            burst.onDone = onClose
            if let start = request.held { hold(start) }
        }
        .onChange(of: scenePhase) { _, next in
            // Leaving the app mid-step saves the photo as shown rather than holding it in memory.
            if next != .active, held != nil { _ = fileHeld(); dictation.stop() }
        }
        .onDisappear { if held != nil { _ = fileHeld() }; dictation.stop() }
    }

    // MARK: Tag step

    private func tagStep(_ image: UIImage) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button(request.mode == .library ? "Cancel" : "Retake") { discard() }
                    .buttonStyle(ThorbisBarButtonStyle())
                    .accessibilityHint(request.mode == .library ? "Leaves without adding this photo." : "Discards this photo and opens the camera.")
                    .accessibilityIdentifier("media-tag-retake")
                Spacer(minLength: 0)
                if filed > 0 {
                    Text("\(filed) saved").font(Theme.monoFont(13, weight: .medium)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                PaperCircleButton(symbol: "pencil.tip.crop.circle", label: "Mark up this photo", size: 44, fill: Theme.card, bordered: true) {
                    startMarkup(image)
                }
                .accessibilityIdentifier("media-tag-markup")
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 8)

            Image(uiImage: image).resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, Theme.gutter)
                .accessibilityLabel("The photo you just took")

            VStack(spacing: 12) {
                if let error { ErrorBanner(message: error).padding(.horizontal, -Theme.gutter) }
                captionRow
                if let problem = dictation.problem {
                    Text(problem.message).font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 8) {
                    ForEach(MediaStageChoice.all, id: \.value) { choice in
                        MediaQuietButton(title: choice.label, selected: stage == choice.value) {
                            stage = choice.value
                            onStage(choice.value)
                        }
                        .accessibilityIdentifier("media-tag-\(choice.value.lowercased())")
                    }
                }
                .sensoryFeedback(.selection, trigger: stage)
                commitRow
            }
            .padding(.horizontal, Theme.gutter).padding(.bottom, 8)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
    }

    private var captionRow: some View {
        HStack(spacing: 8) {
            TextField("Caption (optional)", text: $caption)
                .font(Theme.font(16))
                .submitLabel(.done)
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.border))
                .accessibilityIdentifier("media-tag-caption")
            Button {
                if dictation.isListening { dictation.stop() } else {
                    Task { await dictation.start(draft: caption, isOffline: session.isOffline) { caption = $0 } }
                }
            } label: {
                Image(systemName: dictation.isListening ? "stop.fill" : "mic")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(dictation.isListening ? Theme.onInk : Theme.foreground)
                    .frame(width: 52, height: 52)
                    .background(dictation.isListening ? Theme.ink : Theme.fill, in: Circle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(dictation.isListening ? "Stop dictating" : "Say a caption")
        }
    }

    @ViewBuilder private var commitRow: some View {
        if request.mode == .library {
            Button { if fileHeld() { onClose() } } label: {
                Label("Save photo", systemImage: "square.and.arrow.down").inkCommit(height: 56)
            }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("media-tag-save")
        } else {
            HStack(spacing: 8) {
                Button { if fileHeld() { phase = .camera } } label: {
                    Label("Take another", systemImage: "camera").inkCommit(height: 56)
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("media-tag-take-another")
                MediaQuietButton(title: "Done") { if fileHeld() { onClose() } }
                    .frame(maxWidth: 120)
                    .accessibilityIdentifier("media-tag-done")
            }
        }
    }

    // MARK: Actions

    private func hold(_ data: Data?) {
        guard let data, let image = UIImage(data: data) else {
            error = "That photo couldn’t be prepared. Try again."
            phase = .camera
            return
        }
        held = data
        heldImage = image
        caption = ""
        error = nil
        phase = .review
    }

    /// Files the held photo with the stage and caption on screen. Returns false (and keeps the
    /// step open with the reason) when it could not be saved.
    @discardableResult private func fileHeld() -> Bool {
        guard let held else { return true }
        dictation.stop()
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try file(held, MediaStageChoice.tags(stage), trimmed.isEmpty ? nil : trimmed)
            self.held = nil
            filed += 1
            error = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private func discard() {
        dictation.stop()
        held = nil
        heldImage = nil
        if request.mode == .library { onClose() } else { phase = .camera }
    }

    /// Markup files the original first (with its stage and caption), then a marked-up copy.
    private func startMarkup(_ image: UIImage) {
        let tags = MediaStageChoice.tags(stage)
        guard fileHeld() else { return }
        phase = .markup(image, tags)
    }

    private func afterMarkup() {
        heldImage = nil
        if request.mode == .library { onClose() } else { phase = .camera }
    }
}

// MARK: - Burst camera

/// State shared between the burst camera's UIKit picker and its SwiftUI overlay.
@MainActor
final class BurstCameraModel: ObservableObject {
    @Published var count = 0
    @Published var stage = "Other"
    @Published var shooting = false
    @Published var problem: String?
    var onPhoto: (UIImage) -> Void = { _ in }
    var onDone: () -> Void = {}
    weak var picker: UIImagePickerController?

    func shoot() {
        guard !shooting, let picker else { return }
        shooting = true
        picker.takePicture()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

/// The system camera with its own controls hidden: it stays live between shots, and each shot is
/// handed back without closing. Our overlay draws the shutter, the stage and Done.
struct BurstCamera: UIViewControllerRepresentable {
    @ObservedObject var model: BurstCameraModel

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.showsCameraControls = false
        picker.delegate = context.coordinator
        let screen = picker.view.window?.windowScene?.screen.bounds ?? UIScreen.main.bounds
        // The preview is 4:3 at the top; centre it in the screen.
        let previewHeight = screen.width * 4 / 3
        picker.cameraViewTransform = CGAffineTransform(translationX: 0, y: max(0, (screen.height - previewHeight) / 2))
        let overlay = UIHostingController(rootView: BurstCameraOverlay(model: model))
        overlay.view.backgroundColor = .clear
        overlay.view.frame = screen
        picker.cameraOverlayView = overlay.view
        context.coordinator.overlay = overlay
        model.picker = picker
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let model: BurstCameraModel
        var overlay: UIHostingController<BurstCameraOverlay>?
        init(model: BurstCameraModel) { self.model = model }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            MainActor.assumeIsolated {
                model.shooting = false
                if let image { model.onPhoto(image) }
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            MainActor.assumeIsolated { model.onDone() }
        }
    }
}

/// Shutter, count, stage and Done over the live burst camera. Dark glass so it reads on any scene.
struct BurstCameraOverlay: View {
    @ObservedObject var model: BurstCameraModel

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(model.count == 0 ? "Burst · shots save as you take them" : "\(model.count) saved")
                    .font(Theme.font(15, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(.black.opacity(0.55), in: Capsule())
                Spacer()
                Button(model.count == 0 ? "Close" : "Done") { model.onDone() }
                    .buttonStyle(ThorbisBarButtonStyle(prominent: model.count > 0))
                    .accessibilityIdentifier("burst-done")
            }
            if let problem = model.problem {
                Text(problem).font(Theme.font(14)).foregroundStyle(.white)
                    .padding(10).background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(MediaStageChoice.all, id: \.value) { choice in
                    let on = model.stage == choice.value
                    Button { model.stage = choice.value } label: {
                        Text(choice.value == "Other" ? "No stage" : choice.label)
                            .font(Theme.font(15, weight: .medium))
                            .foregroundStyle(on ? .black : .white)
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(on ? Color.white : Color.black.opacity(0.5), in: Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Button { model.shoot() } label: {
                Circle().fill(.white).frame(width: 72, height: 72)
                    .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 3).padding(5))
                    .opacity(model.shooting ? 0.5 : 1)
                    .frame(width: 88, height: 88)
                    .contentShape(Circle())
            }
            .buttonStyle(PressStyle())
            .disabled(model.shooting)
            .accessibilityLabel("Take photo")
            .accessibilityIdentifier("burst-shutter")
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 56).padding(.bottom, 34)
    }
}
