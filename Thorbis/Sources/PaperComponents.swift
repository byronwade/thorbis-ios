import SwiftUI
import UIKit

struct ThorbisLogoLockup: View {
    var markSize: CGFloat = 30
    var wordmarkSize: CGFloat = 16

    var body: some View {
        HStack(spacing: markSize * 0.3) {
            Image("ThorbisMark")
                .resizable()
                .scaledToFit()
                .frame(width: markSize, height: markSize)
                .accessibilityHidden(true)
            Text("Thorbis")
                .font(Theme.font(wordmarkSize, weight: .semibold))
                .foregroundStyle(Theme.foreground)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Thorbis")
    }
}

/// Paper's tab-root header (primitives sheet: 34/700 large title, 15 muted subtitle,
/// trailing 36pt circles). The title scrolls with its content; the tab bar stays put.
struct PaperHeader: View {
    let title: String
    var icon: String = ""
    let subtitle: String
    var search: (() -> Void)? = nil
    @EnvironmentObject private var session: SessionController
    @Environment(\.paperShowMenu) private var openAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // ChatGPT-style top row: the menu button sits top-left on every main screen.
            HStack(alignment: .center, spacing: 8) {
                PaperCircleButton(symbol: "line.3.horizontal", label: "Open menu", action: openAccount)
                Spacer(minLength: 0)
                if let search {
                    PaperCircleButton(symbol: "magnifyingglass", label: "Filter \(title.lowercased())", action: search)
                }
                // One way in: the menu button. The account lives at the bottom of the menu.
            }
            Text(title)
                .font(Theme.font(34, weight: .bold)).tracking(-0.68)
                .lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(Theme.font(15)).foregroundStyle(Theme.muted)
                .frame(minHeight: 20, alignment: .leading)
        }
        .foregroundStyle(Theme.foreground)
        .padding(.horizontal, Theme.gutter).padding(.top, 2).padding(.bottom, 12)
    }
}

/// A 36pt filled circle with a 44pt hit area (HIG-004).
struct PaperCircleButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 36
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.foreground)
                .frame(width: size, height: size).background(Theme.fill, in: Circle())
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

/// Paper's segment tabs: quiet words, the selected one sits in a fill pill.
struct PaperTabs: View {
    let options: [String]
    @Binding var selection: String
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(options, id: \.self) { option in
                    Button { selection = option } label: {
                        Text(option).font(Theme.font(13, weight: selection == option ? .semibold : .medium))
                            .foregroundStyle(selection == option ? Theme.foreground : Theme.muted)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(selection == option ? Theme.fill : .clear, in: Capsule())
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(selection == option ? .isSelected : [])
                }
            }.padding(.horizontal, Theme.gutter - 4)
        }.scrollIndicators(.hidden).padding(.bottom, 4)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Sentence-case group header: 13/500 muted title, mono count, optional trailing action.
struct PaperGroupHeader<Trailing: View>: View {
    let title: String
    var count: Int? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(Theme.font(13, weight: .medium))
            if let count { Text("\(count)").font(Theme.monoFont(12)) }
            Spacer(minLength: 0)
            trailing
        }
        .foregroundStyle(Theme.muted)
        .frame(minHeight: 32)
        .accessibilityElement(children: .contain)
    }
}

extension PaperGroupHeader where Trailing == EmptyView {
    init(title: String, count: Int? = nil) {
        self.init(title: title, count: count) { EmptyView() }
    }
}

/// Job status as a mark whose shape (not only colour) carries meaning, plus a spoken word.
struct StatusRing: View {
    let status: String
    var size: CGFloat = 16

    var body: some View {
        let (symbol, color) = statusIcon(status)
        Image(systemName: symbol)
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(color)
            .frame(width: size + 6, height: size + 6)
            .accessibilityLabel(status.statusLabel)
    }
}

/// MA-14: what will be here, in one sentence, and one bordered button that starts it.
struct PaperEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 26, weight: .light)).foregroundStyle(Theme.muted)
                .padding(.bottom, 6)
            Text(title).font(Theme.font(17, weight: .medium)).foregroundStyle(Theme.foreground)
                .multilineTextAlignment(.center)
            Text(message).font(Theme.font(15)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 18).frame(minHeight: 44)
                        .background(Theme.card, in: Capsule()).overlay(Capsule().stroke(Theme.border))
                }
                .buttonStyle(PressStyle())
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48).padding(.horizontal, Theme.gutter)
    }
}

/// Paper's quick-edit value row: muted label left, value right.
struct PaperDetailRow<Value: View>: View {
    let label: String
    @ViewBuilder var value: Value

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(Theme.font(14)).foregroundStyle(Theme.muted).fixedSize()
            Spacer(minLength: 8)
            value.font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.foreground)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 42)
        .accessibilityElement(children: .combine)
    }
}

extension PaperDetailRow where Value == Text {
    init(_ label: String, value: String) {
        self.init(label: label) { Text(value) }
    }
}

/// A row in a grouped list of destinations or settings (Paper 29 / 65).
struct PaperMenuRow<Trailing: View>: View {
    let title: String
    let symbol: String
    var subtitle: String? = nil
    var tint: Color = Theme.foreground
    /// A softly tinted mark, so a long menu scans by color after the word.
    var tile: Color? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            if let tile {
                // D-020 outline mark at rest; quiet hue on the mark only, never a filled tile.
                Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(tile)
                    .frame(width: 22)
            } else {
                Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(tint == Theme.foreground ? Theme.muted : tint)
                    .frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.font(15, weight: .medium)).foregroundStyle(tint)
                if let subtitle { Text(subtitle).font(Theme.font(13)).foregroundStyle(Theme.muted) }
            }
            Spacer(minLength: 8)
            trailing
        }
        .frame(minHeight: 48).contentShape(Rectangle())
    }
}

extension PaperMenuRow where Trailing == AnyView {
    /// A navigable row with a chevron.
    init(_ title: String, symbol: String, subtitle: String? = nil, value: String? = nil, tile: Color? = nil) {
        self.init(title: title, symbol: symbol, subtitle: subtitle, tile: tile) {
            AnyView(HStack(spacing: 6) {
                if let value { Text(value).font(Theme.font(14)).foregroundStyle(Theme.muted) }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
            })
        }
    }
}

/// The sticky bottom bar: one ink commit (MA-08), at most one quiet square beside it.
struct PaperActionBar<Secondary: View>: View {
    let title: String
    var symbol: String? = nil
    var busy = false
    var disabled = false
    let action: () -> Void
    @ViewBuilder var secondary: Secondary

    var body: some View {
        HStack(spacing: 8) {
            Button(action: action) {
                HStack(spacing: 7) {
                    if busy { ProgressView().tint(Theme.onInk) } else if let symbol { Image(systemName: symbol).font(.system(size: 15, weight: .medium)) }
                    Text(title)
                }
                .inkCommit(enabled: !disabled)
            }
            .buttonStyle(PressStyle())
            .disabled(busy || disabled)
            secondary
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 10).padding(.bottom, 8)
        .background(Theme.background)
    }
}

extension PaperActionBar where Secondary == EmptyView {
    init(title: String, symbol: String? = nil, busy: Bool = false, disabled: Bool = false, action: @escaping () -> Void) {
        self.init(title: title, symbol: symbol, busy: busy, disabled: disabled, action: action) { EmptyView() }
    }
}

/// The rimmed square that sits beside a commit, as tall as the commit.
struct PaperSquareButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(Theme.foreground)
                .frame(width: Theme.commitHeight, height: Theme.commitHeight)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).stroke(Theme.border))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

struct PaperSearchField: View {
    @Binding var text: String
    var prompt: String = "Search"
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField(prompt, text: $text).textInputAutocapitalization(.never).autocorrectionDisabled()
            if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted).frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("Clear search") }
        }.font(Theme.font(16)).padding(.leading, 12).frame(minHeight: 44).background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border)).padding(.horizontal, Theme.gutter).padding(.bottom, 12)
    }
}

enum PaperChrome {
    /// Inter titles on the native navigation bar, so pushed screens keep system
    /// back, swipe-back and VoiceOver escape while matching Paper's type.
    @MainActor static func configureNavigationBar() {
        func inter(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let descriptor = UIFontDescriptor(fontAttributes: [
                .family: "Inter",
                .traits: [UIFontDescriptor.TraitKey.weight: weight]
            ])
            return UIFontMetrics.default.scaledFont(for: UIFont(descriptor: descriptor, size: size))
        }
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.titleTextAttributes = [.font: inter(17, .semibold)]
        appearance.largeTitleTextAttributes = [.font: inter(34, .bold)]
        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithDefaultBackground()
        scrolled.titleTextAttributes = appearance.titleTextAttributes
        scrolled.largeTitleTextAttributes = appearance.largeTitleTextAttributes
        UINavigationBar.appearance().standardAppearance = scrolled
        UINavigationBar.appearance().compactAppearance = scrolled
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
}

private struct PaperShowMenuKey: EnvironmentKey {
    static let defaultValue: @Sendable () -> Void = {}
}
extension EnvironmentValues {
    /// Opens account and settings (the More tab on iPhone, the settings sheet on iPad).
    var paperShowMenu: @Sendable () -> Void {
        get { self[PaperShowMenuKey.self] }
        set { self[PaperShowMenuKey.self] = newValue }
    }
}

/// Paper 73 / 74: offline, syncing and needs-review states. Queued is never shown as done.
struct OfflineBanner: View {
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var outbox: FieldOutbox
    @State private var showReview = false

    var body: some View {
        Group {
            if !outbox.needsReview.isEmpty {
                Button { showReview = true } label: {
                    banner(symbol: "exclamationmark.triangle", tint: Theme.destructive, ground: Theme.destructiveSurface,
                           text: "\(outbox.needsReview.count) change\(outbox.needsReview.count == 1 ? "" : "s") couldn't sync",
                           trailing: "Review")
                }
                .buttonStyle(.plain)
            } else if session.isOffline {
                banner(symbol: "wifi.slash", tint: Theme.warning, ground: Theme.warningSurface,
                       text: outbox.pending.isEmpty ? "Offline · showing \(store.cachedAt.map { "work saved " + $0.formatted(.relative(presentation: .named)) } ?? "your last copy")"
                                                    : "Offline · changes save on this phone",
                       trailing: outbox.pending.isEmpty ? nil : "\(outbox.pending.count) queued")
            } else if outbox.syncing || !outbox.pending.isEmpty {
                banner(symbol: "arrow.triangle.2.circlepath", tint: Theme.success, ground: Theme.successSurface,
                       text: outbox.syncing ? "Back online · syncing changes" : "Waiting to sync",
                       trailing: "\(outbox.pending.count) left")
            }
        }
        .padding(.horizontal, Theme.gutter).padding(.bottom, 10)
        .sheet(isPresented: $showReview) { OutboxReviewSheet() }
    }

    private func banner(symbol: String, tint: Color, ground: Color, text: String, trailing: String?) -> some View {
        // Only the mark is tinted; the words stay body colour (design.thorbis.com).
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(tint)
            Text(text).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.foreground).lineLimit(2)
            Spacer(minLength: 8)
            if let trailing { Text(trailing).font(Theme.monoFont(12, weight: .medium)).foregroundStyle(Theme.muted) }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Changes the server refused, with its reason. Dismissing removes the local copy only.
struct OutboxReviewSheet: View {
    @EnvironmentObject private var outbox: FieldOutbox
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("These changes were made without signal and the server didn't accept them. Open the job to redo what's still needed.")
                        .font(Theme.font(14)).foregroundStyle(Theme.muted).padding(.bottom, 12)
                    ForEach(outbox.needsReview) { entry in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.destructive).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(entry.summary) · \(store.jobs.first { $0.id == entry.jobID }?.title ?? "Job")")
                                    .font(Theme.font(15, weight: .medium))
                                Text(reason(entry)).font(Theme.font(13)).foregroundStyle(Theme.muted)
                                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened)).font(Theme.monoFont(11)).foregroundStyle(Theme.muted)
                            }
                            Spacer(minLength: 8)
                            if case .rejected = entry.state {
                                VStack(spacing: 0) {
                                    Button("Retry") { outbox.retry(entry) }
                                        .font(Theme.font(13, weight: .semibold)).frame(minHeight: 44)
                                    Button("Dismiss", role: .destructive) { outbox.dismiss(entry) }
                                        .font(Theme.font(13, weight: .medium)).frame(minHeight: 44)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
            .background(Theme.background)
            .foregroundStyle(Theme.foreground)
            .navigationTitle("Couldn't sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func reason(_ entry: OutboxEntry) -> String {
        switch entry.state {
        case .rejected(let reason): reason
        case .held: "Waiting on an earlier change to this job that didn't sync."
        case .pending: "Waiting to sync."
        }
    }
}

/// One row of the actions people reach for on a person or a place: call, text, email, drive.
/// Used on the job and customer headers so the pattern is the same everywhere.
struct PaperQuickActions: View {
    var phone: String?
    var email: String?
    var directions: URL?
    @Environment(\.openURL) private var openURL

    private var dialable: String? {
        phone.map { $0.filter { $0.isNumber || $0 == "+" } }.flatMap { $0.count >= 7 ? $0 : nil }
    }

    var body: some View {
        let dialable = dialable
        let mail = email.flatMap { $0.contains("@") ? URL(string: "mailto:\($0)") : nil }
        if dialable != nil || mail != nil || directions != nil {
            HStack(spacing: 8) {
                if let dialable, let call = URL(string: "tel:\(dialable)"), let text = URL(string: "sms:\(dialable)") {
                    action("Call", symbol: "phone", label: "Call") { openURL(call) }
                    action("Text", symbol: "message", label: "Text") { openURL(text) }
                }
                if let mail { action("Email", symbol: "envelope", label: "Email") { openURL(mail) } }
                if let directions { action("Directions", symbol: "arrow.triangle.turn.up.right.diamond", label: "Directions in Maps") { openURL(directions) } }
            }
        }
    }

    private func action(_ title: String, symbol: String, label: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.brandText)
                    .frame(height: 18)
                Text(title).font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.foreground)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Lays chips out left to right and wraps to a new line when they run out of room.
struct FlowRow: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += lineHeight + lineSpacing; lineHeight = 0 }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(widest, width), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Break into lines first, then center each chip on its line so mixed hit areas align.
        var lines: [[(Subviews.Element, CGSize)]] = [[]]
        var x: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > bounds.width { lines.append([]); x = 0 }
            lines[lines.count - 1].append((view, size))
            x += size.width + spacing
        }
        var y = bounds.minY
        for line in lines where !line.isEmpty {
            let height = line.map(\.1.height).max() ?? 0
            var x = bounds.minX
            for (view, size) in line {
                view.place(at: CGPoint(x: x, y: y + (height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += height + lineSpacing
        }
    }
}

