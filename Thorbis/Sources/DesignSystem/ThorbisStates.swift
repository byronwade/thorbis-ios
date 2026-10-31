import SwiftUI
import UIKit

// First-run and edge states (2026-10-31 redesign): one way to say "nothing here", "this went
// wrong", "this is off in Settings" and "loading", used everywhere so they read the same.
//
// - Empty: one line that says what is empty, the one action that fills it, a neutral glyph.
// - Error: what went wrong and the way out, in a quiet field-coloured strip. Never a toast.
// - Permission: what is off, why Thorbis needs it, and Open Settings.
// - Loading: rows the shape of the real ones (SkeletonRows / SkeletonSection), static.

// MARK: - Error copy

/// The kind of failure, so a banner can pick its glyph and the words name the exit.
enum ProblemKind: Equatable {
    /// No answer from the server: no signal, DNS, timeout.
    case offline
    /// The server answered with an outage or rate limit.
    case server
    /// The account may not see or change this.
    case forbidden
    /// The sign-in ended; the person signs in again.
    case expired
    /// Anything else, with the server's own words.
    case other

    init(_ error: Error) {
        if error.isConnectivityFailure { self = .offline; return }
        guard let problem = error as? Problem, let status = problem.status else { self = .other; return }
        switch status {
        case 401: self = .expired
        case 403: self = .forbidden
        case 429, 500...: self = .server
        default: self = .other
        }
    }

    var symbol: String {
        switch self {
        case .offline: "wifi.slash"
        case .server: "exclamationmark.icloud"
        case .forbidden: "lock"
        case .expired: "person.crop.circle.badge.exclamationmark"
        case .other: "exclamationmark.triangle"
        }
    }
}

extension Error {
    /// Plain words for a failed read or change: what went wrong and the way out.
    /// `subject` names what was being opened ("jobs", "this invoice") for the access line.
    /// A server's own explanation (a conflict, a validation) is passed through unchanged.
    func plainMessage(subject: String? = nil) -> String {
        let problem = self as? Problem
        switch ProblemKind(self) {
        case .offline:
            return problem?.detail ?? "No connection. Check your signal and try again."
        case .expired:
            // At sign-in a 401 carries the reason ("Invalid email or password"); keep it.
            return problem?.detail ?? "Your session expired. Sign in again."
        case .forbidden:
            return subject.map { "Ask your office for access to \($0)." } ?? "Your role can’t open this. Ask your office for access."
        case .server:
            if problem?.status == 429 { return "Too many tries. Wait a minute, then try again." }
            return "Thorbis couldn’t answer just now. Try again in a minute."
        case .other:
            if let problem {
                if let detail = problem.detail, !detail.isEmpty { return detail }
                if let title = problem.title, !title.isEmpty, !title.hasPrefix("HTTP ") { return title }
                if problem.status == 404 { return "This was moved or deleted. Go back and refresh." }
                return "That didn’t go through. Try again."
            }
            return localizedDescription
        }
    }
}

// MARK: - Empty

/// MA-14 (2026-10-31): one line that says what is empty, and the one action that fills it.
/// A neutral glyph, no illustration. `message` is an optional quieter second line for a
/// reason the person needs ("Your role can't assign jobs"), never filler.
struct PaperEmptyState: View {
    let symbol: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Theme.muted)
                .frame(width: 44, height: 44)
                .background(Theme.fill, in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(Theme.font(16, weight: .medium))
                .foregroundStyle(Theme.foreground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let message, !message.isEmpty {
                Text(message)
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 18).frame(minHeight: 44)
                        .background(Theme.fill, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .padding(.top, 2)
                .accessibilityIdentifier("empty-state-action")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36).padding(.horizontal, Theme.gutter)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Errors and permissions

/// MA-15: errors name the exit. The words stay body colour, only the glyph is tinted, and when
/// the screen can do something about it the strip offers one quiet action ("Try again",
/// "Open Settings", "Sign in"). It sits where the problem is, never as a toast.
struct ErrorBanner: View {
    struct Action {
        let title: String
        let run: () async -> Void
    }

    let message: String
    var symbol: String = "exclamationmark.triangle"
    var tint: Color = Theme.warning
    var action: Action? = nil
    /// Side margin; zero when the parent already pads its content.
    var outer: CGFloat = Theme.gutter
    @State private var running = false
    @Environment(\.dynamicTypeSize) private var typeSize

    init(message: String, symbol: String = "exclamationmark.triangle", tint: Color = Theme.warning,
         action: Action? = nil, outer: CGFloat = Theme.gutter) {
        self.message = message
        self.symbol = symbol
        self.tint = tint
        self.action = action
        self.outer = outer
    }

    /// The common case: a read failed and the screen can try it again.
    init(message: String, retry: (() async -> Void)?) {
        self.init(message: message, action: retry.map { Action(title: String(localized: "Try again"), run: $0) })
    }

    /// From the error itself, so the glyph and the words match what went wrong.
    init(error: Error, subject: String? = nil, retry: (() async -> Void)? = nil) {
        let kind = ProblemKind(error)
        self.init(message: error.plainMessage(subject: subject), symbol: kind.symbol,
                  tint: kind == .forbidden ? Theme.muted : Theme.warning,
                  // Retrying a refused permission only refuses again.
                  action: kind == .forbidden ? nil : retry.map { Action(title: String(localized: "Try again"), run: $0) })
    }

    var body: some View {
        // A long message keeps the full width and puts its action underneath.
        let stacked = typeSize.isAccessibilitySize || (action != nil && message.count > 64)
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                                  : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
        layout {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(message).font(Theme.font(15)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let action {
                Button {
                    Task { running = true; await action.run(); running = false }
                } label: {
                    Text(action.title).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                        .underline(false)
                        .padding(.horizontal, 12).frame(minHeight: 32)
                        .background(Theme.card, in: Capsule())
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .disabled(running)
                .fixedSize()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, action == nil ? 12 : 2)
        .padding(.top, stacked && action != nil ? 10 : 0)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .padding(.horizontal, outer).padding(.top, 8)
        .accessibilityElement(children: .contain)
    }

    /// The same strip without its own side margin, for parents that already pad.
    func flush() -> ErrorBanner { var copy = self; copy.outer = 0; return copy }
}

/// What a person turned off in iOS Settings, and why Thorbis asks for it.
enum DevicePermission {
    case camera, microphone, speech, location, notifications

    var name: String {
        switch self {
        case .camera: String(localized: "Camera")
        case .microphone: String(localized: "Microphone")
        case .speech: String(localized: "Speech Recognition")
        case .location: String(localized: "Location")
        case .notifications: String(localized: "Notifications")
        }
    }

    var symbol: String {
        switch self {
        case .camera: "camera"
        case .microphone, .speech: "mic.slash"
        case .location: "location.slash"
        case .notifications: "bell.slash"
        }
    }

    var settingsURL: URL? {
        URL(string: self == .notifications ? UIApplication.openNotificationSettingsURLString : UIApplication.openSettingsURLString)
    }
}

/// "Camera is off for Thorbis. Turn it on in Settings to add photos." with Open Settings.
struct PermissionNotice: View {
    let permission: DevicePermission
    /// What it is for, finishing "Turn it on in Settings to …".
    let purpose: String
    /// Overrides the generated sentence when two permissions are involved (dictation).
    var message: String? = nil
    var outer: CGFloat = Theme.gutter
    @Environment(\.openURL) private var openURL

    var body: some View {
        ErrorBanner(message: message ?? (permission == .notifications
                        ? String(localized: "Notifications are off for Thorbis. Turn them on in Settings to \(purpose).")
                        : String(localized: "\(permission.name) is off for Thorbis. Turn it on in Settings to \(purpose).")),
                    symbol: permission.symbol, tint: Theme.muted,
                    action: permission.settingsURL.map { url in
                        ErrorBanner.Action(title: String(localized: "Open Settings")) { openURL(url) }
                    }, outer: outer)
        .accessibilityIdentifier("permission-notice")
    }
}

// MARK: - Loading

/// MA-13: the shape of what is coming. Rows the size of `PaperListRow` (a time column, a 16pt
/// title, one supporting line, a status word), static with no shimmer, so Reduce Motion needs
/// nothing different; VoiceOver hears one "Loading" instead.
struct SkeletonRows: View {
    var count = 6
    /// A leading time or date column, like a schedule row.
    var leading = true
    /// Zero when the parent already pads to the gutter.
    var inset: CGFloat = Theme.gutter
    @ScaledMetric(relativeTo: .subheadline) private var column: CGFloat = 82

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                HStack(alignment: .top, spacing: 14) {
                    if leading {
                        Capsule().fill(Theme.fill).frame(width: 52, height: 12)
                            .frame(width: column, alignment: .leading)
                            .padding(.top, 3)
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        Capsule().fill(Theme.fill).frame(width: Self.titleWidth(index), height: 13)
                        Capsule().fill(Theme.fill.opacity(0.7)).frame(width: Self.lineWidth(index), height: 11)
                    }
                    .padding(.top, 2)
                    Spacer(minLength: 0)
                    Capsule().fill(Theme.fill.opacity(0.7)).frame(width: 54, height: 11).padding(.top, 3)
                }
                .padding(.vertical, 12)
                .frame(minHeight: 60, alignment: .top)
            }
        }
        .padding(.horizontal, inset)
        .padding(.top, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }

    private static func titleWidth(_ index: Int) -> CGFloat { [170, 136, 188, 150, 120, 164][index % 6] }
    private static func lineWidth(_ index: Int) -> CGFloat { [120, 150, 104, 132, 158, 112][index % 6] }
}

/// A loading section: a label-sized bar above one white panel of skeleton rows, the same
/// geometry as `PaperSection`, for screens whose content is a stack of sections.
struct SkeletonSection: View {
    var rows = 3
    var leading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(Theme.fill).frame(width: 84, height: 11)
                .frame(minHeight: 28, alignment: .leading)
                .padding(.horizontal, 4).padding(.bottom, 4)
            PaperCard { SkeletonRows(count: rows, leading: leading, inset: PaperCardMetrics.inset) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

/// The wait between launch (or sign-out) and the first screen: the mark on the cream ground and
/// one line saying what is happening. Nothing else to read, so nothing else is drawn.
struct SessionLoadingView: View {
    let message: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 18) {
            Image("ThorbisMark")
                .resizable().scaledToFit()
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            Text(message)
                .font(Theme.font(15)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            ProgressView().tint(Theme.muted).opacity(reduceMotion ? 0 : 1)
                .accessibilityHidden(true)
        }
        .padding(Theme.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("session-loading")
    }
}

/// "Step 2 of 4" above a first-run screen's title.
struct StepLabel: View {
    let step: Int
    let of: Int

    var body: some View {
        Text("Step \(step) of \(of)")
            .font(Theme.font(13, weight: .medium)).monospacedDigit()
            .foregroundStyle(Theme.muted)
            .accessibilityLabel("Step \(step) of \(of)")
    }
}
