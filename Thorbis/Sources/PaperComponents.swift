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
                .font(Theme.font(wordmarkSize, weight: .medium))
                .foregroundStyle(Theme.foreground)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Thorbis")
    }
}

/// The tab-root header (design.thorbis.com MA-05): a 44-tall top row with the menu button leading and
/// at most one circle trailing, then the 30/500 large title and one muted subtitle line. The title
/// scrolls with its content; the tab bar stays put.
struct PaperHeader: View {
    let title: String
    var icon: String = ""
    let subtitle: String
    var search: (() -> Void)? = nil
    @EnvironmentObject private var session: SessionController
    @Environment(\.paperShowMenu) private var openAccount
    @Environment(\.paperMenuButton) private var showsMenuButton

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The menu button sits top-left on iPad. On iPhone the bottom bar opens the menu, so the
            // filter joins the title's line and no near-empty row sits above it.
            if showsMenuButton {
                HStack(alignment: .center, spacing: 8) {
                    PaperCircleButton(symbol: "line.3.horizontal", label: "Open menu", action: openAccount)
                    Spacer(minLength: 0)
                    filterButton
                }
                .frame(minHeight: 44)
            }
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(Theme.font(30, weight: .medium)).tracking(-0.6)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if !showsMenuButton { filterButton }
            }
            Text(subtitle)
                .font(Theme.font(15)).foregroundStyle(Theme.muted)
                .lineLimit(2)
                .frame(minHeight: 20, alignment: .leading)
        }
        .foregroundStyle(Theme.foreground)
        .padding(.horizontal, Theme.gutter).padding(.top, showsMenuButton ? 2 : 12).padding(.bottom, 12)
    }

    /// Filters this list; the bar's Search finds anything. Different glyphs, different jobs.
    @ViewBuilder private var filterButton: some View {
        if let search {
            PaperCircleButton(symbol: "line.3.horizontal.decrease", label: "Filter \(title.lowercased())", action: search)
        }
    }
}

/// A 36pt filled circle with a 44pt hit area (HIG-004).
struct PaperCircleButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 36
    /// Canvas fill; use `Theme.card` with `bordered` on a cream ground so the circle reads as a button.
    var fill: Color = Theme.fill
    var bordered = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.foreground)
                .frame(width: size, height: size)
                .background(fill, in: Circle())
                .overlay { if bordered { Circle().strokeBorder(Theme.border, lineWidth: 1) } }
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
    /// Keep every destination visible when a compact screen cannot fit one row.
    var wrapOverflow = false
    /// Offer a button as well as a swipe when a row has hidden sections.
    var explicitScrollControl = false
    /// True while tabs remain past the trailing edge; the fade shows only then, so the
    /// last tab is never left dimmed once you've scrolled to it.
    @State private var moreTrailing = true
    var body: some View {
        // Fit one row where possible. Compact layouts can wrap; other callers keep
        // the scrolling fallback and its trailing fade.
        ViewThatFits(in: .horizontal) {
            row(padding: 12).padding(.horizontal, Theme.gutter - 4)
            row(padding: 8).padding(.horizontal, Theme.gutter - 8)
            // The job's five tabs need this on a 402pt phone; a cut-off "Acti" reads as a bug.
            row(padding: 6).padding(.horizontal, Theme.gutter - 6)
            if wrapOverflow {
                // Keep all destinations in one row when modestly tighter spacing suffices.
                // Each tab retains its 44-point minimum height and full label.
                row(padding: 3).padding(.horizontal, Theme.gutter - 6)
                FlowRow(spacing: 2, lineSpacing: 0) {
                    ForEach(options, id: \.self) { option in
                        tab(option, padding: 8)
                    }
                }
                .padding(.horizontal, Theme.gutter - 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollViewReader { proxy in
                    HStack(spacing: 0) {
                        ScrollView(.horizontal) {
                            row(padding: explicitScrollControl ? 6 : 12).padding(.horizontal, Theme.gutter - 4)
                        }
                        .scrollIndicators(.hidden)
                        .onScrollGeometryChange(for: Bool.self) { geometry in
                            geometry.contentOffset.x + geometry.containerSize.width < geometry.contentSize.width - 1
                        } action: { _, value in
                            moreTrailing = value
                        }
                        .mask(LinearGradient(stops: [.init(color: .black, location: 0.88),
                                                     .init(color: moreTrailing ? .clear : .black, location: 1)],
                                             startPoint: .leading, endPoint: .trailing))
                        .onChange(of: selection) { _, value in
                            withMotion(.easeOut(duration: 0.2)) { proxy.scrollTo(value, anchor: .center) }
                        }
                        if explicitScrollControl, let first = options.first, let last = options.last {
                            Button {
                                withMotion(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo(moreTrailing ? last : first, anchor: moreTrailing ? .trailing : .leading)
                                }
                            } label: {
                                Image(systemName: moreTrailing ? "chevron.right" : "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(moreTrailing ? "Show more job sections" : "Show first job sections")
                        }
                    }
                }
            }
        }
        .padding(.bottom, 4)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func row(padding: CGFloat) -> some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                tab(option, padding: padding)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tab(_ option: String, padding: CGFloat) -> some View {
        Button { selection = option } label: {
            Text(option).font(Theme.font(15, weight: .medium)).lineLimit(1).fixedSize()
                .foregroundStyle(selection == option ? Theme.foreground : Theme.muted)
                .padding(.horizontal, padding).padding(.vertical, 6)
                .frame(minHeight: Theme.chipHeight + 4)
                .background(selection == option ? Theme.fill : .clear, in: Capsule())
                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .id(option)
        .accessibilityAddTraits(selection == option ? .isSelected : [])
    }
}

/// The muted line above a page title. Only the reference ("JOB-2214") is mono so its digits
/// line up; names and words read in the 13pt body face.
struct PaperEyebrow: View {
    var reference: String? = nil
    var text: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let reference { Text(reference).font(Theme.monoFont(12, weight: .medium)).fixedSize() }
            if reference != nil, text != nil { Text("·").font(Theme.font(13)) }
            if let text { Text(text).font(Theme.font(13)).lineLimit(1) }
        }
        .foregroundStyle(Theme.muted)
        .accessibilityElement(children: .combine)
    }
}

/// Sentence-case group header: 13/500 muted title, mono count (left out at zero, where the
/// empty state below already says so), optional trailing action.
struct PaperGroupHeader<Trailing: View>: View {
    let title: String
    var count: Int? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(Theme.font(13, weight: .medium))
            if let count, count > 0 { Text("\(count)").font(Theme.monoFont(12)) }
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
            Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(Theme.muted)
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
        // A short value sits on the label's line; a long one (gate codes, notes) goes under it,
        // left-aligned, instead of a ragged right-aligned paragraph.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label).font(Theme.font(15)).foregroundStyle(Theme.muted).fixedSize()
                Spacer(minLength: 8)
                value.font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(Theme.font(15)).foregroundStyle(Theme.muted)
                value.font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

extension PaperDetailRow where Value == Text {
    init(_ label: String, value: String) {
        self.init(label: label) { Text(value) }
    }
    /// MF-02: an amount in a detail row reads at the line size in tabular mono.
    init(_ label: String, money: String) {
        self.init(label: label) { Text(money).font(Theme.moneyFont(.line)).monospacedDigit() }
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
    /// Inside a card the mark sits in an `IconTile` well, like every other card row.
    var filled = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: filled ? 12 : 14) {
            if filled {
                IconTile(symbol: symbol, tint: tile ?? (tint == Theme.foreground ? Theme.foreground : tint))
            } else if let tile {
                // D-020 outline mark at rest; quiet hue on the mark only, never a filled tile.
                Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(tile)
                    .frame(width: 22)
            } else {
                Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(tint == Theme.foreground ? Theme.muted : tint)
                    .frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.font(15, weight: .medium)).foregroundStyle(tint)
                if let subtitle {
                    Text(subtitle).font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .lineLimit(filled ? 2 : nil)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, filled ? PaperCardMetrics.inset : 0).padding(.vertical, filled ? 8 : 0)
        .frame(minHeight: filled ? 60 : 48).contentShape(Rectangle())
    }
}

extension PaperMenuRow where Trailing == AnyView {
    /// A navigable row with a chevron.
    init(_ title: String, symbol: String, subtitle: String? = nil, value: String? = nil, tile: Color? = nil, filled: Bool = false) {
        self.init(title: title, symbol: symbol, subtitle: subtitle, tile: tile, filled: filled) {
            AnyView(HStack(spacing: 6) {
                if let value { Text(value).font(Theme.font(15)).foregroundStyle(Theme.muted) }
                PaperDisclosure()
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
        }.font(Theme.font(16)).padding(.leading, 12).frame(minHeight: 44).background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).stroke(Theme.border)).padding(.horizontal, Theme.gutter).padding(.bottom, 12)
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
        appearance.titleTextAttributes = [.font: inter(17, .medium)]
        appearance.largeTitleTextAttributes = [.font: inter(30, .medium)]
        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithDefaultBackground()
        scrolled.titleTextAttributes = appearance.titleTextAttributes
        scrolled.largeTitleTextAttributes = appearance.largeTitleTextAttributes
        UINavigationBar.appearance().standardAppearance = scrolled
        UINavigationBar.appearance().compactAppearance = scrolled
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
}

private struct PaperMenuButtonKey: EnvironmentKey {
    static let defaultValue = true
}
extension EnvironmentValues {
    /// Whether tab-root headers show the top-left menu button. iPhone turns it off for the bottom bar.
    var paperMenuButton: Bool {
        get { self[PaperMenuButtonKey.self] }
        set { self[PaperMenuButtonKey.self] = newValue }
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
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var outbox: FieldOutbox
    @EnvironmentObject private var media: PendingMediaStore
    @Environment(\.savedWorkReviewReturnToRoot) private var returnToReview
    @State private var reviewScope: SavedWorkScope?

    private var scope: SavedWorkScope? { .capture(session: session, api: api, media: media, outbox: outbox) }
    private var reviewIsCurrent: Bool { reviewScope?.isCurrent(session: session, api: api, media: media, outbox: outbox) ?? true }
    private var snapshot: SavedWorkSnapshot? {
        guard let scope else { return nil }
        return .make(scope: scope, entries: outbox.entries, media: media.items, mediaErrors: media.errors,
                     unverifiedMediaIDs: media.unverifiedIDs, uploadingMediaID: media.uploadingID,
                     commandsSyncing: outbox.syncing, jobs: store.jobs, listingWarning: media.storageWarning)
    }
    var body: some View {
        Group {
            if let state = snapshot, state.hasPendingWork {
                Button {
                    if let returnToReview { returnToReview() }
                    else { reviewScope = scope }
                } label: {
                    banner(symbol: state.attentionCount > 0 || state.hasListingWarning ? "exclamationmark.triangle" : (session.isOffline ? "wifi.slash" : "arrow.triangle.2.circlepath"),
                           tint: state.attentionCount > 0 || state.hasListingWarning ? Theme.warning : Theme.muted,
                           text: summary(state), trailing: state.totalCount == 0 ? String(localized: "Review") : (state.totalCount == 1 ? String(localized: "1 item") : String(localized: "\(state.totalCount) items")))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Review saved work")
                .accessibilityValue(summary(state) + ", " + String(localized: "\(state.totalCount) items listed"))
                .accessibilityIdentifier("saved-work-summary")
            } else if session.isOffline {
                banner(symbol: "wifi.slash", tint: Theme.warning,
                       text: "Offline · showing \(store.cachedAt.map { "work saved " + $0.formatted(.relative(presentation: .named)) } ?? "your last copy")", trailing: nil)
            }
        }
        .padding(.horizontal, Theme.gutter).padding(.bottom, 10)
        .sheet(item: $reviewScope) { SavedWorkReviewView(scope: $0) }
        .onChange(of: reviewIsCurrent) { _, valid in if !valid { reviewScope = nil } }
        #if DEBUG
        .task { await PaperPreview.activateSavedWorkScenario(session: session) }
        #endif
    }
    private func summary(_ state: SavedWorkSnapshot) -> String {
        if state.hasListingWarning { return String(localized: "Saved work needs checking") }
        if state.attentionCount > 0 { return String(localized: "Saved work needs attention") }
        if session.isOffline { return String(localized: "Offline · saved on this phone") }
        return state.isSending ? String(localized: "Syncing saved work") : String(localized: "Saved on this phone")
    }
    private func banner(symbol: String, tint: Color, text: String, trailing: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(tint).accessibilityHidden(true)
            Text(text).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let trailing { Text(trailing).font(Theme.monoFont(13, weight: .medium)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// One row of the actions people reach for on a person or a place: call, text, email, drive.
/// Used on the job and customer headers so the pattern is the same everywhere.
struct PaperQuickActions: View {
    var phone: String?
    var email: String?
    var directions: URL?
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var dialable: String? {
        phone.map { $0.filter { $0.isNumber || $0 == "+" } }.flatMap { $0.count >= 7 ? $0 : nil }
    }

    var body: some View {
        let dialable = dialable
        let mail = email.flatMap { $0.contains("@") ? URL(string: "mailto:\($0)") : nil }
        if dialable != nil || mail != nil || directions != nil {
            if dynamicTypeSize.isAccessibilitySize {
                row(dialable: dialable, mail: mail, stacked: false, vertical: true)
            } else {
                // At standard sizes, use the compact row while every label fits.
                ViewThatFits(in: .horizontal) {
                    row(dialable: dialable, mail: mail, stacked: false)
                    row(dialable: dialable, mail: mail, stacked: true)
                }
            }
        }
    }

    private func row(dialable: String?, mail: URL?, stacked: Bool, vertical: Bool = false) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            if let dialable, let call = URL(string: "tel:\(dialable)"), let text = URL(string: "sms:\(dialable)") {
                action("Call", symbol: "phone", label: "Call", stacked: stacked) { openURL(call) }
                action("Text", symbol: "message", label: "Text", stacked: stacked) { openURL(text) }
            }
            if let mail { action("Email", symbol: "envelope", label: "Email", stacked: stacked) { openURL(mail) } }
            if let directions { action("Directions", symbol: "arrow.triangle.turn.up.right.diamond", label: "Directions in Maps", stacked: stacked) { openURL(directions) } }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func action(_ title: String, symbol: String, label: String, stacked: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            // Glyph then word: the same reach as a tile, in less height.
            let layout = stacked ? AnyLayout(VStackLayout(spacing: 3)) : AnyLayout(HStackLayout(spacing: 6))
            layout {
                // A fixed glyph box keeps every word on one baseline, whatever the symbol's height.
                Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.brandText)
                    .frame(width: 22, height: 20)
                Text(title).font(Theme.font(stacked ? 13 : 15, weight: .medium)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
            }
            .padding(.horizontal, stacked ? 4 : 10)
            .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : (stacked ? 6 : 0))
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: dynamicTypeSize.isAccessibilitySize ? nil : .infinity)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
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
            let size = measuredSize(of: view, width: width)
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
            let size = measuredSize(of: view, width: bounds.width)
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

    private func measuredSize(of view: Subviews.Element, width: CGFloat) -> CGSize {
        let natural = view.sizeThatFits(.unspecified)
        guard natural.width > width else { return natural }
        return view.sizeThatFits(ProposedViewSize(width: max(0, width), height: nil))
    }
}


/// One "more" control for an editable line (MA-12): keeps the description wide instead of
/// three icon buttons beside it.
struct LineItemActions: View {
    let name: String
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    var body: some View {
        var items: [ThorbisMenuItem] = []
        if canMoveUp { items.append(ThorbisMenuItem("Move up", icon: "arrow.up") { moveUp() }) }
        if canMoveDown { items.append(ThorbisMenuItem("Move down", icon: "arrow.down") { moveDown() }) }
        items.append(ThorbisMenuItem("Remove line", icon: "trash", role: .destructive) { remove() })
        return ThorbisMenu(items: items,
                           accessibilityLabel: "Actions for \(name.isEmpty ? "line item" : name)") {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.muted)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }
}

/// A number field on a line: a 44-tall well so the thumb can hit it, readable mono type.
struct LineNumberField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var prefix: String?
    var decimal = false
    var width: CGFloat = 64

    var body: some View {
        HStack(spacing: 4) {
            if let prefix { Text(prefix).font(Theme.monoFont(15)).foregroundStyle(Theme.muted) }
            TextField(placeholder, text: $text)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .font(Theme.monoFont(15, weight: .medium))
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(label)
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: 44)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }
}

extension View {
    /// Number pads have no return key: one Done above the keyboard (MA-16).
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .frame(minWidth: 44, minHeight: 44)
            }
        }
    }

    /// Cancel and swipe never throw away edits silently (MA-16, MA-17).
    func discardChangesGuard(hasChanges: Bool, busy: Bool, isPresented: Binding<Bool>, discard: @escaping () -> Void) -> some View {
        interactiveDismissDisabled(busy || hasChanges)
            .thorbisConfirm("Discard your changes?", isPresented: isPresented,
                            actions: [ThorbisConfirmAction("Discard changes", role: .destructive, action: discard)])
    }
}

/// The list's create action, in the thumb zone above the tab bar (MA-02): the same pill on
/// Jobs and Customers instead of a plus on one screen and a pill on the other.
struct FloatingCreateButton: View {
    let title: String
    var disabled = false
    let action: () -> Void
    /// On iPhone the bottom bar's + creates for the screen showing, so this pill steps aside.
    @Environment(\.paperMenuButton) private var visible

    var body: some View {
        if visible { pill }
    }

    private var pill: some View {
        HStack {
            Spacer()
            Button(action: action) {
                Label(title, systemImage: "plus").font(Theme.font(15, weight: .medium))
                    .padding(.horizontal, 16).frame(minHeight: 44)
                    .background(Theme.card, in: Capsule()).overlay(Capsule().stroke(Theme.border))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressStyle()).disabled(disabled)
        }
        .padding(.horizontal, Theme.gutter).padding(.bottom, 8)
    }
}

/// Row disclosure chevron: one size, weight and colour for every tappable row.
struct PaperDisclosure: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.muted)
            .accessibilityHidden(true)
    }
}

extension PaperEmptyState {
    /// No-results state for a search, in Paper type instead of the system's SF Pro view.
    static func search(_ text: String) -> PaperEmptyState {
        PaperEmptyState(symbol: "magnifyingglass", title: "No results for \u{201C}\(text)\u{201D}",
                        message: "Check the spelling or try a different word.")
    }
}

// MARK: - Planar card groups (approved visual design, 2026-10-30)
//
// Groups of rows sit on one planar panel: `Theme.card`, radius 14, a 1px `Theme.border` rim that
// follows the radius, no shadow and no hairlines between rows (design.thorbis.com: "a border is a
// use case, never a separator"; golden rule 9). Rows are separated by spacing and lead with an icon
// tile; a status is always a word, the tile's colour only reinforces it.

enum PaperCardMetrics {
    /// design.thorbis.com sheet radius.
    static let radius: CGFloat = Theme.cardRadius
    /// Rows inside a card pad by this, so their text lines up with the card's edge.
    static let inset: CGFloat = 14
    /// The card's distance from the screen edge; group headers add 4 so they align with the gutter.
    static let margin: CGFloat = 16
    /// Breathing room above the first and below the last row, instead of a rule between rows.
    static let edge: CGFloat = 4
}

/// Rows pad horizontally by this. Outside a card it is the screen gutter, so a row used on the
/// bare background is unchanged; inside a card it is the card's inset.
private struct PaperRowInsetKey: EnvironmentKey { static let defaultValue: CGFloat = Theme.gutter }
extension EnvironmentValues {
    var paperRowInset: CGFloat {
        get { self[PaperRowInsetKey.self] }
        set { self[PaperRowInsetKey.self] = newValue }
    }
}

/// A planar panel holding a group of rows or one block of content.
struct PaperCard<Content: View>: View {
    /// Inner padding for free-form content; rows pass 0 and pad themselves by `paperRowInset`.
    var padding: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PaperCardMetrics.radius, style: .circular)
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: shape)
            .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
            .environment(\.paperRowInset, PaperCardMetrics.inset)
    }
}

extension View {
    /// A label-and-value row inside a `PaperCard`: padded to the card's edge, 48 tall.
    func cardRow() -> some View {
        padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 48)
    }

    /// One row of a card that is built row by row, so long lists stay lazy. The first row draws
    /// the card's top, the last its bottom; rows between carry only the side rims, never a line.
    func paperCardSlot(first: Bool, last: Bool) -> some View {
        modifier(PaperCardSlot(first: first, last: last))
    }

    /// Cards sit 16 from the screen edge.
    func paperCardMargin() -> some View { padding(.horizontal, PaperCardMetrics.margin) }
}

private struct PaperCardSlot: ViewModifier {
    let first: Bool
    let last: Bool

    func body(content: Content) -> some View {
        let r = PaperCardMetrics.radius
        content
            .environment(\.paperRowInset, PaperCardMetrics.inset)
            .padding(.top, first ? PaperCardMetrics.edge : 0)
            .padding(.bottom, last ? PaperCardMetrics.edge : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: UnevenRoundedRectangle(topLeadingRadius: first ? r : 0, bottomLeadingRadius: last ? r : 0,
                                                               bottomTrailingRadius: last ? r : 0, topTrailingRadius: first ? r : 0,
                                                               style: .circular))
            .overlay(PaperCardSliceRim(first: first, last: last, radius: r).stroke(Theme.border, lineWidth: 1))
    }
}

/// The card's 1px rim for one slice: sides always, the top arc on the first slice and the bottom
/// arc on the last, so a stack of slices reads as one panel with no rule between rows.
private struct PaperCardSliceRim: Shape {
    let first: Bool
    let last: Bool
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: 0.5, dy: 0.5)
        let r = min(radius, box.width / 2, box.height / 2)
        var path = Path()
        // Leading side, bottom to top (through the bottom arc when last).
        if last {
            path.move(to: CGPoint(x: box.midX, y: box.maxY))
            path.addArc(tangent1End: CGPoint(x: box.minX, y: box.maxY), tangent2End: CGPoint(x: box.minX, y: box.minY), radius: r)
        } else {
            path.move(to: CGPoint(x: box.minX, y: rect.maxY))
        }
        if first {
            path.addArc(tangent1End: CGPoint(x: box.minX, y: box.minY), tangent2End: CGPoint(x: box.maxX, y: box.minY), radius: r)
            path.addArc(tangent1End: CGPoint(x: box.maxX, y: box.minY), tangent2End: CGPoint(x: box.maxX, y: box.maxY), radius: r)
        } else {
            path.addLine(to: CGPoint(x: box.minX, y: rect.minY))
            path.move(to: CGPoint(x: box.maxX, y: rect.minY))
        }
        if last {
            path.addArc(tangent1End: CGPoint(x: box.maxX, y: box.maxY), tangent2End: CGPoint(x: box.minX, y: box.maxY), radius: r)
            path.addLine(to: CGPoint(x: box.midX, y: box.maxY))
        } else {
            path.addLine(to: CGPoint(x: box.maxX, y: rect.maxY))
        }
        return path
    }
}

/// A group of rows on one card, built lazily row by row.
struct PaperCardList<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    let data: Data
    @ViewBuilder var row: (Data.Element) -> Row

    var body: some View {
        let items = Array(data)
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            row(item).paperCardSlot(first: index == 0, last: index == items.count - 1)
        }
    }
}

/// A rounded square holding a symbol: the leading mark on a row, so rows scan by shape and colour.
/// Decorative; the row's words carry the meaning.
struct IconTile: View {
    let symbol: String
    var tint: Color = Theme.foreground
    var fill: Color = Theme.fill
    static let size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: Self.size, height: Self.size)
            .background(fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A job's status as a tinted tile. The status word is always in the row beside it.
struct StatusTile: View {
    let status: String
    /// A step saved on the phone and waiting to sync.
    var pending = false

    var body: some View {
        let (symbol, color) = statusIcon(status)
        IconTile(symbol: pending ? "clock.arrow.circlepath" : symbol,
                 tint: pending ? Theme.warning : color == Theme.muted ? Theme.foreground : color,
                 fill: Self.surface(status, pending: pending))
    }

    static func surface(_ status: String, pending: Bool = false) -> Color {
        if pending { return Theme.warningSurface }
        switch status {
        case "completed": return Theme.successSurface
        case "in_progress", "arrived", "paused": return Theme.warningSurface
        case "en_route", "dispatched": return Theme.brandSurface
        default: return Theme.fill
        }
    }
}

/// A document's kind as a tile tinted by its status (approved green, waiting amber, void red).
struct DocumentTile: View {
    let symbol: String
    let status: String

    var body: some View {
        let (tint, fill): (Color, Color) = switch status {
        case "approved", "paid", "completed": (Theme.success, Theme.successSurface)
        case "sent", "issued", "open": (Theme.warning, Theme.warningSurface)
        case "declined", "void", "canceled": (Theme.destructive, Theme.destructiveSurface)
        default: (Theme.foreground, Theme.fill)
        }
        IconTile(symbol: symbol, tint: tint, fill: fill)
    }
}

/// A plain fact beside a status pill: a small icon and words, no pill. Only what you can tap or
/// what carries state is a pill.
struct Fact: View {
    let text: String
    var icon: String? = nil
    var tint: Color = Theme.muted

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 12, weight: .medium)).foregroundStyle(tint).accessibilityHidden(true) }
            Text(text).font(Theme.font(13, weight: .medium)).foregroundStyle(tint).lineLimit(1).fixedSize()
        }
        .frame(minHeight: Theme.chipHeight)
    }
}

/// Headline numbers at the top of a screen: two to four figures on one card, label over value,
/// separated by space rather than rules. Stacks at accessibility sizes instead of shrinking.
struct PaperStatRow: View {
    struct Stat: Identifiable {
        let label: String
        let value: String
        var detail: String? = nil
        var tint: Color = Theme.foreground
        var detailTint: Color = Theme.muted
        var id: String { label }
    }
    let stats: [Stat]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                             : AnyLayout(HStackLayout(alignment: .top, spacing: 0))
        PaperCard {
            layout {
                ForEach(stats) { stat in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(stat.label).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                            .lineLimit(stacked ? nil : 1)
                        Text(stat.value).font(Theme.font(20, weight: .medium)).monospacedDigit()
                            .foregroundStyle(stat.tint)
                            .lineLimit(stacked ? nil : 1).minimumScaleFactor(stacked ? 1 : 0.8)
                        if let detail = stat.detail {
                            Text(detail).font(Theme.font(12, weight: stat.detailTint == Theme.muted ? .regular : .medium))
                                .foregroundStyle(stat.detailTint)
                                .lineLimit(stacked ? nil : 2)
                        }
                    }
                    .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
