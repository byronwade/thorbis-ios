import AVFoundation
import CoreLocation
import EventKit
@preconcurrency import Speech
import SwiftUI
import UIKit
import UserNotifications

// MARK: - Privacy and permissions (Paper "Thorbis Mobile" 69)
//
// What the phone may use and why, with the system's current answer for each. Only permissions this
// app asks for and can read back are listed: each has a purpose string in Info.plist (project.yml /
// Thorbis/Resources/Info.plist) and a call site that requests it. Not listed: Photo library (the app
// uses the system photo picker, which needs no permission), Bluetooth (declared only because the
// card-reader SDK links it; Tap to Pay does not ask), Face ID (no status the app can read).
// A row the system has not asked about yet opens its explainer (Paper 70/71's layout) and asks
// from there; every other row opens this app's page in the system Settings, the only place an
// answer can change once given. Location's explainer keeps Paper 70's layout with this app's own
// words: the drive to the next job and the schedule map. Paper's automatic arrival is not
// something this app does, so it is not promised.

/// The system's answer for one permission, in the words the row shows.
enum DevicePermissionState: Equatable, Sendable {
    case notAsked
    case off
    case restricted
    case allowed
    case whileUsing
    case always
    case addOnly
    case quietly

    var word: String {
        switch self {
        case .notAsked: "Not asked"
        case .off: "Off"
        case .restricted: "Restricted"
        case .allowed: "Allowed"
        case .whileUsing: "While using"
        case .always: "Always"
        case .addOnly: "Add only"
        case .quietly: "Quietly"
        }
    }

    // One reading per system API. `default` covers deprecated and future cases.

    static func location(_ status: CLAuthorizationStatus) -> DevicePermissionState {
        switch status {
        case .notDetermined: .notAsked
        case .denied: .off
        case .restricted: .restricted
        case .authorizedWhenInUse: .whileUsing
        case .authorizedAlways: .always
        default: .off
        }
    }

    static func capture(_ status: AVAuthorizationStatus) -> DevicePermissionState {
        switch status {
        case .notDetermined: .notAsked
        case .denied: .off
        case .restricted: .restricted
        case .authorized: .allowed
        default: .off
        }
    }

    static func microphone(_ permission: AVAudioApplication.recordPermission) -> DevicePermissionState {
        switch permission {
        case .undetermined: .notAsked
        case .denied: .off
        case .granted: .allowed
        default: .off
        }
    }

    static func speech(_ status: SFSpeechRecognizerAuthorizationStatus) -> DevicePermissionState {
        switch status {
        case .notDetermined: .notAsked
        case .denied: .off
        case .restricted: .restricted
        case .authorized: .allowed
        default: .off
        }
    }

    static func calendar(_ status: EKAuthorizationStatus) -> DevicePermissionState {
        switch status {
        case .notDetermined: .notAsked
        case .denied: .off
        case .restricted: .restricted
        case .writeOnly: .addOnly
        case .fullAccess: .allowed
        default: .off
        }
    }

    static func notifications(_ status: UNAuthorizationStatus) -> DevicePermissionState {
        switch status {
        case .notDetermined: .notAsked
        case .denied: .off
        case .authorized, .ephemeral: .allowed
        case .provisional: .quietly
        default: .off
        }
    }
}

/// One row of Device access: what it is, why the app uses it, the system's answer.
struct DevicePermissionRow: Identifiable, Equatable, Sendable {
    let id: String
    let symbol: String
    let title: String
    let purpose: String
    let state: DevicePermissionState

    /// The rows in Paper's order, purposes trimmed from the Info.plist purpose strings.
    static func rows(location: DevicePermissionState, camera: DevicePermissionState,
                     notifications: DevicePermissionState, microphone: DevicePermissionState,
                     speech: DevicePermissionState, calendar: DevicePermissionState) -> [DevicePermissionRow] {
        [
            DevicePermissionRow(id: "location", symbol: "location", title: "Location",
                                purpose: "Schedule map, drive time and card payments", state: location),
            DevicePermissionRow(id: "camera", symbol: "camera", title: "Camera",
                                purpose: "Job photos and data plate scans", state: camera),
            DevicePermissionRow(id: "notifications", symbol: "bell", title: "Notifications",
                                purpose: "New jobs and schedule changes", state: notifications),
            DevicePermissionRow(id: "microphone", symbol: "mic", title: "Microphone",
                                purpose: "Dictating notes and recording job videos", state: microphone),
            DevicePermissionRow(id: "speech", symbol: "waveform", title: "Speech recognition",
                                purpose: "Turning what you say into note text", state: speech),
            DevicePermissionRow(id: "calendar", symbol: "calendar", title: "Calendar",
                                purpose: "Adding a visit to your calendar when you ask", state: calendar),
        ]
    }
}

/// 69 · Privacy and permissions. Push it from Account and data (Your data) with
/// `.thorbisBackButton()`; needs no environment objects.
struct PrivacyPermissionsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var rows: [DevicePermissionRow] = []
    /// The explainer shown before the system asks (Paper 71).
    @State private var primer: PermissionPrimer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AccountPageTitle(title: "Privacy and permissions",
                                 subtitle: "Every permission is optional. Thorbis keeps working without them — you only lose the feature described.")

                AccountGroup(title: "Device access", count: rows.isEmpty ? nil : "\(rows.count)") {
                    ForEach(rows) { row in
                        if row.id != rows.first?.id { WellDivider(leading: AccountRow<EmptyView>.dividerInset) }
                        Button { tapped(row) } label: {
                            AccountRow(glyph: row.id == "notifications" ? .setBell : nil, symbol: row.symbol,
                                       title: row.title, subtitle: row.purpose, value: row.state.word)
                        }
                            .buttonStyle(RowPressStyle())
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(row.title), \(row.purpose)")
                            .accessibilityValue(row.state.word)
                            .accessibilityHint(asksHere(row) ? "Explains why, then asks" : "Opens this app's settings")
                            .accessibilityIdentifier("privacy-permission-\(row.id)")
                    }
                }
                .padding(.top, 22)
            }
            .padding(.horizontal, PaperCardMetrics.margin).padding(.bottom, 44)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await read() }
        .fullScreenCover(item: $primer) { shown in
            PermissionPrimerView(primer: shown) {
                primer = nil
                Task { await read() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from the system's Settings: show what the person changed there.
            if phase == .active { Task { await read() } }
        }
    }

    private func read() async {
        let notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        rows = DevicePermissionRow.rows(
            location: .location(CLLocationManager().authorizationStatus),
            camera: .capture(AVCaptureDevice.authorizationStatus(for: .video)),
            notifications: .notifications(notifications),
            microphone: .microphone(AVAudioApplication.shared.recordPermission),
            speech: .speech(SFSpeechRecognizer.authorizationStatus()),
            calendar: .calendar(EKEventStore.authorizationStatus(for: .event))
        )
    }

    private func asksHere(_ row: DevicePermissionRow) -> Bool {
        row.state == .notAsked && PermissionPrimer.primer(for: row.id) != nil
    }

    private func tapped(_ row: DevicePermissionRow) {
        if row.state == .notAsked, let explain = PermissionPrimer.primer(for: row.id) {
            primer = explain
        } else {
            openSettings()
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

// MARK: - Before the system asks (Paper 70 / 71)

/// The words shown before a system permission prompt: what it is for, what the person gets, and
/// the two answers. Only permissions this app asks for have one.
struct PermissionPrimer: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case location, notifications, camera, dictation, calendar }

    let kind: Kind
    let symbol: String
    let title: String
    let detail: String
    let points: [String]
    let allow: String
    let later: String

    var id: String { kind.rawValue }

    /// Paper 70's layout. The words are what Location is used for here: the Next stop card's drive
    /// time (NextStopETA) and the blue dot on the schedule map, both only while Thorbis is open
    /// (When In Use is the only access the app asks for).
    static let location = PermissionPrimer(
        kind: .location, symbol: "location", title: "Location while you work",
        detail: "Used only while Thorbis is open, to show the drive to your next job and where you are on the schedule map.",
        points: ["Drive time to your next job", "Your position on the schedule map", "Never used when Thorbis is closed"],
        allow: "Allow while using", later: "Not now")

    /// Paper 71, with the points this app can keep (alerts are on or off for the whole phone).
    static let notifications = PermissionPrimer(
        kind: .notifications, symbol: "bell", title: "Know when plans change",
        detail: "Dispatch moves jobs during the day. Without alerts you'll only see it next time you open the app.",
        points: ["New jobs", "Schedule changes", "The morning digest, if you turn it on"],
        allow: "Turn on alerts", later: "Maybe later")

    static let camera = PermissionPrimer(
        kind: .camera, symbol: "camera", title: "Camera for the job",
        detail: "Used only while the camera is open, to add photos to the job you are working on.",
        points: ["Before and after photos", "Data plate and receipt scans", "Barcodes on parts"],
        allow: "Allow camera", later: "Not now")

    static let dictation = PermissionPrimer(
        kind: .dictation, symbol: "mic", title: "Talk instead of typing",
        detail: "Used only while you dictate or record. Thorbis turns what you say into text, on this iPhone when it can.",
        points: ["Dictate a job note", "Dictate a photo caption", "Record a video clip for a job"],
        allow: "Allow microphone", later: "Not now")

    static let calendar = PermissionPrimer(
        kind: .calendar, symbol: "calendar", title: "Visits on your calendar",
        detail: "Thorbis adds a scheduled visit to your calendar when you ask. It never reads your other events.",
        points: ["Add a visit with its time and address", "Add only: nothing is read", "Only when you tap Add to Calendar"],
        allow: "Allow adding events", later: "Not now")

    /// The explainer for a Device access row, by the row's id.
    static func primer(for rowID: String) -> PermissionPrimer? {
        switch rowID {
        case "location": return .location
        case "notifications": return .notifications
        case "camera": return .camera
        case "microphone", "speech": return .dictation
        case "calendar": return .calendar
        default: return nil
        }
    }

    /// Shows the system's own prompt. Nothing is returned: the screen reads the answer back.
    nonisolated static func request(_ kind: Kind) async {
        switch kind {
        case .location:
            // The same request the Next stop card makes: a When In Use session and one read of
            // live updates bring up the system prompt. Done as soon as there is an answer.
            let session = CLServiceSession(authorization: .whenInUse)
            defer { session.invalidate() }
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    do {
                        for try await update in CLLocationUpdate.liveUpdates() {
                            if update.location != nil || update.authorizationDenied
                                || update.authorizationDeniedGlobally || update.authorizationRestricted { return }
                        }
                    } catch {}
                }
                group.addTask {
                    // The answer itself; a fix can take longer than the person does.
                    for _ in 0..<240 {
                        if CLLocationManager().authorizationStatus != .notDetermined { return }
                        try? await Task.sleep(for: .milliseconds(250))
                        if Task.isCancelled { return }
                    }
                }
                _ = await group.next()
                group.cancelAll()
            }
        case .notifications:
            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            let status = await center.notificationSettings().authorizationStatus
            if status == .authorized || status == .provisional || status == .ephemeral {
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            }
        case .camera:
            _ = await AVCaptureDevice.requestAccess(for: .video)
        case .dictation:
            let speech: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { done in
                SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0) }
            }
            _ = speech
            _ = await AVAudioApplication.requestRecordPermission()
        case .calendar:
            _ = await CalendarAccess.requestAddOnly()
        }
    }
}

/// Paper 70/71: the glyph, a 34 Bold promise, one muted line, a card of what you get, then the
/// brand commit and a quiet "Not now". The commit shows the system prompt and closes.
struct PermissionPrimerView: View {
    let primer: PermissionPrimer
    /// The system has answered (after the commit), or "Not now" when `later` is not given.
    let done: () -> Void
    /// "Not now", for a caller that needs to tell it from an answer.
    var later: (() -> Void)? = nil
    @State private var asking = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: primer.symbol).font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .frame(height: 28)
                        .accessibilityHidden(true)
                    Text(primer.title)
                        .font(Theme.font(34, weight: .bold)).tracking(-0.85)
                        .foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 20)
                        .accessibilityAddTraits(.isHeader)
                    Text(primer.detail)
                        .font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.top, 96)
                VStack(spacing: 0) {
                    ForEach(Array(primer.points.enumerated()), id: \.offset) { index, point in
                        if index > 0 { WellDivider(leading: 46) }
                        HStack(spacing: 0) {
                            Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.muted)
                                .frame(width: 30, alignment: .leading)
                                .accessibilityHidden(true)
                            Text(point).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .frame(minHeight: 56)
                    }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: 10) {
                Button {
                    guard !asking else { return }
                    asking = true
                    Task {
                        await PermissionPrimer.request(primer.kind)
                        asking = false
                        done()
                    }
                } label: {
                    Text(primer.allow).inkCommit()
                }
                .buttonStyle(PressStyle())
                .disabled(asking)
                .accessibilityIdentifier("permission-primer-allow")
                Button { (later ?? done)() } label: {
                    Text(primer.later)
                        .font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.fill, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("permission-primer-later")
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }
}

// MARK: - Before a first-run system prompt (Paper 70 / 71)

/// How an explainer shown from outside a screen ended.
private enum PermissionPrimerAnswer: Sendable { case asked, later, unseen }

/// Hosts the explainer over whatever is on screen. Closed by its two buttons; if something else
/// takes it down, it counts as not seen.
private final class PermissionPrimerHost: UIHostingController<PermissionPrimerView> {
    var closed: ((PermissionPrimerAnswer) -> Void)?

    func finish(_ answer: PermissionPrimerAnswer) {
        guard let closed else { return }
        self.closed = nil
        guard presentingViewController != nil else { closed(answer); return }
        dismiss(animated: true) { closed(answer) }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed, let closed {
            self.closed = nil
            closed(.unseen)
        }
    }
}

/// Shows a permission's explainer before the system prompt at the places that ask on their own:
/// the first signed-in launch (notifications), the Next stop card (location) and the join flow's
/// Turn on. These have no screen of their own to present from, so the explainer goes over the
/// front window.
@MainActor
enum PermissionPrimerPresenter {
    private static var showing = false

    private static func laterKey(_ kind: PermissionPrimer.Kind) -> String {
        "thorbis.permission.primer.later.\(kind.rawValue)"
    }

    /// True when the caller may go on: the person tapped the commit and the system has asked, or
    /// this is a design-preview run (no explainer; the caller asks the system as it always has).
    /// False when they said "Not now" or the explainer could not be shown. After "Not now" an
    /// `automatic` ask stays quiet on later launches; Privacy and permissions can still ask.
    @discardableResult
    static func ask(_ primer: PermissionPrimer, automatic: Bool = true) async -> Bool {
        #if DEBUG
        if PaperPreview.enabled { return true }
        #endif
        let defaults = UserDefaults.standard
        guard !showing, !(automatic && defaults.bool(forKey: laterKey(primer.kind))) else { return false }
        showing = true
        defer { showing = false }
        // A sign-in, the What's new sheet or setup may be coming up: let them land, then go on top.
        if automatic { try? await Task.sleep(for: .milliseconds(1200)) }
        var top = frontController()
        var tries = 0
        while tries < 20, top == nil || top?.isBeingPresented == true || top?.isBeingDismissed == true {
            try? await Task.sleep(for: .milliseconds(300))
            top = frontController()
            tries += 1
        }
        guard let top, !top.isBeingPresented, !top.isBeingDismissed else { return false }
        let host = PermissionPrimerHost(rootView: PermissionPrimerView(primer: primer, done: {}))
        host.rootView = PermissionPrimerView(primer: primer,
                                             done: { [weak host] in host?.finish(.asked) },
                                             later: { [weak host] in host?.finish(.later) })
        host.modalPresentationStyle = .fullScreen
        host.isModalInPresentation = true
        let answer: PermissionPrimerAnswer = await withCheckedContinuation { continuation in
            host.closed = { continuation.resume(returning: $0) }
            top.present(host, animated: true)
            // UIKit refused (another presentation started first): nothing was shown.
            if host.presentingViewController == nil { host.finish(.unseen) }
        }
        if answer == .later { defaults.set(true, forKey: laterKey(primer.kind)) }
        return answer == .asked
    }

    /// The topmost view controller of the window in front, or nil while the app is not active.
    private static func frontController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.keyWindow?.rootViewController else { return nil }
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }
}
