import SwiftUI
import ARKit
import SceneKit
import AVFoundation

/// Distance text for a site measurement: feet and inches where the locale uses US units,
/// metres or centimetres elsewhere, with the locale's number formatting.
enum MeasureDistanceFormatter {
    static func format(meters: Double, locale: Locale) -> String {
        let meters = max(0, meters)
        if locale.measurementSystem == .us {
            var totalInches = Int((meters / 0.0254).rounded())
            if totalInches < 12 { return "\(totalInches) in" }
            let feet = totalInches / 12
            totalInches -= feet * 12
            return "\(feet) ft \(totalInches) in"
        }
        let number = NumberFormatter()
        number.locale = locale
        number.numberStyle = .decimal
        if meters < 1 {
            number.maximumFractionDigits = 0
            return "\(number.string(from: NSNumber(value: (meters * 100).rounded())) ?? "0") cm"
        }
        number.minimumFractionDigits = 2
        number.maximumFractionDigits = 2
        return "\(number.string(from: NSNumber(value: meters)) ?? "0") m"
    }

    /// Caption filed with the saved measurement photo.
    static func caption(meters: Double, locale: Locale) -> String {
        "Measured \(format(meters: meters, locale: locale))"
    }

    /// The units a trade reads a tape in. Feet and inches for most US trades, plain inches for
    /// fitters who think in inches, metric elsewhere. Defaults from the locale; the choice is kept.
    enum Unit: String, CaseIterable {
        case feetInches, inches, metric
        var label: String {
            switch self {
            case .feetInches: "ft in"
            case .inches: "in"
            case .metric: "m / cm"
            }
        }
        static func standard(for locale: Locale) -> Unit { locale.measurementSystem == .us ? .feetInches : .metric }
    }

    static func format(meters: Double, unit: Unit, locale: Locale) -> String {
        let meters = max(0, meters)
        switch unit {
        case .feetInches:
            return format(meters: meters, locale: Locale(identifier: "en_US"))
        case .inches:
            let number = NumberFormatter()
            number.locale = locale
            number.numberStyle = .decimal
            number.maximumFractionDigits = 1
            number.minimumFractionDigits = 0
            let inches = (meters / 0.0254 * 2).rounded() / 2
            return "\(number.string(from: NSNumber(value: inches)) ?? "0") in"
        case .metric:
            var metric = Locale.Components(locale: locale)
            metric.measurementSystem = .metric
            return format(meters: meters, locale: Locale(components: metric))
        }
    }

    static func caption(meters: Double, unit: Unit, locale: Locale) -> String {
        "Measured \(format(meters: meters, unit: unit, locale: locale))"
    }
}

enum SiteMeasure {
    /// World tracking is unavailable in the simulator and on very old devices; the entry hides then.
    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    /// Draws the measurement label onto the AR snapshot so the saved photo carries it.
    static func stamp(_ image: UIImage, text: String) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
            let fontSize = max(28, size.width * 0.06)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            let textSize = (text as NSString).size(withAttributes: attributes)
            let padding = fontSize * 0.5
            let box = CGRect(x: (size.width - textSize.width) / 2 - padding,
                             y: size.height - textSize.height - padding * 4,
                             width: textSize.width + padding * 2, height: textSize.height + padding)
            UIColor.black.withAlphaComponent(0.7).setFill()
            UIBezierPath(roundedRect: box, cornerRadius: padding).fill()
            (text as NSString).draw(at: CGPoint(x: box.minX + padding, y: box.minY + padding / 2), withAttributes: attributes)
        }
    }
}

@MainActor
final class SiteMeasureSession: ObservableObject {
    let sceneView = ARSCNView()
    @Published private(set) var points: [SIMD3<Float>] = []
    @Published var hint = "Move your phone slowly, then tap the first point."
    private var nodes: [SCNNode] = []

    var distance: Double? {
        guard points.count == 2 else { return nil }
        return Double(simd_distance(points[0], points[1]))
    }

    func start() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        // LiDAR devices: scene depth and mesh give far better hits on edges and walls.
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        sceneView.automaticallyUpdatesLighting = true
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func pause() { sceneView.session.pause() }

    /// Places a point where the screen tap meets the real world. Returns true when placed.
    func place(at location: CGPoint) -> Bool {
        guard let query = sceneView.raycastQuery(from: location, allowing: .estimatedPlane, alignment: .any),
              let hit = sceneView.session.raycast(query).first else {
            hint = "Couldn't find a surface there. Move closer and try again."
            return false
        }
        if points.count == 2 { reset() }
        let position = SIMD3<Float>(hit.worldTransform.columns.3.x, hit.worldTransform.columns.3.y, hit.worldTransform.columns.3.z)
        points.append(position)
        let marker = SCNNode(geometry: SCNSphere(radius: 0.008))
        marker.geometry?.firstMaterial?.diffuse.contents = UIColor.systemYellow
        marker.geometry?.firstMaterial?.lightingModel = .constant
        marker.simdPosition = position
        sceneView.scene.rootNode.addChildNode(marker)
        nodes.append(marker)
        if points.count == 2 {
            let line = SCNGeometry(sources: [SCNGeometrySource(vertices: points.map { SCNVector3($0) })],
                                   elements: [SCNGeometryElement(indices: [Int32(0), 1], primitiveType: .line)])
            line.firstMaterial?.diffuse.contents = UIColor.systemYellow
            line.firstMaterial?.lightingModel = .constant
            let lineNode = SCNNode(geometry: line)
            sceneView.scene.rootNode.addChildNode(lineNode)
            nodes.append(lineNode)
            hint = "Save to add this to the job, or tap to measure again."
        } else {
            hint = "Now tap the second point."
        }
        return true
    }

    func reset() {
        nodes.forEach { $0.removeFromParentNode() }
        nodes = []
        points = []
        hint = "Tap the first point."
    }
}

private struct ARSceneRepresentable: UIViewRepresentable {
    let session: SiteMeasureSession
    let onTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> ARSCNView {
        let view = session.sceneView
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        view.accessibilityLabel = "Camera view. Tap two points to measure."
        session.start()
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) { context.coordinator.onTap = onTap }

    static func dismantleUIView(_ view: ARSCNView, coordinator: Coordinator) { view.session.pause() }

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    @MainActor
    final class Coordinator: NSObject {
        var onTap: (CGPoint) -> Void
        init(onTap: @escaping (CGPoint) -> Void) { self.onTap = onTap }
        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            onTap(gesture.location(in: gesture.view))
        }
    }
}

/// Tap two points to measure a distance on site; Save files the annotated snapshot to the job.
/// Thorbis bar (Close, Clear as words), the result large in the trade's units, and one ink
/// "Save to job" commit.
struct SiteMeasureView: View {
    /// Saves the stamped snapshot with its caption. Throwing keeps the view open with the error.
    let onSave: (UIImage, String) throws -> Void
    let onClose: () -> Void
    @StateObject private var session = SiteMeasureSession()
    @Environment(\.locale) private var locale
    @AppStorage("siteMeasureUnit") private var storedUnit = ""
    @State private var error: String?
    @State private var cameraDenied = false

    private var unit: MeasureDistanceFormatter.Unit {
        MeasureDistanceFormatter.Unit(rawValue: storedUnit) ?? .standard(for: locale)
    }
    private var unitBinding: Binding<MeasureDistanceFormatter.Unit> {
        Binding(get: { unit }, set: { storedUnit = $0.rawValue })
    }
    /// DEBUG screenshots only: a fixed sample reading over a plain ground, since the simulator has no AR.
    private var sampleMeters: Double? {
        #if DEBUG
        if PaperPreview.enabled, ProcessInfo.processInfo.arguments.contains("measure"),
           ProcessInfo.processInfo.arguments.contains("--paper-preview-media-state") { return 1.2446 }
        #endif
        return nil
    }
    private var distance: Double? { sampleMeters ?? session.distance }

    var body: some View {
        ZStack {
            if cameraDenied {
                VStack(spacing: 12) {
                    PermissionNotice(permission: .camera, purpose: "measure on site")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.canvas)
            } else if sampleMeters != nil {
                Color(white: 0.35).ignoresSafeArea()
                    .overlay { Text("SAMPLE camera view").font(Theme.font(15, weight: .medium)).foregroundStyle(.white.opacity(0.7)) }
            } else {
                ARSceneRepresentable(session: session) { point in
                    if session.place(at: point) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
                .ignoresSafeArea()
                Image(systemName: "plus").font(.system(size: 22, weight: .light)).foregroundStyle(.white)
                    .shadow(radius: 2).allowsHitTesting(false).accessibilityHidden(true)
            }
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button("Close") { session.pause(); onClose() }
                        .buttonStyle(ThorbisBarButtonStyle())
                        .accessibilityIdentifier("measure-close")
                    Spacer()
                    if !session.points.isEmpty {
                        Button("Clear") { session.reset() }
                            .buttonStyle(ThorbisBarButtonStyle())
                            .accessibilityIdentifier("measure-clear")
                    }
                }
                if let error { ErrorBanner(message: error) }
                Spacer()
                VStack(spacing: 12) {
                    if let distance {
                        Text(MeasureDistanceFormatter.format(meters: distance, unit: unit, locale: locale))
                            .font(Theme.moneyFont(.hero)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .accessibilityLabel("Distance \(MeasureDistanceFormatter.format(meters: distance, unit: unit, locale: locale))")
                            .accessibilityIdentifier("measure-result")
                        ThorbisSegmented(options: MeasureDistanceFormatter.Unit.allCases.map { ($0, $0.label) }, selection: unitBinding)
                    }
                    if !cameraDenied {
                        Text(sampleMeters != nil ? "Save to add this to the job, or tap to measure again." : session.hint)
                            .font(Theme.font(15)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    }
                    if let distance {
                        Button { save(distance) } label: {
                            Label("Save to job", systemImage: "square.and.arrow.down").inkCommit(height: 56)
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("measure-save")
                    }
                }
                .foregroundStyle(Theme.foreground)
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            }
            .padding(.horizontal, Theme.gutter).padding(.vertical, 12)
        }
        .onAppear {
            cameraDenied = [.denied, .restricted].contains(AVCaptureDevice.authorizationStatus(for: .video)) && sampleMeters == nil
        }
        .onDisappear { session.pause() }
    }

    private func save(_ distance: Double) {
        let text = MeasureDistanceFormatter.format(meters: distance, unit: unit, locale: locale)
        let snapshot = sampleMeters != nil ? UIGraphicsImageRenderer(size: CGSize(width: 600, height: 800)).image { context in
            UIColor.gray.setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
        } : session.sceneView.snapshot()
        let stamped = SiteMeasure.stamp(snapshot, text: text)
        do {
            try onSave(stamped, MeasureDistanceFormatter.caption(meters: distance, unit: unit, locale: locale))
            session.pause()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
