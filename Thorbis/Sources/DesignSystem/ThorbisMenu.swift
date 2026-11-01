import SwiftUI

extension DynamicTypeSize {
    /// A rough multiplier for fitted-height sheets so they grow (and don't clip) at large text.
    /// Biased to over-estimate — extra height is harmless dim space; too little clips rows.
    var sheetHeightScale: CGFloat {
        switch self {
        case .xSmall, .small, .medium, .large: 1.0
        case .xLarge: 1.1
        case .xxLarge: 1.2
        case .xxxLarge: 1.35
        case .accessibility1: 1.6
        case .accessibility2: 1.9
        case .accessibility3: 2.2
        case .accessibility4: 2.5
        case .accessibility5: 2.8
        @unknown default: 1.35
        }
    }
}

// MARK: - Model

/// One row in a `ThorbisMenu`.
///
/// `role: .destructive` tints the row `Theme.destructive`. `isSelected` shows a trailing
/// checkmark. `tint` colours the leading mark only (a soft place-mark hue), never the word.
/// `status` leads the row with that status's `StatusGlyph` instead of an icon (the status picker);
/// the glyph is decorative there, the title already says where the job goes.
struct ThorbisMenuItem: Identifiable {
    let id = UUID()
    var title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var tint: Color? = nil
    var status: StatusTone? = nil
    var isSelected: Bool = false
    var isDisabled: Bool = false
    var role: ButtonRole? = nil
    var action: () -> Void

    init(_ title: String, icon: String? = nil, subtitle: String? = nil, tint: Color? = nil, status: StatusTone? = nil,
         isSelected: Bool = false, isDisabled: Bool = false, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.status = status
        self.subtitle = subtitle
        self.tint = tint
        self.isSelected = isSelected
        self.isDisabled = isDisabled
        self.role = role
        self.action = action
    }
}

/// Presentation state kept apart from the view so selection logic is unit-tested without UI.
struct ThorbisMenuModel {
    var isPresented = false
    /// The row chosen in an open popover; its action runs once the popover has gone, so an action
    /// that presents a sheet never collides with the closing menu.
    var pending: ThorbisMenuItem? = nil

    /// Runs the row's action and dismisses. A menu is a one-shot choice.
    mutating func select(_ item: ThorbisMenuItem) {
        item.action()
        isPresented = false
    }

    /// Popover path: close first, keep the choice for `finish()`.
    mutating func choose(_ item: ThorbisMenuItem) {
        pending = item
        isPresented = false
    }

    /// The popover has gone: run the kept choice, once.
    mutating func finish() {
        let item = pending
        pending = nil
        item?.action()
    }
}

// MARK: - Menu

/// v2 (design.thorbis.com Places, "A popover is one choice"): an anchored popover that grows from
/// the control that opened it, at overlay depth (the panel, radius 14, a real shadow; the only thing
/// that floats). Rows are about 44pt: a leading mark where it helps (a status's mark for the status
/// picker), the word, and a check on the current value. Destructive rows sit in their own group in
/// the danger tone. It replaces stock `Menu {}` everywhere.
///
/// It is a real `.popover` with compact adaptation, so tap-outside, VoiceOver's escape gesture and
/// focus come from the system; our panel replaces Liquid Glass (`presentationBackground`).
struct ThorbisMenu<Label: View>: View {
    let items: [ThorbisMenuItem]
    /// A quiet caption above the rows (e.g. the thing being changed).
    var title: String? = nil
    var accessibilityLabel: String? = nil
    /// CustomerPresentation's stronger floor (rule 13): 17pt words, 56pt rows.
    var customerFacing = false
    /// Screenshot-only: open on appear (preview flags).
    var opensOnAppear = false
    /// Where the popover's arrow sits. `.top` grows the menu down from its control, `.bottom` grows it
    /// up. Left nil (the default) it follows the control: down from the top half of the window, up
    /// from the bottom half, so a select low in a sheet (a long location list) opens where it has
    /// room instead of squeezing into the strip below it.
    var arrowEdge: Edge? = nil
    @ViewBuilder var label: () -> Label

    @State private var model = ThorbisMenuModel()

    var body: some View {
        Group {
            if let accessibilityLabel {
                button.accessibilityLabel(accessibilityLabel)
            } else {
                button
            }
        }
        .anchoredPopover(isPresented: $model.isPresented, arrowEdge: arrowEdge) {
            ThorbisMenuPanel(items: items, title: title, customerFacing: customerFacing,
                             onSelect: { model.choose($0) }, onClose: { model.isPresented = false })
                .onDisappear { model.finish() }
                .presentationCompactAdaptation(.popover)
                .presentationBackground(Theme.surface)
        }
        .task {
            guard opensOnAppear else { return }
            try? await Task.sleep(for: .milliseconds(900))
            model.isPresented = true
        }
    }

    private var button: some View {
        Button { ThorbisKeyboard.dismiss { model.isPresented = true } } label: { label() }
            .buttonStyle(PressStyle())
            .sensoryFeedback(.selection, trigger: model.isPresented) { _, open in open }
    }
}

/// Every anchored popover's direction (ThorbisMenu, JobStatusMenu, a list room's filter): it grows
/// down from a control in the top half of the window and up from one in the bottom half, so a
/// control low on the screen opens where there is room instead of squeezing into the strip below
/// it. An explicit `arrowEdge` wins (`.top` grows down, `.bottom` grows up).
struct AnchoredPopover<PopoverContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    var arrowEdge: Edge?
    var popoverContent: () -> PopoverContent
    @State private var inLowerHalf = false

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: Bool.self) { proxy in
                let height = ThorbisMenuWindow.height
                return height > 0 && proxy.frame(in: .global).midY > height / 2
            } action: { inLowerHalf = $0 }
            .onAppear { ThorbisKeyboard.watch() }
            .popover(isPresented: $isPresented, arrowEdge: arrowEdge ?? (inLowerHalf ? .bottom : .top)) { popoverContent() }
    }
}

/// Opening a popover is a move away from typing. With the keyboard up, a menu growing down from a
/// select under a focused field (the invite's Role) ended behind the keyboard, and putting the
/// keyboard away at the same moment let the sheet drop and cut the menu off at the screen's foot.
/// So the keyboard goes first, and the popover opens once the layout has settled, from where its
/// control now sits.
@MainActor enum ThorbisKeyboard {
    private static var visible = false
    private static var observers: [NSObjectProtocol] = []
    /// The latest `open` waiting for the keyboard and sheet to settle. A second tap replaces it
    /// instead of presenting now; hide can finish (and `visible` go false) before the wait is over.
    private static var pendingOpen: (@MainActor () -> Void)?

    /// Starts listening (idempotent); called at launch (`ThorbisApp.init`) and by every popover.
    static func watch() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { visible = true }
            },
            // Still up until hide *finishes*. `willHide` fires as the sheet starts dropping.
            center.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { visible = false }
            },
        ]
    }

    /// Runs `open` now, or after putting the keyboard away and letting the screen settle.
    static func dismiss(then open: @escaping @MainActor () -> Void) {
        watch()
        if pendingOpen != nil {
            pendingOpen = open
            return
        }
        guard visible else { open(); return }
        pendingOpen = open
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            let work = pendingOpen
            pendingOpen = nil
            work?()
        }
    }
}

extension View {
    /// A `.popover` that opens toward the room it has (see `AnchoredPopover`).
    func anchoredPopover<PopoverContent: View>(isPresented: Binding<Bool>, arrowEdge: Edge? = nil,
                                               @ViewBuilder content: @escaping () -> PopoverContent) -> some View {
        modifier(AnchoredPopover(isPresented: isPresented, arrowEdge: arrowEdge, popoverContent: content))
    }
}

/// The key window's height, in the global coordinate space SwiftUI reports frames in.
@MainActor enum ThorbisMenuWindow {
    static var height: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        return window?.bounds.height ?? 0
    }
}

/// The popover's content: an optional caption, the rows, and destructive rows in their own group.
/// Sized to its rows (about 260pt wide, wider at accessibility sizes) and scrolls only when it
/// would outgrow the screen.
struct ThorbisMenuPanel: View {
    let items: [ThorbisMenuItem]
    var title: String? = nil
    var customerFacing = false
    let onSelect: (ThorbisMenuItem) -> Void
    var onClose: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private var width: CGFloat {
        if customerFacing || typeSize.isAccessibilitySize { return 340 }
        return typeSize >= .xxLarge ? 300 : 264
    }

    private var estimatedHeight: CGFloat {
        let row: CGFloat = customerFacing ? 58 : 46
        let rows = items.reduce(CGFloat(0)) { $0 + ($1.subtitle == nil ? row : row + 16) }
        return (rows + (title == nil ? 12 : 44) + 16) * typeSize.sheetHeightScale
    }

    var body: some View {
        Group {
            if estimatedHeight > 460 {
                ScrollView { ThorbisMenuRows(items: items, title: title, customerFacing: customerFacing, onSelect: onSelect) }
                    .frame(height: 460)
            } else {
                ThorbisMenuRows(items: items, title: title, customerFacing: customerFacing, onSelect: onSelect)
            }
        }
        .frame(width: width)
        // design.thorbis.com Motion: a menu fades in at 120ms ease-out; it does not fly.
        .opacity(shown || reduceMotion ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.12)) { shown = true } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title ?? "Menu")
        .accessibilityAction(.escape) { onClose() }
    }
}

/// The rows themselves, shared by the popover and by `ThorbisMenuCard` (a menu shown in a sheet).
struct ThorbisMenuRows: View {
    let items: [ThorbisMenuItem]
    var title: String? = nil
    var customerFacing = false
    let onSelect: (ThorbisMenuItem) -> Void
    @ScaledMetric(relativeTo: .body) private var glyphColumn: CGFloat = 20

    private var regular: [ThorbisMenuItem] { items.filter { $0.role != .destructive } }
    private var destructive: [ThorbisMenuItem] { items.filter { $0.role == .destructive } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(customerFacing ? Theme.customerFont(17, weight: .medium) : Theme.font(13, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            group(regular)
            if !destructive.isEmpty {
                // Destructive choices sit apart: space, not a line.
                if !regular.isEmpty { Color.clear.frame(height: 8).accessibilityHidden(true) }
                group(destructive)
            }
        }
        .padding(6)
    }

    private func group(_ rows: [ThorbisMenuItem]) -> some View {
        ForEach(rows) { item in
            Button { onSelect(item) } label: { row(item) }
                .buttonStyle(MenuRowPressStyle())
                .disabled(item.isDisabled)
                .opacity(item.isDisabled ? 0.4 : 1)
        }
    }

    private func row(_ item: ThorbisMenuItem) -> some View {
        let isDestructive = item.role == .destructive
        let titleColor = isDestructive ? Theme.destructive : Theme.foreground
        return HStack(spacing: 10) {
            if let status = item.status {
                StatusGlyph(tone: status, label: item.title, size: 14)
                    .accessibilityHidden(true)
                    .frame(width: glyphColumn)
            } else if let icon = item.icon {
                Image(systemName: icon).font(.system(size: 15, weight: .regular))
                    .foregroundStyle(isDestructive ? Theme.destructive : (item.tint ?? Theme.muted))
                    .frame(width: glyphColumn)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(customerFacing ? Theme.customerFont(17, weight: .medium) : Theme.font(16))
                    .foregroundStyle(titleColor)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = item.subtitle {
                    Text(subtitle).font(customerFacing ? Theme.customerFont(17) : Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if item.isSelected {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.brandText)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: customerFacing ? 56 : 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(item.isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A menu shown as a bottom sheet by callers that own their presentation (Create, the dispatch
/// board's job menu). v2: a clean system sheet on the panel, its title at 17 Medium and the rows
/// filling it; no floating card inside the sheet, no glass.
struct ThorbisMenuCard: View {
    let items: [ThorbisMenuItem]
    var title: String? = nil
    var customerFacing = false
    let onSelect: (ThorbisMenuItem) -> Void
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var estimatedHeight: CGFloat {
        let rows = items.reduce(CGFloat(0)) { $0 + ($1.subtitle == nil ? 46 : 62) + (customerFacing ? 12 : 0) }
        let header: CGFloat = title == nil ? 28 : 64
        return (rows + header + 40) * dynamicTypeSize.sheetHeightScale
    }

    private var detents: Set<PresentationDetent> {
        if verticalSizeClass == .compact { return [.large] }
        return estimatedHeight <= 520 && !dynamicTypeSize.isAccessibilitySize
            ? [.height(estimatedHeight)] : [.medium, .large]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if let title {
                    Text(title).font(Theme.font(17, weight: .medium)).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.gutter - 6)
                        .accessibilityAddTraits(.isHeader)
                }
                ThorbisMenuRows(items: items, customerFacing: customerFacing, onSelect: onSelect)
            }
            .padding(.horizontal, 6).padding(.top, 20).padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.surface)
        .presentationDetents(detents)
        .presentationBackground(Theme.surface)
        .presentationCornerRadius(Theme.cardRadius + 6)
        .presentationDragIndicator(.visible)
    }
}

/// A menu row's press: a rounded `fill` highlight inside the panel (hover is a quieter fill).
struct MenuRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.fill : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }
}

#if DEBUG
#Preview("ThorbisMenu panel") {
    ThorbisMenuPanel(items: [
        ThorbisMenuItem("Dispatched", status: .dispatched, isSelected: true) {},
        ThorbisMenuItem("On my way", status: .dispatched) {},
        ThorbisMenuItem("Start work", status: .inProgress) {},
        ThorbisMenuItem("Cancel trip", icon: "xmark.circle", role: .destructive) {},
    ], title: "Status") { _ in }
    .background(Theme.surface)
}
#endif
