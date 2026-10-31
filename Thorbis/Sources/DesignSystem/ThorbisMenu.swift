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
struct ThorbisMenuItem: Identifiable {
    let id = UUID()
    var title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var tint: Color? = nil
    var isSelected: Bool = false
    var isDisabled: Bool = false
    var role: ButtonRole? = nil
    var action: () -> Void

    init(_ title: String, icon: String? = nil, subtitle: String? = nil, tint: Color? = nil,
         isSelected: Bool = false, isDisabled: Bool = false, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
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

    /// Runs the row's action and dismisses. A menu is a one-shot choice.
    mutating func select(_ item: ThorbisMenuItem) {
        item.action()
        isPresented = false
    }
}

// MARK: - Menu

/// A custom dropdown, Linear-mobile style: a rounded card of rows that floats up from the
/// bottom (no system `Menu` chrome — no grey material, no caret). Icons left, a checkmark on
/// the chosen row, destructive rows in red. This replaces stock `Menu {}` everywhere.
///
/// The card is presented as a height-fitted sheet with a clear background, so the system gives
/// us free dimming, drag-to-dismiss, tap-outside-to-close and VoiceOver focus while we draw the
/// card ourselves.
struct ThorbisMenu<Label: View>: View {
    let items: [ThorbisMenuItem]
    /// A quiet caption above the rows (e.g. the thing being changed).
    var title: String? = nil
    var accessibilityLabel: String? = nil
    /// CustomerPresentation's stronger floor (rule 13): 17pt words, 56pt rows.
    var customerFacing = false
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
        .sheet(isPresented: $model.isPresented) {
            ThorbisMenuCard(items: items, title: title, customerFacing: customerFacing) { model.select($0) }
        }
    }

    private var button: some View {
        Button { model.isPresented = true } label: { label() }
            .buttonStyle(PressStyle())
    }
}

/// The floating card. Split out so previews and tests can show it directly.
struct ThorbisMenuCard: View {
    let items: [ThorbisMenuItem]
    var title: String? = nil
    var customerFacing = false
    let onSelect: (ThorbisMenuItem) -> Void
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var estimatedHeight: CGFloat {
        let rows = items.reduce(CGFloat(0)) { $0 + ($1.subtitle == nil ? 50 : 62) + (customerFacing ? 12 : 0) }
        let header: CGFloat = title == nil ? 0 : 32
        // Bias up with Dynamic Type so a fitted-height sheet never clips at large text; over-
        // estimating only leaves dim space above the bottom-anchored card.
        return (rows + header + 40) * dynamicTypeSize.sheetHeightScale
    }

    private var detents: Set<PresentationDetent> {
        if verticalSizeClass == .compact { return [.large] }
        return estimatedHeight <= 420 && !dynamicTypeSize.isAccessibilitySize
            ? [.height(estimatedHeight)] : [.medium, .large]
    }

    var body: some View {
        // The card hugs its rows, so every menu (Create, status, sections…) is exactly as tall as
        // what it offers instead of stretching to the sheet's estimated detent. It scrolls only
        // when the rows outgrow the screen.
        ViewThatFits(in: .vertical) {
            rows
            ScrollView { rows }
        }
        .padding(4)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.border))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 10)
        .presentationDetents(detents)
        .presentationBackground(.clear)
        .presentationDragIndicator(.hidden)
    }

    /// Planar rows with no rules between them; spacing and the press state separate them.
    private var rows: some View {
        VStack(spacing: 0) {
            if let title {
                Text(title)
                    .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 2)
            }
            ForEach(items) { item in
                Button { onSelect(item) } label: { row(item) }
                    .buttonStyle(RowPressStyle())
                    .disabled(item.isDisabled)
                    .opacity(item.isDisabled ? 0.4 : 1)
            }
        }
        .padding(.bottom, 4)
    }

    private func row(_ item: ThorbisMenuItem) -> some View {
        let destructive = item.role == .destructive
        let titleColor = destructive ? Theme.destructive : Theme.foreground
        return HStack(spacing: 12) {
            if let icon = item.icon {
                Image(systemName: icon).font(.system(size: 16))
                    .foregroundStyle(destructive ? Theme.destructive : (item.tint ?? Theme.muted))
                    .frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(Theme.font(customerFacing ? 17 : 15, weight: .medium)).foregroundStyle(titleColor)
                if let subtitle = item.subtitle {
                    Text(subtitle).font(Theme.font(customerFacing ? 17 : 13)).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 8)
            if item.isSelected {
                Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.brandText)
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: customerFacing ? 56 : (item.subtitle == nil ? 50 : 58))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(item.isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#if DEBUG
#Preview("ThorbisMenu card") {
    ThorbisMenuCard(items: [
        ThorbisMenuItem("On my way", icon: "location.fill", isSelected: true) {},
        ThorbisMenuItem("ETA 15 min", icon: "clock") {},
        ThorbisMenuItem("ETA 30 min", icon: "clock") {},
        ThorbisMenuItem("Cancel trip", icon: "xmark.circle", role: .destructive) {},
    ], title: "On my way") { _ in }
    .background(Theme.background)
}
#endif
