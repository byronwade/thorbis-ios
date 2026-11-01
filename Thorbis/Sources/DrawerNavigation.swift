import SwiftUI
import UIKit

// MARK: - Phone drawer (simplified 2026-10-31, after owner feedback on build 125)
//
// The phone's navigation: a side drawer that slides in from the left and pushes the place showing to
// the right, where it waits as a dimmed, rounded card. Calm like the Claude and ChatGPT drawers: a
// modest business name and Search, at most five places for the person's role, "All places" folded
// behind one row, a few recent records as plain words, then New job and the gear.
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
            PaperCircleLabel(symbol: "line.3.horizontal", size: size, fill: Theme.fill)
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

/// Which places the drawer lists, and where: the role's primary rows, any extra pins from Edit menu,
/// and everything else behind "All places". Pure, so the role table is unit-tested.
struct DrawerPlaces: Equatable {
    /// The one primary list, no header (at most `maxPrimary`).
    var primary: [MenuItem]
    /// Places the person pinned in Edit menu that do not fit the primary list.
    var pinned: [MenuItem]
    /// Everything else this person may open, behind "All places".
    var more: [MenuItem]

    static let maxPrimary = 5

    /// The primary rows each role starts from (owner feedback, 2026-10-31).
    /// - Technicians: their day, the jobs and customers it touches, and Inbox.
    /// - Office: the schedule they run, jobs, customers, money and Inbox.
    /// - Owners: Home already carries the day (who is out, the next visit, jobs without a time), so
    ///   the schedule sits under All places rather than a second "today" row beside Home.
    static func roleRows(_ role: WorkRole) -> [MenuItem] {
        switch role {
        case .technician: [.schedule, .jobs, .customers, .inbox]
        case .office: [.schedule, .jobs, .customers, .money, .inbox]
        case .owner: [.home, .jobs, .customers, .money, .inbox]
        }
    }

    /// The drawer's word for a place. Schedule is the same screen for everyone: technicians read it
    /// as their day ("Today"), office and owners as the schedule they run.
    static func title(_ item: MenuItem, role: WorkRole) -> String {
        item == .schedule ? (role == .technician ? "Today" : "Schedule") : item.title
    }

    /// - Parameters:
    ///   - tabs: the layout's pinned places (company or this phone).
    ///   - explicitPins: true when the person or company chose pins (not the role's defaults), so
    ///     only real choices add rows.
    ///   - roleDefaults: the role's default pinned places, which never count as a choice.
    static func make(role: WorkRole, tabs: [MenuItem], explicitPins: Bool, roleDefaults: [MenuItem] = [], hidden: Set<MenuItem>,
                     order: [MenuItem], access: PrimaryTabAccess, permitted: (MenuItem) -> Bool) -> DrawerPlaces {
        func opens(_ item: MenuItem) -> Bool {
            switch item {
            case .schedule: access.canOpen(.schedule)
            case .jobs: access.canOpen(.jobs)
            case .customers: access.canOpen(.customers)
            default: permitted(item) && MenuItem.listed(item, permitted: permitted) && !hidden.contains(item)
            }
        }
        var primary = roleRows(role).filter(opens)
        var pinned: [MenuItem] = []
        if explicitPins {
            // A pin that merely repeats the role's defaults (a company layout started from them keeps
            // Schedule beside an owner's Home) adds nothing.
            for item in tabs where opens(item) && !primary.contains(item) && !roleDefaults.contains(item) {
                if primary.count < maxPrimary { primary.append(item) } else { pinned.append(item) }
            }
        }
        let more = AppMenuContent.menu(tabs: primary + pinned, hidden: hidden, order: order, permitted: permitted)
            .filter { item in [.schedule, .jobs, .customers].contains(item) ? opens(item) : true }
        return DrawerPlaces(primary: primary, pinned: pinned, more: more)
    }
}

/// The drawer itself: the business name and Search on top, one short list of places, All places,
/// recent records, then a floating New job capsule and the gear circle.
struct AppDrawer: View {
    let title: String
    let role: WorkRole
    /// The place showing (a MenuItem id or "local-<section>").
    let current: String
    let places: DrawerPlaces
    let local: [LocalWorkspaceSection]
    let recents: [DrawerRecent]
    /// Inbox holds unread notices.
    let inboxUnread: Bool
    /// Saved work on this phone: its words go to the gear's VoiceOver value, its dot when it needs the person.
    var savedWork: AppBottomBar.Sync?
    var create: PaperCreateAction?
    /// The gear circle's menu: businesses, saved work, Add a business, Settings, Edit menu.
    let settingsItems: [ThorbisMenuItem]
    /// At accessibility sizes the drawer is full width, so it carries its own close circle.
    let showsClose: Bool
    /// False while the drawer sits closed under the card. Its scroll view, the capsule's context menu
    /// and the gear's popover are UIKit-hosted and stay in the accessibility tree even when the
    /// drawer is hidden, so nothing is built until the drawer can be seen.
    var showsControls = true
    var titleFocus: AccessibilityFocusState<Bool>.Binding
    let search: () -> Void
    let close: () -> Void
    let openPlace: (MenuItem) -> Void
    let openLocal: (LocalWorkspaceSection) -> Void
    let openRecent: (RecentItems.Item) -> Void

    /// All places stays folded unless the person opened it; remembered on this phone.
    @AppStorage("thorbis.drawer.allPlacesOpen") private var allPlacesOpen = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Row icons grow with the words beside them.
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 20
    @ScaledMetric(relativeTo: .body) private var iconColumn: CGFloat = 26
    /// Room under the last row for the capsule and gear, which grow with the text.
    @ScaledMetric(relativeTo: .body) private var bottomClearance: CGFloat = 110

    /// Words line up under the primary rows' labels: row padding, icon column, gap.
    private var textInset: CGFloat { 12 + iconColumn + 14 }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Closed, nothing is built: an empty scroll view would still sit in the accessibility tree.
            if showsControls { rows }
            if showsControls { bottomControls }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Theme.foreground)
        .background(Theme.card.ignoresSafeArea())
        #if DEBUG
        .onAppear {
            if PaperPreview.enabled, ProcessInfo.processInfo.arguments.contains("--paper-preview-drawer-all-places") { allPlacesOpen = true }
        }
        #endif
    }

    private var rows: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                ForEach(places.primary) { placeRow($0) }
                if hasMore { allPlacesRow }
                if allPlacesOpen, hasMore {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(places.more) { item in
                            plainRow(id: "drawer-\(item.rawValue)", title: DrawerPlaces.title(item, role: role),
                                     here: current == item.rawValue, dot: item == .inbox && inboxUnread) { openPlace(item) }
                        }
                        ForEach(local, id: \.self) { section in
                            plainRow(id: "drawer-local-\(section.rawValue)", title: section.title,
                                     here: current == "local-\(section.rawValue)", dot: false) { openLocal(section) }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if !places.pinned.isEmpty {
                    sectionLabel("Pinned")
                    ForEach(places.pinned) { placeRow($0) }
                }
                if !recents.isEmpty {
                    sectionLabel("Recents")
                    ForEach(recents.prefix(5)) { recentRow($0) }
                }
            }
            .padding(.horizontal, 12)
            // Room for the capsule and gear so the last rows scroll clear of them.
            .padding(.bottom, bottomClearance)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("drawer-rows")
        #if DEBUG
        .modifier(PaperPreviewScrollAnchor())
        #endif
    }

    private var hasMore: Bool { !places.more.isEmpty || !local.isEmpty }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(Theme.font(20, weight: .medium)).tracking(-0.2)
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                .truncationMode(.tail)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused(titleFocus)
            Spacer(minLength: 8)
            PaperCircleButton(symbol: "magnifyingglass", label: "Search", size: 44, fill: Theme.background, bordered: true, action: search)
                .accessibilityIdentifier("drawer-search")
            if showsClose {
                PaperCircleButton(symbol: "xmark", label: "Close menu", size: 44, fill: Theme.background, bordered: true, action: close)
                    .accessibilityIdentifier("drawer-close")
            }
        }
        .padding(.leading, 12)
        .padding(.top, 8).padding(.bottom, 16)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.font(13, weight: .medium))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 12)
            .padding(.top, 28).padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Rows

    /// A primary place (v2): its mark in a soft place hue, outlined at rest and filled when this is
    /// the place; the word stays cream or body and lifts to full type when here. No wash on the row.
    private func placeRow(_ item: MenuItem) -> some View {
        let here = current == item.rawValue
        let dot = item == .inbox && inboxUnread
        let title = DrawerPlaces.title(item, role: role)
        return Button { openPlace(item) } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: item.symbol)
                    .font(.system(size: iconSize, weight: .regular))
                    .symbolVariant(here ? .fill : .none)
                    .foregroundStyle(item.tint)
                    .frame(width: iconColumn)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Theme.font(17, weight: .medium))
                    .foregroundStyle(here ? Theme.foreground : Theme.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if dot { DrawerDot() }
            }
            .padding(.horizontal, 12).padding(.vertical, 2)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(dot ? "Unread" : "")
        .accessibilityAddTraits(here ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("drawer-\(item.rawValue)")
    }

    /// The last primary row: folds every other place in and out, in place.
    private var allPlacesRow: some View {
        Button {
            withAnimation(.easeOut(duration: 0.12)) { allPlacesOpen.toggle() }
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: iconSize, weight: .regular))
                    .foregroundStyle(Theme.markGrey)
                    .frame(width: iconColumn)
                    .accessibilityHidden(true)
                Text("All places").font(Theme.font(17, weight: .medium)).foregroundStyle(Theme.subtle)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .rotationEffect(.degrees(allPlacesOpen ? 0 : -90))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12).padding(.vertical, 2)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("All places")
        .accessibilityValue(allPlacesOpen ? "Expanded" : "Collapsed")
        .accessibilityHint(allPlacesOpen ? "Hides the other places" : "Shows every other place")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("drawer-all-places")
    }

    /// A place inside All places: 16pt words under the primary labels, no icon.
    private func plainRow(id: String, title: String, here: Bool, dot: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).font(Theme.font(16, weight: here ? .medium : .regular))
                    .foregroundStyle(here ? Theme.foreground : Theme.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if dot { DrawerDot() }
            }
            .padding(.leading, textInset).padding(.trailing, 12).padding(.vertical, 2)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(dot ? "Unread" : "")
        .accessibilityAddTraits(here ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(id)
    }

    /// A recent record as plain words, like ChatGPT's recents. A job under way wears its status glyph.
    private func recentRow(_ recent: DrawerRecent) -> some View {
        Button { openRecent(recent.item) } label: {
            HStack(alignment: .center, spacing: 10) {
                Text(recent.item.title)
                    .font(Theme.font(16))
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
                Spacer(minLength: 8)
                if recent.inProgress, let status = recent.status { StatusLabel(jobStatus: status, emphasis: .quiet).fixedSize() }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
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

    /// The ink New job capsule on the left and the gear on the right, over a fade. The gear wears
    /// saved work's dot when it needs the person, and says what is still on the phone.
    private var bottomControls: some View {
        HStack(alignment: .center, spacing: 12) {
            if let create { createCapsule(create) }
            Spacer(minLength: 0)
            // The gear sits at the bottom edge: its menu grows up so every row (saved work, Settings,
            // Edit menu) stays on screen and clear of the home indicator.
            ThorbisMenu(items: settingsItems, title: title, accessibilityLabel: "Settings and businesses",
                        opensOnAppear: gearOpensForPreview, arrowEdge: .bottom) {
                Image(systemName: "gearshape")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(Theme.foreground)
                    .frame(width: 48, height: 48)
                    .background(Theme.background, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
                    .overlay(alignment: .topTrailing) {
                        if savedWork?.needsPerson == true { DrawerDot().offset(x: -3, y: 3) }
                    }
                    .contentShape(Circle())
            }
            .accessibilityValue(savedWork?.words ?? "")
            .accessibilityIdentifier("drawer-settings")
        }
        .padding(.horizontal, 20)
        .padding(.top, 24).padding(.bottom, 8)
        .background {
            LinearGradient(stops: [.init(color: Theme.card.opacity(0), location: 0), .init(color: Theme.card, location: 0.45)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }

    private func createCapsule(_ create: PaperCreateAction) -> some View {
        Button(action: create.run) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil").font(.system(size: 16, weight: .medium))
                    .accessibilityHidden(true)
                Text(create.label).font(Theme.font(16, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(Theme.onInk)
            .padding(.horizontal, 18)
            .frame(minHeight: 48)
            .background(Theme.ink, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 0, y: 1)
            .contentShape(Capsule())
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
