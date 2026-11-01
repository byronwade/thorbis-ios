import SwiftUI
import UIKit

// MARK: - Phone drawer (simplified 2026-10-31, after owner feedback on build 125)
//
// The phone's navigation: a side drawer that slides in from the left and pushes the place showing to
// the right, where it waits as a rounded card. Cream sheet (2026-11-01, C-Nav.dc.html): the business
// name and Search, every place the role can reach grouped under Work, Money, Shop and On this phone,
// a few recent records as plain words, then New job and the gear.
// Every screen in a place offers the menu circle: roots in their header, pushed screens beside Back.
// An edge swipe opens it on a root; on a pushed screen the edge swipe stays Back.
// iPad at regular width keeps its sidebar (TabletRoot).

/// The round menu circle at the top left of every phone screen in a place. A small brand dot shows
/// only for unread Inbox notices or saved work that needs the person.
struct DrawerMenuCircle: View {
    let control: PaperDrawerControl
    var size: CGFloat = 40

    var body: some View {
        Button(action: control.open) {
            CreamCircleLabel(symbol: "line.3.horizontal", size: size)
                .overlay(alignment: .topTrailing) {
                    if control.hasNews { DrawerDot().offset(x: -6, y: 6) }
                }
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Menu")
        .accessibilityValue([control.hasNews ? "New items" : nil, control.status].compactMap { $0 }.joined(separator: ", "))
        .accessibilityIdentifier("drawer-menu")
    }
}

/// The small brand dot for unread Inbox notices and saved work that needs the person.
struct DrawerDot: View {
    var body: some View {
        Circle().fill(Theme.brand)
            .frame(width: 9, height: 9)
            .accessibilityHidden(true)
    }
}

/// A recently opened job or customer, as the drawer lists it.
struct DrawerRecent: Identifiable {
    let item: RecentItems.Item
    /// The job's status, when this phone holds the job.
    var status: String?
    var id: String { "\(item.kind.rawValue)-\(item.id)" }
    /// Only a job under way wears a glyph; everything else is words alone.
    var inProgress: Bool { ["arrived", "in_progress", "paused"].contains(status ?? "") }
}

/// The drawer's words for a place.
enum DrawerPlaces {
    /// Schedule is the same screen for everyone: technicians read it as their day ("Today"), office
    /// and owners as the schedule they run.
    static func title(_ item: MenuItem, role: WorkRole) -> String {
        item == .schedule ? (role == .technician ? "Today" : "Schedule") : item.title
    }
}

/// The drawer itself (Cream sheet, C-Nav.dc.html): the business name and a search circle on top,
/// then every place this role can reach grouped under Work, Money, Shop and On this phone (pinned
/// places from Edit menu lead), recent records, and at the foot the ink New job commit and the
/// Settings circle. The list fades at its bottom edge where it continues under the foot.
struct AppDrawer: View {
    let title: String
    let role: WorkRole
    /// The place showing (a MenuItem id or "local-<section>").
    let current: String
    let sections: DrawerSections
    let count: (MenuItem) -> PlaceCount?
    let recents: [DrawerRecent]
    /// Saved work on this phone: its row under On this phone, its words on the gear, its dot when it needs the person.
    var savedWork: AppBottomBar.Sync?
    var create: PaperCreateAction?
    /// The gear circle's menu: businesses, saved work, Add a business, Settings, Edit menu.
    let settingsItems: [ThorbisMenuItem]
    /// At accessibility sizes the drawer is full width, so it carries its own close circle.
    let showsClose: Bool
    /// False while the drawer sits closed under the card (and from the moment it starts closing). The
    /// commit's context menu and the gear's popover are UIKit-hosted and stay in the accessibility
    /// tree even when the drawer is hidden, so they are only built while the drawer can be seen.
    var showsControls = true
    /// False once the drawer has slid shut: its scroll view (UIKit-hosted too) would otherwise sit
    /// empty in the accessibility tree. Kept through the closing slide so the rows don't pop.
    var showsRows = true
    var titleFocus: AccessibilityFocusState<Bool>.Binding
    let search: () -> Void
    let close: () -> Void
    let openPlace: (MenuItem) -> Void
    let openLocal: (LocalWorkspaceSection) -> Void
    let openRecent: (RecentItems.Item) -> Void
    var openSavedWork: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            // Closed, nothing is built: the header and an empty scroll view would still sit in the
            // accessibility tree behind the card.
            if showsRows { header; rows } else { Spacer(minLength: 0) }
            if showsControls { bottomControls }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(Theme.foreground)
        // C-Nav: the drawer sits on the canvas; the place it pushed aside is the panel.
        .background(Theme.background.ignoresSafeArea())
    }

    private var rows: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PlacesList(sections: sections, title: { DrawerPlaces.title($0, role: role) },
                           isCurrent: { current == $0.rawValue }, isCurrentLocal: { current == "local-\($0.rawValue)" },
                           count: count, idPrefix: "drawer", savedWork: savedWork,
                           openPlace: openPlace, openLocal: openLocal, openSavedWork: openSavedWork)
                if !recents.isEmpty {
                    Text("Recent")
                        .font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 12).padding(.top, 16).padding(.bottom, 4)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(recents.prefix(5)) { recentRow($0) }
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        // "Where a list continues, fade the edge": the last rows fade into the foot.
        .mask {
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9),
                                   .init(color: .black.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom)
        }
        .accessibilityIdentifier("drawer-rows")
        #if DEBUG
        .modifier(PaperPreviewScrollAnchor())
        #endif
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(Theme.font(18, weight: .medium)).tracking(-0.2)
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused(titleFocus)
            Button(action: search) { CreamCircleLabel(symbol: "magnifyingglass") }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Search")
                .accessibilityIdentifier("drawer-search")
            if showsClose {
                Button(action: close) { CreamCircleLabel(symbol: "xmark") }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Close menu")
                    .accessibilityIdentifier("drawer-close")
            }
        }
        .padding(.leading, 12).padding(.trailing, 2)
        .padding(.top, 6).padding(.bottom, 4)
    }

    /// A recent record as plain words, like ChatGPT's recents. A job under way wears its status word.
    private func recentRow(_ recent: DrawerRecent) -> some View {
        Button { openRecent(recent.item) } label: {
            HStack(alignment: .center, spacing: 10) {
                Text(recent.item.title)
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.subtle)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
                Spacer(minLength: 8)
                if recent.inProgress, let status = recent.status { StatusLabel(jobStatus: status, emphasis: .quiet).fixedSize() }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([recent.item.title, recent.inProgress ? recent.status?.statusLabel : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(recent.item.kind == .job ? "Opens the job" : "Opens the customer")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("drawer-recent-\(recent.item.id)")
    }

    // MARK: Bottom

    /// Screenshot only: `--paper-preview-gear-open` (with `--paper-preview-drawer-open`) opens the gear's menu.
    private var gearOpensForPreview: Bool {
        #if DEBUG
        PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-gear-open")
        #else
        false
        #endif
    }

    /// The ink New job commit and the Settings circle, pinned under the list. The gear wears saved
    /// work's dot when it needs the person, and says what is still on the phone.
    private var bottomControls: some View {
        HStack(alignment: .center, spacing: 12) {
            if let create { createCommit(create) } else { Spacer(minLength: 0) }
            // The gear sits at the bottom edge: its menu grows up so every row (saved work, Settings,
            // Edit menu) stays on screen and clear of the home indicator.
            ThorbisMenu(items: settingsItems, title: title, accessibilityLabel: "Settings and businesses",
                        opensOnAppear: gearOpensForPreview, arrowEdge: .bottom) {
                CreamCircleLabel(symbol: "gearshape", size: 44)
                    .overlay(alignment: .topTrailing) {
                        if savedWork?.needsPerson == true { DrawerDot().offset(x: -3, y: 3) }
                    }
            }
            .accessibilityValue(savedWork?.words ?? "")
            .accessibilityIdentifier("drawer-settings")
        }
        .padding(.horizontal, 4)
        .padding(.top, 10).padding(.bottom, 8)
    }

    private func createCommit(_ create: PaperCreateAction) -> some View {
        Button(action: create.run) {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                    .accessibilityHidden(true)
                Text(create.label).lineLimit(1).minimumScaleFactor(0.8)
            }
            .inkCommit(height: 44)
        }
        .buttonStyle(PressStyle())
        .contextMenu {
            ForEach(create.choices) { choice in
                Button(action: choice.run) { Label(choice.title, systemImage: choice.symbol) }
            }
        }
        .accessibilityIdentifier("drawer-new")
    }
}

// MARK: - The menu circle on pushed screens

/// The drawer as every screen in a phone place sees it, pushed screens included. Set by the phone
/// shell only (nil on iPad). Sheets and full-screen covers never show it: `ThorbisBackButton`
/// checks it is not inside a presentation, and customer mode clears it outright.
private struct PaperDrawerReachKey: EnvironmentKey {
    static let defaultValue: PaperDrawerControl? = nil
}
extension EnvironmentValues {
    var paperDrawerReach: PaperDrawerControl? {
        get { self[PaperDrawerReachKey.self] }
        set { self[PaperDrawerReachKey.self] = newValue }
    }
}

/// Reports whether the view sits inside a sheet or full-screen cover (any presented controller),
/// so a pushed screen there keeps Back alone.
struct PresentationProbe: UIViewRepresentable {
    @Binding var presented: Bool

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.report = { value in if presented != value { presented = value } }
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {}

    final class ProbeView: UIView {
        var report: ((Bool) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            var responder: UIResponder? = self
            while let next = responder?.next, !(next is UIViewController) { responder = next }
            let controller = responder?.next as? UIViewController
            let presented = controller?.presentingViewController != nil
            DispatchQueue.main.async { [weak self] in self?.report?(presented) }
        }
    }
}

/// The card's outline: a rounded rectangle grown past the view's frame by the safe areas, so the
/// card's rounded top and bottom sit at the screen's edges rather than under the status bar.
struct DrawerCardShape: InsettableShape {
    var radius: CGFloat
    var top: CGFloat
    var bottom: CGFloat
    var inset: CGFloat = 0

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let grown = CGRect(x: rect.minX + inset, y: rect.minY - top + inset,
                           width: rect.width - inset * 2, height: rect.height + top + bottom - inset * 2)
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: grown)
    }

    func inset(by amount: CGFloat) -> DrawerCardShape {
        var shape = self
        shape.inset += amount
        return shape
    }
}

/// Where the drawer stands: shut, open, or following a finger.
struct DrawerMotion {
    /// About 80% of the screen (Claude and ChatGPT leave a fifth of the card showing); full width
    /// at accessibility sizes, where the words need it.
    static func width(screen: CGFloat, accessibilitySize: Bool) -> CGFloat {
        accessibilitySize ? screen : (screen * 0.8).rounded()
    }

    /// The card's corner once open, close to the screen's own corner: Dynamic Island phones (top
    /// inset 59pt or more) round at about 55pt, notched phones at about 44pt, Home-button phones
    /// are square. Read from the safe area, not the private display-corner key.
    static func cornerRadius(topInset: CGFloat) -> CGFloat {
        if topInset >= 59 { return 55 }
        if topInset >= 44 { return 44 }
        return 16
    }

    /// 0 shut … 1 open, including a drag in progress.
    static func progress(open: Bool, drag: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return open ? 1 : 0 }
        let value = open ? 1 + min(0, drag) / width : max(0, drag) / width
        return min(1, max(0, value))
    }

    /// Whether a released drag leaves the drawer open: past a third, or flicked.
    static func settlesOpen(wasOpen: Bool, translation: CGFloat, predicted: CGFloat, width: CGFloat) -> Bool {
        if wasOpen { return !(translation < -width / 3 || predicted < -width / 2) }
        return translation > width / 3 || predicted > width / 2
    }
}
