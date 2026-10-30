import SwiftUI

// Form-level controls that replace the remaining stock SwiftUI pieces: `Picker` (both the
// menu/wheel kind and the segmented kind) and `confirmationDialog`. Same Theme tokens, same
// Linear-mobile feel as ThorbisMenu/ThorbisSheet.

// MARK: - ThorbisSelect (replaces a menu/default `Picker`)

/// A select control that shows the chosen option's label and a `chevron.up.chevron.down`, and
/// opens a `ThorbisMenu` of the options. Use where a stock menu/default `Picker` used to sit.
///
/// With a `label` it renders as a bare row (`label … value ⌄`) that drops into a form; without
/// one it renders as a boxed control on the card fill for standalone use.
struct ThorbisSelect<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    /// A leading label; when set the control renders as a bare form row.
    var label: String? = nil
    /// Shown when the selection matches no option (e.g. an unset optional).
    var placeholder: String = "Select"
    var menuTitle: String? = nil

    private var currentLabel: String {
        options.first { $0.value == selection }?.label ?? placeholder
    }

    var body: some View {
        ThorbisMenu(
            items: options.map { option in
                ThorbisMenuItem(option.label, isSelected: option.value == selection) { selection = option.value }
            },
            title: menuTitle ?? label,
            accessibilityLabel: "\(menuTitle ?? label ?? "Select"), \(currentLabel)"
        ) {
            if let label {
                HStack(spacing: 8) {
                    Text(label).font(Theme.font(16)).foregroundStyle(Theme.foreground)
                    Spacer(minLength: 8)
                    Text(currentLabel).font(Theme.font(16)).foregroundStyle(Theme.muted).lineLimit(1)
                    chevron
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            } else {
                HStack(spacing: 8) {
                    Text(currentLabel).font(Theme.font(16)).foregroundStyle(Theme.foreground).lineLimit(1)
                    Spacer(minLength: 8)
                    chevron
                }
                .padding(.horizontal, 12).frame(minHeight: 44).contentShape(Rectangle())
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).stroke(Theme.border))
            }
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.muted)
    }
}

// MARK: - ThorbisSegmented (replaces a `.pickerStyle(.segmented)` `Picker`)

/// A pill segmented control: a track with the chosen segment raised as a card. For a small,
/// fixed set of choices (two to four) shown side by side.
struct ThorbisSegmented<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                verticalChoices
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 3) { choices(horizontal: true) }
                    verticalChoices
                }
            }
        }
        .padding(3)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var verticalChoices: some View {
        VStack(spacing: 3) { choices(horizontal: false) }
    }

    @ViewBuilder private func choices(horizontal: Bool) -> some View {
        ForEach(Array(options.enumerated()), id: \.offset) { _, option in
            let isOn = option.value == selection
            Button { selection = option.value } label: {
                Text(option.label)
                    .font(Theme.font(15, weight: .medium))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: horizontal, vertical: !horizontal)
                    .foregroundStyle(isOn ? Theme.foreground : Theme.muted)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(isOn ? Theme.card : .clear, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(isOn ? Theme.border : .clear))
                    .shadow(color: .black.opacity(isOn ? 0.06 : 0), radius: 3, y: 1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        }
    }
}

// MARK: - ThorbisConfirm (replaces `.confirmationDialog`)

/// One choice in a `thorbisConfirm`. `.destructive` draws a red filled button; otherwise it is
/// the ink commit. A Cancel row is added automatically.
struct ThorbisConfirmAction: Identifiable {
    let id = UUID()
    var title: String
    var role: ButtonRole? = nil
    var action: () -> Void

    init(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.action = action
    }
}

/// The confirm card: title, optional message, the action buttons, and Cancel. Drawn ourselves so
/// there is no system action-sheet chrome.
struct ThorbisConfirmCard: View {
    let title: String
    var message: String? = nil
    let actions: [ThorbisConfirmAction]
    let onChoose: (ThorbisConfirmAction) -> Void
    let onCancel: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        ScrollView {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Text(title).font(Theme.font(17, weight: .semibold)).foregroundStyle(Theme.foreground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message).font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

            VStack(spacing: 8) {
                ForEach(actions) { action in
                    Button { onChoose(action) } label: {
                        Text(action.title).font(Theme.font(17, weight: .medium))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity).frame(minHeight: 50).padding(.vertical, 6)
                            .foregroundStyle(Theme.onInk)
                            .background(action.role == .destructive ? Theme.destructive : Theme.ink,
                                        in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    }
                    .buttonStyle(PressStyle())
                }
                Button(action: onCancel) {
                    Text("Cancel").font(Theme.font(17, weight: .medium)).foregroundStyle(Theme.foreground)
                        .frame(maxWidth: .infinity).frame(minHeight: 50)
                        .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.border))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 10)
        // Fitted height, biased up for Dynamic Type; `.large` is the escape hatch so a long
        // title/message at an AX size can't clip the buttons.
        .presentationDetents(typeSize.isAccessibilitySize || verticalSizeClass == .compact
                             ? [.large] : [.height(estimatedHeight), .large])
        .presentationBackground(.clear)
        .presentationDragIndicator(.hidden)
    }

    private var estimatedHeight: CGFloat {
        let header: CGFloat = message == nil ? 52 : 86
        let buttons = CGFloat(actions.count + 1) * 58
        return (header + buttons + 44) * typeSize.sheetHeightScale
    }
}

extension View {
    /// Present a custom confirm sheet in place of `.confirmationDialog`. Destructive actions draw
    /// a red button; a Cancel is added for you.
    func thorbisConfirm(_ title: String, message: String? = nil, isPresented: Binding<Bool>,
                        actions: [ThorbisConfirmAction]) -> some View {
        sheet(isPresented: isPresented) {
            ThorbisConfirmCard(title: title, message: message, actions: actions,
                               onChoose: { action in isPresented.wrappedValue = false; action.action() },
                               onCancel: { isPresented.wrappedValue = false })
        }
    }

    /// Present a confirm sheet bound to an optional item, in place of
    /// `.confirmationDialog(..., presenting:)`. The sheet shows while `item` is non-nil and clears
    /// it on dismiss (so a swipe-away reads as Cancel).
    func thorbisConfirm<Item: Identifiable>(item: Binding<Item?>,
                                            title: @escaping (Item) -> String,
                                            message: ((Item) -> String)? = nil,
                                            actions: @escaping (Item) -> [ThorbisConfirmAction]) -> some View {
        sheet(item: item) { value in
            ThorbisConfirmCard(title: title(value), message: message?(value), actions: actions(value),
                               onChoose: { action in item.wrappedValue = nil; action.action() },
                               onCancel: { item.wrappedValue = nil })
        }
    }
}

#if DEBUG
#Preview("ThorbisSelect + Segmented") {
    struct Demo: View {
        @State private var kind = "service"
        @State private var account = "residential"
        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                Text("Kind").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                ThorbisSelect(options: [("service", "Service"), ("material", "Material"), ("fee", "Fee")],
                              selection: $kind, menuTitle: "Kind")
                Text("Account").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                ThorbisSegmented(options: [("residential", "Residential"), ("commercial", "Commercial")],
                                 selection: $account)
            }
            .padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.background)
        }
    }
    return Demo()
}

#Preview("ThorbisConfirm card") {
    ThorbisConfirmCard(title: "Remove this item from the price book?",
                       message: "It stays on past invoices and estimates.",
                       actions: [ThorbisConfirmAction("Remove", role: .destructive) {}],
                       onChoose: { _ in }, onCancel: {})
    .background(Theme.background)
}
#endif
