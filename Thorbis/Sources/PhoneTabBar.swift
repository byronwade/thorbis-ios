import SwiftUI
import UIKit

// MARK: - The choice: bottom bar or sidebar

/// How an iPhone moves between places (Paper 65 / 65A "Navigation: Sidebar | Bottom bar"). The
/// bottom bar is the phone's default, as in the field-service apps technicians already use one
/// handed; the sidebar is the floating drawer alone. iPad always keeps its own sidebar.
enum PhoneNavigationStyle: String, CaseIterable, Identifiable {
    case bottomBar, sidebar

    var id: String { rawValue }

    /// Kept apart from the menu layout's own key, so a layout saved by any build still decodes.
    static let key = "thorbis.phoneNavigation.v1"

    var title: String {
        switch self {
        case .bottomBar: "Bottom bar"
        case .sidebar: "Sidebar"
        }
    }

    /// What this device uses. iPad: the sidebar, always (even in a narrow window). The DEBUG design
    /// preview keeps the sidebar unless launched with `--paper-preview-nav bottom`, so UI tests that
    /// walk the drawer stay valid; it never reads or writes the saved choice.
    static func resolve(saved: String?, isPad: Bool, preview: Bool, previewFlag: String?) -> PhoneNavigationStyle {
        if isPad { return .sidebar }
        if preview { return previewFlag == "bottom" ? .bottomBar : .sidebar }
        return saved.flatMap(PhoneNavigationStyle.init(rawValue:)) ?? .bottomBar
    }

    /// `--paper-preview-nav <bottom|sidebar>`.
    static var previewFlag: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--paper-preview-nav"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    static var isPreview: Bool {
        #if DEBUG
        return PaperPreview.enabled
        #else
        return false
        #endif
    }
}

// MARK: - Which places are tabs

/// The bar's places for each role, ahead of More (which opens the drawer, the full menu). Kept
/// pure so it is unit-tested; it reads permissions only, never the job or customer lists.
enum PhoneTabs {
    /// Places in the bar; More is always the last item after them.
    static let maxPlaces = 4

    /// The places each role reaches for most, in bar order.
    static func wanted(_ role: WorkRole) -> [MenuItem] {
        switch role {
        case .technician, .office: [.schedule, .jobs, .customers, .inbox]
        case .owner: [.home, .schedule, .jobs, .money]
        }
    }

    /// The role's wanted places this person can open; a gap is filled from the role's next main
    /// drawer place (Paper 29N / 57N / 58N order). The office Dashboard stays first in More.
    static func tabs(role: WorkRole, opens: (MenuItem) -> Bool) -> [MenuItem] {
        var result = wanted(role).filter(opens)
        let fill = DrawerSections.paperLayout(role).primary.compactMap { entry -> MenuItem? in
            if case .place(let item) = entry { return item }
            return nil
        }
        for item in fill where result.count < maxPlaces {
            if role == .office && item == .home { continue }
            if !result.contains(item), opens(item) { result.append(item) }
        }
        return Array(result.prefix(maxPlaces))
    }
}

// MARK: - Paper 18A glyphs

extension PaperGlyph {
    /// Paper 18A's dock: 20pt glyphs stroked 1.6.
    static let tabCalendar = PaperGlyph(box: 20, [.rect(3, 4.5, 14, 12, rx: 2, 1.6), .stroke("M3 8.5H17", 1.6),
                                                  .stroke("M7 2.5V6M13 2.5V6", 1.6)])
    static let tabJobs = PaperGlyph(box: 20, [.rect(3, 6, 14, 10.5, rx: 2, 1.6),
                                              .stroke("M7.5 6V4.5C7.5 3.9 7.9 3.5 8.5 3.5H11.5C12.1 3.5 12.5 3.9 12.5 4.5V6", 1.6),
                                              .stroke("M3 10H17", 1.6)])
    static let tabPeople = PaperGlyph(box: 20, [.circle(7, 7.5, 2.6, 1.6), .circle(13.6, 8.5, 2.1, 1.6),
                                                .stroke("M2.8 16C3.4 13.8 5 12.5 7 12.5C9 12.5 10.6 13.8 11.2 16", 1.6),
                                                .stroke("M13.2 12.9C14.9 12.9 16.4 14 16.9 15.8", 1.6)])
    /// Paper 65's Navigation segments: the sidebar and the bottom bar marks (18pt, stroked 1.5).
    static let navSidebar = PaperGlyph(box: 18, [.rect(2.25, 3.25, 13.5, 11.5, rx: 2.5, 1.5), .stroke("M7 3.25V14.75", 1.5)])
    static let navBottomBar = PaperGlyph(box: 18, [.rect(2.25, 3.25, 13.5, 11.5, rx: 2.5, 1.5), .stroke("M2.25 11H15.75", 1.5)])
    /// The menu, last in the pill: three lines, as Shopify draws its own.
    static let tabMenu = PaperGlyph(box: 20, [.stroke("M3.5 5.5H16.5M3.5 10H16.5M3.5 14.5H16.5", 1.6)])
    static let tabMore = PaperGlyph(box: 20, [.circle(4.5, 10, 1.5), .circle(10, 10, 1.5), .circle(15.5, 10, 1.5)])

    /// A place's mark in the dock: 18A's own where it draws one, else the drawer's.
    static func tab(_ item: MenuItem) -> PaperGlyph {
        switch item {
        case .schedule: .tabCalendar
        case .jobs: .tabJobs
        case .customers: .tabPeople
        default: .place(symbol: item.symbol) ?? .tabMore
        }
    }
}

// MARK: - The bar

/// The phone's bottom bar, laid out as Shopify's mobile app lays out its own (owner's instruction,
/// 2026-11-19): three floating pieces in one row. A round Search button on the left, a pill of
/// icon-only places ending in the menu in the middle, and a round account button (the person's
/// initials, opening Settings) on the right. The place showing sits on a soft brand circle. No
/// words are drawn, as in Paper 18A; every item still names itself to VoiceOver and shows its
/// word large on a long press. Opaque card grounds, so list text never shows through.
struct PhoneTabBar: View {
    let tabs: [MenuItem]
    /// The place showing (a MenuItem id, "local-…" or "notifications").
    let current: String
    /// Messages wears the brand dot while unread notices wait.
    let messagesUnread: Bool
    let messagesUnreadCount: Int?
    /// The menu wears the dot for anything else in it that needs the person.
    let moreHasNews: Bool
    /// The person's initials for the account button.
    var initials: String = ""
    let select: (MenuItem) -> Void
    let openMore: () -> Void
    var openSearch: (() -> Void)? = nil
    var openAccount: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme

    /// The side margins: the standard 16.
    static let margin: CGFloat = 16
    /// The round buttons and the pill share one height.
    static let height: CGFloat = 56

    /// A place not in the bar (opened from the menu, a link or a notification) lights the menu.
    private var moreActive: Bool { !tabs.contains { $0.rawValue == current } }

    var body: some View {
        HStack(spacing: 8) {
            if let openSearch {
                roundButton(label: "Search", id: "bar-search", action: openSearch) {
                    PaperIcon(.search, size: 22, color: Theme.foreground)
                }
            }
            HStack(spacing: 0) {
                ForEach(tabs) { item in
                    let unread = item == .inbox && messagesUnread
                    itemButton(title: item.title, glyph: .tab(item), active: current == item.rawValue, dot: unread,
                               value: unread ? (messagesUnreadCount.map { "\($0) unread" } ?? "Unread") : nil,
                               id: "tabbar-\(item.rawValue)") { select(item) }
                }
                itemButton(title: "Menu", glyph: .tabMenu, active: moreActive, dot: moreHasNews,
                           value: moreHasNews ? "New items" : nil, id: "tabbar-more", action: openMore)
            }
            .padding(.horizontal, 4)
            .frame(height: Self.height)
            .background(Theme.card, in: Capsule())
            .overlay { Capsule().strokeBorder(Theme.border, lineWidth: 1).allowsHitTesting(false) }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.14), radius: 12, y: 8)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isTabBar)
            .accessibilityLabel("Tab bar")
            .accessibilityIdentifier("tabbar")
            if let openAccount {
                roundButton(label: "Settings", id: "bar-account", action: openAccount) {
                    Text(initials.isEmpty ? "You" : initials)
                        .font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.brandText)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .dynamicTypeSize(...DynamicTypeSize.large)
                        .frame(width: 40, height: 40)
                        .background(Theme.brandSurface, in: Circle())
                }
            }
        }
        .padding(.horizontal, Self.margin)
    }

    /// Search and the account: a card circle the pill's height, with the pill's border and shadow.
    private func roundButton(label: String, id: String, action: @escaping () -> Void,
                             @ViewBuilder content: () -> some View) -> some View {
        Button(action: action) {
            content()
                .frame(width: Self.height, height: Self.height)
                .background(Theme.card, in: Circle())
                .overlay { Circle().strokeBorder(Theme.border, lineWidth: 1).allowsHitTesting(false) }
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.14), radius: 12, y: 8)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func itemButton(title: String, glyph: PaperGlyph, active: Bool, dot: Bool, value: String?,
                            id: String, action: @escaping () -> Void) -> some View {
        let ink = active ? Theme.brandText : Theme.muted
        return Button(action: action) {
            PaperIcon(glyph, size: 22, color: ink)
                .frame(width: 28, height: 24)
                .overlay(alignment: .topTrailing) {
                    if dot {
                        Circle().fill(Theme.brand).frame(width: 8, height: 8)
                            .padding(1.5).background(Theme.card, in: Circle())
                            .offset(x: 4, y: -2)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: 44, height: 44)
                .background { if active { Circle().fill(Theme.brandSurface) } }
                // The whole slot takes the tap, not just the circle.
                .frame(maxWidth: .infinity, minHeight: Self.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(title)
        .accessibilityValue(value ?? "")
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
        .accessibilityShowsLargeContentViewer {
            PaperIcon(glyph, size: 22)
            Text(title)
        }
        .accessibilityIdentifier(id)
    }
}

// MARK: - Room under a place for the bar

private struct PhoneTabBarClearanceKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// How much a top-level place's content must clear at the bottom for the floating bar (0 when
    /// the bar is off or hidden). Pushed pages never read it.
    var phoneTabBarClearance: CGFloat {
        get { self[PhoneTabBarClearanceKey.self] }
        set { self[PhoneTabBarClearanceKey.self] = newValue }
    }
}

/// On a place's root (inside its stack, so pushed pages never get it): a clear bottom inset as tall
/// as the bar reaches above the safe area. Scroll content and pinned bars stack above it.
struct PhoneTabBarRootInset: ViewModifier {
    @Environment(\.phoneTabBarClearance) private var clearance

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: clearance).allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

extension View {
    func phoneTabBarRoot() -> some View { modifier(PhoneTabBarRootInset()) }
}

// MARK: - Scroll to top

/// Re-tapping the active tab at a place's root: the frontmost full-height scroll view goes back to
/// its top, as a status-bar tap does.
@MainActor
enum ScrollToTop {
    static func run() {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows).first(where: \.isKeyWindow) else { return }
        guard let scroll = largestScrollView(in: window, window: window) else { return }
        let top = CGPoint(x: scroll.contentOffset.x, y: -scroll.adjustedContentInset.top)
        scroll.setContentOffset(top, animated: true)
    }

    private static func largestScrollView(in view: UIView, window: UIWindow) -> UIScrollView? {
        var best: (UIScrollView, CGFloat)?
        func visit(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0.01 else { return }
            if let scroll = view as? UIScrollView, scroll.scrollsToTop,
               scroll.contentSize.height > scroll.bounds.height {
                let frame = scroll.convert(scroll.bounds, to: window).intersection(window.bounds)
                let area = frame.width * frame.height
                // Vertical lists only: a chip strip is wide and short.
                if frame.height > window.bounds.height * 0.4, area > (best?.1 ?? 0) { best = (scroll, area) }
            }
            view.subviews.forEach(visit)
        }
        visit(view)
        return best?.0
    }
}
