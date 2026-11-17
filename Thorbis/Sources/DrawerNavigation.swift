import SwiftUI
import UIKit

// MARK: - Phone drawer (simplified 2026-10-31, after owner feedback on build 125)
//
// The phone's navigation: a side drawer that slides in from the left and pushes the place showing to
// the right, where it waits as a rounded card. Paper v2 (Navigation 29N/57N/58N): the company and
// the + circle, Search or ask, the role's places in Paper's order, and the person at the foot.
// Every screen in a place offers the menu circle: roots in their header, pushed screens beside Back.
// An edge swipe opens it on a root; on a pushed screen the edge swipe stays Back.
// iPad at regular width keeps its sidebar (TabletRoot).

/// The round menu circle at the top left of every phone screen in a place. A small brand dot shows
/// only for unread Inbox notices or saved work that needs the person.
struct DrawerMenuCircle: View {
    let control: PaperDrawerControl
    var size: CGFloat = 44

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
    /// Paper v2's words: Dashboard, Messages, Team.
    static func title(_ item: MenuItem, role: WorkRole) -> String {
        item.title
    }
}

/// The drawer itself (Paper v2, Navigation 29N/57N/58N). `recents` and `openRecent` are kept so
/// callers compile; Paper's drawer lists no recent records.
struct AppDrawer: View {
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var api: APIClient
    @ObservedObject private var recordFavorites = ScopedRecordFavorites.shared
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
    let openFavorite: (ScopedRecordFavorites.Visible) -> Void
    var openSavedWork: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            // Closed, nothing is built: the header and an empty scroll view would still sit in the
            // accessibility tree behind the card.
            if showsRows {
                header
                searchField
                rows
            } else { Spacer(minLength: 0) }
            if showsControls { footer }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(Theme.foreground)
        // Paper v2 (29N/57N/58N): the drawer is the sidebar surface; the place it pushed aside is the card.
        .background(Theme.sidebar.ignoresSafeArea())
    }

    private var rows: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PlacesList(sections: sections, title: { DrawerPlaces.title($0, role: role) },
                           isCurrent: { current == $0.rawValue }, isCurrentLocal: { current == "local-\($0.rawValue)" },
                           count: count, idPrefix: "drawer", savedWork: savedWork,
                           openPlace: openPlace, openLocal: openLocal, openSavedWork: openSavedWork,
                           openFavorite: openFavorite)
            }
            .padding(.horizontal, 8)
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

    /// Paper v2: the company's initial on a brand square, its name at 17 Semibold (the workspace
    /// menu), and the + circle (New) at the trailing edge.
    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            ThorbisMenu(items: settingsItems, title: title, accessibilityLabel: "Workspace, \(title)") {
                HStack(spacing: 10) {
                    Text(String(title.prefix(1)).uppercased())
                        .font(Theme.font(14, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Theme.brand, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityHidden(true)
                    Text(title).font(Theme.font(17, weight: .semibold))
                        .lineLimit(typeSize.isAccessibilitySize ? 2 : 1).truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("drawer-workspace-menu")
            .accessibilityFocused(titleFocus)
            if showsControls, let create { newCircle(create) }
            if showsClose {
                Button(action: close) { CreamCircleLabel(symbol: "xmark", size: 44) }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Close menu")
                    .accessibilityIdentifier("drawer-close")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 16).padding(.bottom, 10)
    }

    /// Paper v2: "Search or ask" in a 42pt field on the card, under the header.
    private var searchField: some View {
        Button(action: search) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(Theme.muted)
                Text("Search or ask").font(Theme.font(15)).foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Search")
        .accessibilityIdentifier("drawer-search")
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    /// The + circle: New's choices in a menu, or New job straight away when there is only one.
    @ViewBuilder private func newCircle(_ create: PaperCreateAction) -> some View {
        let circle = Image(systemName: "plus").font(.system(size: 17, weight: .medium))
            .foregroundStyle(Theme.foreground)
            .frame(width: 44, height: 44)
            .background(Theme.card, in: Circle())
        if !create.choices.isEmpty {
            ThorbisMenu(items: create.choices.map { choice in
                ThorbisMenuItem(choice.title, icon: choice.symbol, isDisabled: !choice.enabled, action: choice.run)
            }, title: "New", accessibilityLabel: "New") { circle }
            .accessibilityIdentifier("drawer-new-menu")
        } else {
            Button(action: create.run) { circle }
                .buttonStyle(PressStyle())
                .accessibilityLabel("New")
                .accessibilityIdentifier("drawer-new-menu")
        }
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

    private var personName: String { session.user?.name ?? session.user?.email ?? "You" }
    private var personInitials: String {
        let words = personName.split(separator: " ").prefix(2)
        return words.map { String($0.prefix(1)) }.joined().uppercased()
    }
    private var roleWord: String {
        switch role {
        case .technician: "Technician"
        case .office: "Office"
        case .owner: "Owner"
        }
    }

    /// Paper v2: a hairline, then the person (initials on brand surface, name 15 Semibold, role 13),
    /// the bell (Messages) and the gear (Settings and businesses). The gear wears saved work's dot when
    /// it needs the person; its menu grows up, clear of the home indicator.
    private var footer: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(personInitials)
                .font(Theme.font(12, weight: .semibold)).foregroundStyle(Theme.brandText)
                .frame(width: 34, height: 34)
                .background(Theme.brandSurface, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(personName).font(Theme.font(15, weight: .semibold)).lineLimit(1)
                Text(roleWord).font(Theme.font(13)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if sections.places.contains(.inbox) {
                Button { openPlace(.inbox) } label: {
                    Image(systemName: "bell").font(.system(size: 17)).foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Notifications")
                .accessibilityIdentifier("drawer-notifications")
            }
            ThorbisMenu(items: settingsItems, title: title, accessibilityLabel: "Settings and businesses",
                        opensOnAppear: gearOpensForPreview, arrowEdge: .bottom) {
                Image(systemName: "gearshape").font(.system(size: 17)).foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
                    .overlay(alignment: .topTrailing) {
                        if savedWork?.needsPerson == true { DrawerDot().offset(x: -6, y: 6) }
                    }
            }
            .accessibilityValue(savedWork?.words ?? "")
            .accessibilityIdentifier("drawer-settings")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
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
