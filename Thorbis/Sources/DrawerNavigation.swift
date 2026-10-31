import SwiftUI

// MARK: - Phone drawer (2026-10-31, after the Claude and ChatGPT iOS apps)
//
// The phone's navigation: a side drawer that slides in from the left and pushes the place showing to
// the right, where it waits as a rounded card. Each place root has a menu circle at top left; an edge
// swipe on a root opens the drawer too. Pushed screens keep the system back swipe and never open it.
// iPad at regular width keeps its sidebar (TabletRoot).

/// The round menu circle at the top left of every phone place root. A small brand dot shows when
/// anything in the drawer carries one.
struct DrawerMenuCircle: View {
    let control: PaperDrawerControl

    var body: some View {
        Button(action: control.open) {
            PaperCircleLabel(symbol: "line.3.horizontal", size: 40, fill: Theme.fill)
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

/// The small brand dot for unread or needs-attention items (ChatGPT's drawer dot).
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
    /// In progress, or a change to it waiting on this phone: the row turns a small spinner.
    var busy = false
    /// The job changed since it was last seen in this list.
    var changed = false
    var id: String { "\(item.kind.rawValue)-\(item.id)" }
}

/// The drawer itself: the business name and Search on top, the job on now, the pinned places, the
/// other places, recent records, then a floating New job capsule and the settings circle.
struct AppDrawer: View {
    let title: String
    /// The place showing (a MenuItem id or "local-<section>").
    let current: String
    var now: (job: Job, customer: String)?
    var savedWork: AppBottomBar.Sync?
    let pinned: [MenuItem]
    let places: [MenuItem]
    let local: [LocalWorkspaceSection]
    let recents: [DrawerRecent]
    let dots: Set<MenuItem>
    var create: PaperCreateAction?
    /// The gear circle's menu: businesses, Add a business, Settings, Edit menu.
    let settingsItems: [ThorbisMenuItem]
    /// At accessibility sizes the drawer is full width, so it carries its own close circle.
    let showsClose: Bool
    var titleFocus: AccessibilityFocusState<Bool>.Binding
    let search: () -> Void
    let close: () -> Void
    let openPlace: (MenuItem) -> Void
    let openLocal: (LocalWorkspaceSection) -> Void
    let openNow: () -> Void
    let openSavedWork: () -> Void
    let openRecent: (RecentItems.Item) -> Void
    let editMenu: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    /// Row icons grow with the words beside them.
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 20
    @ScaledMetric(relativeTo: .body) private var iconColumn: CGFloat = 28

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if let now { nowRow(now.job, customer: now.customer) }
                    if let savedWork { savedWorkRow(savedWork) }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(pinned) { placeRow($0) }
                    }
                    .padding(.top, 8)
                    if !places.isEmpty || !local.isEmpty {
                        sectionLabel("Places")
                        ForEach(places) { placeRow($0) }
                        ForEach(local, id: \.self) { localRow($0) }
                    }
                    row(id: "drawer-edit-menu", symbol: "slider.horizontal.3", title: "Edit menu", action: editMenu)
                    if !recents.isEmpty {
                        sectionLabel("Recents")
                        ForEach(recents) { recentRow($0) }
                    }
                }
                .padding(.horizontal, 12)
                // Room for the capsule and gear so the last rows scroll clear of them.
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            #if DEBUG
            .modifier(PaperPreviewScrollAnchor())
            #endif
            bottomControls
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.card.ignoresSafeArea())
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(Theme.font(30, weight: .semibold)).tracking(-0.6)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused(titleFocus)
            Spacer(minLength: 8)
            PaperCircleButton(symbol: "magnifyingglass", label: "Search", size: 48, fill: Theme.background, bordered: true, action: search)
                .accessibilityIdentifier("drawer-search")
            if showsClose {
                PaperCircleButton(symbol: "xmark", label: "Close menu", size: 48, fill: Theme.background, bordered: true, action: close)
                    .accessibilityIdentifier("drawer-close")
            }
        }
        .padding(.leading, 12)
        .padding(.top, 8).padding(.bottom, 12)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.font(17, weight: .semibold))
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 12)
            .padding(.top, 24).padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Rows

    /// The job this person is on now (the in-app twin of the Live Activity).
    private func nowRow(_ job: Job, customer: String) -> some View {
        Button(action: openNow) {
            HStack(alignment: .center, spacing: 14) {
                StatusGlyph(jobStatus: job.status)
                    .frame(width: iconColumn)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Now · \(job.status.statusLabel)")
                        .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                    Text(job.title).font(Theme.font(17, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    if !customer.isEmpty {
                        Text(customer).font(Theme.font(15)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                PaperDisclosure()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current job, \(job.title), \(job.status.statusLabel)\(customer.isEmpty ? "" : ", \(customer)")")
        .accessibilityHint("Opens the job")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("drawer-now")
        .padding(.bottom, 4)
    }

    /// Changes kept on this phone until they reach the office; opens the review.
    private func savedWorkRow(_ sync: AppBottomBar.Sync) -> some View {
        Button(action: openSavedWork) {
            rowBody(symbol: sync.needsPerson ? "exclamationmark.triangle" : "arrow.triangle.2.circlepath",
                    title: "Saved on this phone", subtitle: sync.words, here: false) {
                if case .syncing = sync { SpinnerArc(tint: Theme.success).frame(width: 18, height: 18) }
                if sync.needsPerson { DrawerDot() }
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Saved on this phone, \(sync.words)")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("drawer-saved-work")
    }

    private func placeRow(_ item: MenuItem) -> some View {
        Button { openPlace(item) } label: {
            rowBody(symbol: item.symbol, title: item.drawerTitle, subtitle: nil,
                    here: current == item.rawValue) {
                if dots.contains(item) { DrawerDot() }
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.drawerTitle)
        .accessibilityValue(dots.contains(item) ? "New" : "")
        .accessibilityAddTraits(current == item.rawValue ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("drawer-\(item.rawValue)")
    }

    private func localRow(_ section: LocalWorkspaceSection) -> some View {
        let id = "local-\(section.rawValue)"
        return Button { openLocal(section) } label: {
            rowBody(symbol: section.moreSymbol, title: section.title, subtitle: nil, here: current == id) { EmptyView() }
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(current == id ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("drawer-\(id)")
    }

    private func row(id: String, symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowBody(symbol: symbol, title: title, subtitle: nil, here: false) { EmptyView() }
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(id)
    }

    /// A recent record: jobs lead with their status glyph (it carries the status); customers are
    /// words only, like ChatGPT's recents.
    private func recentRow(_ recent: DrawerRecent) -> some View {
        Button { openRecent(recent.item) } label: {
            HStack(alignment: .center, spacing: 14) {
                if let status = recent.status {
                    StatusGlyph(jobStatus: status).frame(width: iconColumn)
                }
                Text(recent.item.title)
                    .font(Theme.font(17))
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
                Spacer(minLength: 8)
                if recent.busy { SpinnerArc().frame(width: 18, height: 18) }
                if recent.changed { DrawerDot() }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([recent.item.title, recent.status?.statusLabel, recent.busy && recent.status != "in_progress" ? "waiting to sync" : nil,
                             recent.changed ? "changed" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(recent.item.kind == .job ? "Opens the job" : "Opens the customer")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("drawer-recent-\(recent.item.id)")
    }

    /// One drawer row: an outline icon and a 17pt label on the drawer's ground, no card or well.
    /// The place showing sits on a soft fill. Words wrap at large sizes.
    private func rowBody<Trailing: View>(symbol: String, title: String, subtitle: String?, here: Bool,
                                         @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: here ? .medium : .regular))
                .frame(width: iconColumn)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.font(17, weight: here ? .medium : .regular))
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle).font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background { if here { RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).fill(Theme.fill) } }
        .contentShape(Rectangle())
    }

    // MARK: Bottom

    /// The ink New job capsule on the left and the gear on the right, over a fade.
    private var bottomControls: some View {
        HStack(alignment: .center, spacing: 12) {
            if let create { createCapsule(create) }
            Spacer(minLength: 0)
            ThorbisMenu(items: settingsItems, title: title, accessibilityLabel: "Settings and businesses") {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Theme.foreground)
                    .frame(width: 52, height: 52)
                    .background(Theme.background, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
                    .contentShape(Circle())
            }
            .accessibilityIdentifier("drawer-settings")
        }
        .padding(.horizontal, 20)
        .padding(.top, 28).padding(.bottom, 8)
        .background {
            LinearGradient(stops: [.init(color: Theme.card.opacity(0), location: 0), .init(color: Theme.card, location: 0.45)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }

    private func createCapsule(_ create: PaperCreateAction) -> some View {
        Button(action: create.run) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil").font(.system(size: 18, weight: .medium))
                    .accessibilityHidden(true)
                Text(create.label).font(Theme.font(17, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(Theme.onInk)
            .padding(.horizontal, 22)
            .frame(minHeight: 52)
            .background(Theme.ink, in: Capsule())
            .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
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
    static func width(screen: CGFloat, accessibilitySize: Bool) -> CGFloat {
        accessibilitySize ? screen : min(screen - 84, 360)
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
