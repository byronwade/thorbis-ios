import SwiftUI
import UIKit

// First-run and edge states (2026-10-31 redesign): one way to say "nothing here", "this went
// wrong", "this is off in Settings" and "loading", used everywhere so they read the same.
//
// Phase 4 (Linear style): a soft tinted glyph, a semibold one-line title, one secondary sentence
// and one Thorbis action.
// - Empty: what is empty, the one action that fills it, the place's soft tinted glyph.
// - Error: what went wrong and the way out, in a calm rounded strip. Never a toast.
// - Permission: what is off, why Thorbis needs it, and Open Settings.
// - Loading: rows the shape of the real ones (status-glyph circle and two bars) on a well,
//   breathing gently; still under Reduce Motion.

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

/// MA-14, Linear style (phase 4): a soft tinted glyph, a semibold title that says what is empty,
/// an optional quieter sentence for a reason the person needs ("Your role can't assign jobs"), and
/// the one action that fills it. `tint` is the place's mark colour (as More shows it); nil is a
/// neutral grey. `prominent` draws the action in ink, for a place's root list where it is the
/// screen's one action; inside a record (where the bar already holds the ink commit) it stays a
/// quiet capsule (golden rule 8).
struct PaperEmptyState: View {
    let symbol: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var tint: Color? = nil
    var prominent = false
    var action: (() -> Void)? = nil
    @ScaledMetric(relativeTo: .title3) private var mark: CGFloat = 48

    init(symbol: String, title: String, message: String? = nil, actionTitle: String? = nil,
         tint: Color? = nil, prominent: Bool = false, action: (() -> Void)? = nil) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.tint = tint
        self.prominent = prominent
        self.action = action
    }

    var body: some View {
        VStack(spacing: 0) {
            EmptyGlyph(symbol: symbol, tint: tint, size: mark)
                .padding(.bottom, 14)
            Text(title)
                .font(Theme.font(17, weight: .medium))
                .foregroundStyle(Theme.foreground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let message, !message.isEmpty {
                Text(message)
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(Theme.font(15, weight: .medium)).foregroundStyle(prominent ? Theme.onInk : Theme.foreground)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18).padding(.vertical, 8).frame(minHeight: 40)
                        .background(prominent ? Theme.ink : Theme.fill, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .padding(.top, 16)
                .accessibilityIdentifier("empty-state-action")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40).padding(.horizontal, Theme.gutter)
        .accessibilityElement(children: .contain)
    }
}

/// The soft glyph of an empty or calm state: the symbol in its hue on a pale rounded square of the
/// same hue. Decorative; the words carry the meaning.
struct EmptyGlyph: View {
    let symbol: String
    var tint: Color? = nil
    var size: CGFloat = 48

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(tint ?? Theme.muted)
            .frame(width: size, height: size)
            .background((tint ?? Theme.muted).opacity(tint == nil ? 0.12 : 0.13),
                        in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .strokeBorder((tint ?? Theme.muted).opacity(0.12)))
            .accessibilityHidden(true)
    }
}

/// The calm strip behind a banner (offline, waiting to sync, a failed read): a rounded `fill`
/// ground, the glyph in a small tinted circle, then the words. Shared by `ErrorBanner` and the
/// saved-work `OfflineBanner` so every in-between state reads the same.
struct BannerGlyph: View {
    let symbol: String
    var tint: Color = Theme.muted
    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 26

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: Circle())
            .accessibilityHidden(true)
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
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                                                  : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
        layout {
            HStack(alignment: .center, spacing: 10) {
                BannerGlyph(symbol: symbol, tint: tint)
                Text(message).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let action {
                Button {
                    Task { running = true; await action.run(); running = false }
                } label: {
                    Text(action.title).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 12).frame(minHeight: 32)
                        .background(Theme.selectedSegment, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.border))
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .disabled(running)
                .fixedSize()
                .padding(.leading, stacked ? 36 : 0)
            }
        }
        .padding(.leading, 10).padding(.trailing, 12).padding(.vertical, action == nil || stacked ? 9 : 2)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
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

/// MA-13, phase 4: the shape of what is coming, matching the redesigned rows: a status-glyph
/// circle, a title bar and a supporting bar (and a short "when" bar for schedule rows). Rows only,
/// no ground, so they drop into a card or a well; `SkeletonList` puts them on a well under a
/// header bar. They breathe slowly; under Reduce Motion they hold still. VoiceOver hears one
/// "Loading".
struct SkeletonRows: View {
    var count = 6
    /// A third, short bar for the who-and-when line of a schedule row.
    var leading = true
    /// Zero when the parent already pads to the gutter.
    var inset: CGFloat = Theme.gutter
    /// Inset hairlines between rows, as on a well.
    var dividers = false
    @ScaledMetric(relativeTo: .body) private var glyph: CGFloat = 16

    var body: some View {
        SkeletonPulse {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<count, id: \.self) { index in
                    HStack(alignment: .top, spacing: 12) {
                        Circle().fill(Theme.fill).frame(width: glyph, height: glyph).padding(.top, 1)
                        VStack(alignment: .leading, spacing: 8) {
                            Capsule().fill(Theme.fill).frame(width: Self.titleWidth(index), height: 12)
                            Capsule().fill(Theme.fill.opacity(0.75)).frame(width: Self.lineWidth(index), height: 10)
                            if leading {
                                Capsule().fill(Theme.fill.opacity(0.6)).frame(width: 72, height: 9)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, inset)
                    .padding(.vertical, 13)
                    .frame(minHeight: leading ? 70 : 56, alignment: .top)
                    .overlay(alignment: .bottom) {
                        if dividers && index < count - 1 { WellDivider(leading: inset + glyph + 12) }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }

    private static func titleWidth(_ index: Int) -> CGFloat { [170, 136, 188, 150, 120, 164][index % 6] }
    private static func lineWidth(_ index: Int) -> CGFloat { [120, 150, 104, 132, 158, 112][index % 6] }
}

/// A slow breath (opacity 1 → 0.55) for loading placeholders. Off under Reduce Motion.
struct SkeletonPulse<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        content
            .opacity(reduceMotion ? 1 : (dim ? 0.55 : 1))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
            }
            .onChange(of: reduceMotion) { _, still in
                if still { dim = false }
            }
    }
}

/// A loading list the way the loaded one draws: a header-sized bar over one well of skeleton rows
/// with inset hairlines. No side margin; the caller pads it like its `WellSection`s.
struct SkeletonList: View {
    var count = 5
    var leading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SkeletonPulse {
                Capsule().fill(Theme.fill).frame(width: 84, height: 11)
                    .frame(minHeight: 30, alignment: .leading)
                    .padding(.horizontal, 4).padding(.top, 12).padding(.bottom, 4)
            }
            Well { SkeletonRows(count: count, leading: leading, inset: PaperCardMetrics.inset, dividers: true) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

/// A loading section for screens whose content is a stack of sections: `SkeletonList` geometry.
struct SkeletonSection: View {
    var rows = 3
    var leading = false

    var body: some View { SkeletonList(count: rows, leading: leading) }
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
        .background(Theme.canvas)
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
