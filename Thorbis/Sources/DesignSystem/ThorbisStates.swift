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

/// The one empty-state grammar, centred, in three sizes that share one shape (mark, title,
/// sentence, one action):
/// - a screen with nothing in it (`prominent`, Paper 19 "Today (empty state)"): a 56pt circle with
///   a 26pt muted glyph, a 22 Bold title 16 under it, one 15/20 muted sentence 6 under that, and
///   the action 20 under that as Paper's tinted pill (48pt, brand at 24%, 16 Semibold brand text);
/// - a screen that failed or is locked (`problem`, Paper 73C "Couldn't load" / 73D "No access"): a
///   64pt circle (warning surface for a failure, neutral for a lock), 22 Bold title, 16/22 muted
///   sentence, 12 between parts, and the action 24 under as the solid brand pill, full width, 50pt;
/// - inside a card or a section of a record (neither flag): the same shape one step down (48pt
///   circle, 17 Semibold title, 15 sentence) with Paper 48A's small tinted pill (44pt, 14 Semibold).
/// The title is sentence case with no full stop; the sentence ends with one. `tint` is the place's
/// mark colour; nil is Paper's neutral circle.
struct PaperEmptyState: View {
    let symbol: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var tint: Color? = nil
    var prominent = false
    /// Paper 73C / 73D: the screen's own failed or locked state.
    var problem = false
    var action: (() -> Void)? = nil
    @ScaledMetric(relativeTo: .title3) private var scale: CGFloat = 1

    init(symbol: String, title: String, message: String? = nil, actionTitle: String? = nil,
         tint: Color? = nil, prominent: Bool = false, problem: Bool = false, action: (() -> Void)? = nil) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.tint = tint
        self.prominent = prominent || problem
        self.problem = problem
        self.action = action
    }

    private var markSize: CGFloat { (problem ? 64 : prominent ? 56 : 48) * min(scale, 1.5) }

    var body: some View {
        VStack(spacing: 0) {
            EmptyGlyph(symbol: symbol, tint: tint, size: markSize)
                .padding(.bottom, problem ? 12 : prominent ? 16 : 14)
            Text(title)
                .font(prominent ? Theme.font(22, weight: .bold) : Theme.font(17, weight: .semibold))
                .tracking(prominent ? -0.44 : 0)
                .foregroundStyle(Theme.foreground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let message, !message.isEmpty {
                Text(message)
                    .font(Theme.font(problem ? 16 : 15)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 310)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, problem ? 12 : prominent ? 6 : 4)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    if problem {
                        PaperPillLabel(title: actionTitle, height: 50)
                    } else if prominent {
                        PaperPillLabel(title: actionTitle, height: 48, tinted: true, fills: false)
                    } else {
                        Text(actionTitle)
                            .font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.brandText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 44)
                            .background(Theme.brandTint, in: Capsule())
                            .contentShape(Capsule())
                    }
                }
                .buttonStyle(PressStyle())
                .padding(.top, problem ? 24 : prominent ? 20 : 16)
                .accessibilityIdentifier("empty-state-action")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40).padding(.horizontal, problem ? 40 : Theme.gutter)
        .accessibilityElement(children: .contain)
    }
}

/// The glyph of an empty, failed or locked state (Paper 19 / 73C / 73D): the symbol on a circle.
/// With a hue the circle is that hue's pale surface; without one it is Paper's neutral circle (ink
/// at 9%, which reads on the canvas and on a card) with a muted symbol. Decorative; the words
/// carry the meaning.
struct EmptyGlyph: View {
    let symbol: String
    var tint: Color? = nil
    var size: CGFloat = 48

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .regular))
            .foregroundStyle(tint ?? Theme.muted)
            .frame(width: size, height: size)
            .background(tint.map { $0.opacity(0.16) } ?? Theme.quietFill, in: Circle())
            .accessibilityHidden(true)
    }
}

/// "Nothing here" as one line inside a card or a section that still shows its heading ("No line
/// items yet."): a 15/20 muted sentence, the same type as an empty state's sentence. A whole
/// screen or a whole section with nothing uses `PaperEmptyState`.
struct PaperInlineEmpty: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(Theme.font(15)).foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The mark that leads a banner (Paper 73 / 74: offline, waiting to sync, a failed read): an 18pt
/// glyph in the state's tone, no ground of its own; the strip behind it carries the tone.
struct BannerGlyph: View {
    let symbol: String
    var tint: Color = Theme.muted
    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 18

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.86, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Banner

/// What a banner is saying, which picks its colours (Paper 73 / 74).
enum BannerTone {
    /// Something is wrong or waiting on the person: offline, a failed read, needs review.
    case warning
    /// Something is going right: back online, sending.
    case success
    /// Neither: a locked area, a permission that is off, work saved on this phone.
    case quiet

    var ink: Color {
        switch self {
        case .warning: Theme.warning
        case .success: Theme.success
        case .quiet: Theme.foreground
        }
    }
    var ground: Color {
        switch self {
        case .warning: Theme.warningSurface
        case .success: Theme.successSurface
        case .quiet: Theme.fill
        }
    }
    /// The glyph follows the words, except on the quiet strip where it steps back.
    var glyph: Color { self == .quiet ? Theme.muted : ink }
}

/// The one banner grammar (Paper 73 "Offline pill" / 74 "Syncing pill"), used by every banner:
/// a strip on the tone's surface, radius 14, at least 44 tall, 10 above and below, 14 leading,
/// 10 trailing, 8 between parts; an 18pt glyph and the words in the tone's text colour
/// (14 Semibold); and at most one trailing 24pt pill (13 Semibold on the tone at 18%) that holds
/// a count ("3 queued") or the one way out ("Try again"). At accessibility sizes, or when the
/// words are long, the pill drops under the words so they keep the width.
struct PaperBannerStrip<Trailing: View>: View {
    let symbol: String
    let tone: BannerTone
    let text: String
    var stacked = false
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stack = stacked || typeSize.isAccessibilitySize
        let layout = stack ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                           : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        HStack(alignment: stack ? .top : .center, spacing: 8) {
            BannerGlyph(symbol: symbol, tint: tone.glyph)
            layout {
                Text(text).font(Theme.font(14, weight: .semibold)).foregroundStyle(tone.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
        }
        .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(tone.ground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// The banner's trailing pill (Paper 73 "3 queued"): 24pt, 13 Semibold, the tone at 18%.
struct BannerPill: View {
    let title: String
    let tone: BannerTone

    var body: some View {
        Text(title).font(Theme.font(13, weight: .semibold)).foregroundStyle(tone.ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 9).frame(minHeight: 24)
            .background(tone.ink.opacity(tone == .quiet ? 0.09 : 0.18), in: Capsule())
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
    /// The action's accessibility identifier, where a test finds it by one.
    var actionIdentifier: String? = nil
    /// Side margin; zero when the parent already pads its content.
    var outer: CGFloat = Theme.gutter
    @State private var running = false
    @Environment(\.dynamicTypeSize) private var typeSize

    init(message: String, symbol: String = "exclamationmark.triangle", tint: Color = Theme.warning,
         action: Action? = nil, actionIdentifier: String? = nil, outer: CGFloat = Theme.gutter) {
        self.message = message
        self.symbol = symbol
        self.tint = tint
        self.action = action
        self.actionIdentifier = actionIdentifier
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
        // Paper 73: a problem is the warning strip; a locked area or a permission that is off (the
        // muted tint) is the quiet one. A long message keeps the full width, its action underneath.
        let tone: BannerTone = tint == Theme.muted ? .quiet : .warning
        PaperBannerStrip(symbol: symbol, tone: tone, text: message, stacked: action != nil && message.count > 64) {
            if let action {
                Button {
                    Task { running = true; await action.run(); running = false }
                } label: {
                    // The pill is Paper's 24pt; the touch target around it is 44.
                    BannerPill(title: action.title, tone: tone)
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        .padding(.vertical, -10)
                }
                .buttonStyle(PressStyle())
                .disabled(running)
                .fixedSize()
                .modifier(BannerActionIdentifier(identifier: actionIdentifier))
            }
        }
        .padding(.horizontal, outer).padding(.top, 8)
        .accessibilityElement(children: .contain)
    }

    /// The same strip without its own side margin, for parents that already pad.
    func flush() -> ErrorBanner { var copy = self; copy.outer = 0; return copy }
}

/// Sets an accessibility identifier only when there is one, so a control without one is still
/// found by its label.
private struct BannerActionIdentifier: ViewModifier {
    let identifier: String?
    func body(content: Content) -> some View {
        if let identifier { content.accessibilityIdentifier(identifier) } else { content }
    }
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

    var body: some View {
        // Paper 73E: each row is a 14pt title bar over one or two 12pt bars, 8 apart, 18 above and
        // below, in the quiet accent tone. No leading mark.
        SkeletonPulse {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<count, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        Capsule().fill(Theme.sidebarAccent).frame(width: Self.titleWidth(index), height: 14)
                        Capsule().fill(Theme.sidebarAccent).frame(width: Self.lineWidth(index), height: 12)
                        if leading {
                            Capsule().fill(Theme.sidebarAccent).frame(width: Self.tailWidth(index), height: 12)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, inset)
                    .padding(.vertical, 18)
                    .overlay(alignment: .bottom) {
                        if dividers && index < count - 1 { WellDivider(leading: inset) }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }

    private static func titleWidth(_ index: Int) -> CGFloat { [180, 150, 200, 160, 130, 170][index % 6] }
    private static func lineWidth(_ index: Int) -> CGFloat { [250, 270, 230, 240, 260, 220][index % 6] }
    private static func tailWidth(_ index: Int) -> CGFloat { [120, 100, 140, 110, 130, 90][index % 6] }
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
                Capsule().fill(Theme.sidebarAccent).frame(width: 84, height: 12)
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

/// Waiting on one thing that is not a list (a document being prepared, a check running): a small
/// spinner and what is happening, in 14pt muted words, centred. Lists and records use the
/// skeletons above (Paper 73E); this is the one spinner-with-words. VoiceOver hears the words.
struct ThorbisLoadingLine: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(Theme.muted)
                .accessibilityHidden(true)
            Text(message).font(Theme.font(14)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .accessibilityElement(children: .combine)
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
