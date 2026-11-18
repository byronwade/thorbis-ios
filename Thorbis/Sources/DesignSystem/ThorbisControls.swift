import SwiftUI

// Form-level controls that replace the remaining stock SwiftUI pieces: `Picker` (both the
// menu/wheel kind and the segmented kind) and `confirmationDialog`. Same Theme tokens, same
// Linear-mobile feel as ThorbisMenu/ThorbisSheet.

// MARK: - Placeholders

extension Text {
    /// A text field's placeholder (`prompt:`): an example in the secondary text token (`Theme.muted`,
    /// 4.5:1 on the field well in both themes). Always verbatim: a `Text("…")` literal is a localized
    /// Markdown key, so an example like "mike@reyesplumbing.com" became a link and took the app's
    /// tint (blue) once the field was focused. Use this for every `TextField` prompt.
    static func placeholder<S: StringProtocol>(_ example: S) -> Text {
        Text(verbatim: String(example)).foregroundStyle(Theme.muted)
    }
}

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
                // A select is a well with the text field's own measures (Paper "Picker": 50 tall, radius 14).
                .fieldWell().contentShape(Rectangle())
            }
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.muted)
    }
}

// MARK: - ThorbisSegmented (replaces a `.pickerStyle(.segmented)` `Picker`)

/// A segmented control with Paper's one track (DS board, 20A "Sort by"; the same as `PaperTabs` and
/// `PaperSheetSegments`): radius 11, 2 inside it the chosen segment raised on a 36-tall, 9-radius
/// tile; 14 Semibold when chosen, 14 Medium otherwise. 44 to the finger. For a small, fixed set of
/// choices (two to four) shown side by side.
struct ThorbisSegmented<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                verticalChoices
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) { choices(horizontal: true) }
                    verticalChoices
                }
            }
        }
        .padding(2)
        .background(Theme.quietFill, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .animation(Theme.selectionSpring(reduceMotion: reduceMotion), value: selection)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var verticalChoices: some View {
        VStack(spacing: 2) { choices(horizontal: false) }
    }

    @ViewBuilder private func choices(horizontal: Bool) -> some View {
        ForEach(Array(options.enumerated()), id: \.offset) { _, option in
            let isOn = option.value == selection
            Button { selection = option.value } label: {
                Text(option.label)
                    .font(Theme.font(14, weight: isOn ? .semibold : .medium))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: horizontal, vertical: !horizontal)
                    .foregroundStyle(isOn ? Theme.foreground : Theme.subtle)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background {
                        if isOn {
                            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.selectedSegment)
                                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Rectangle().inset(by: -4))
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

/// The confirm modal (Paper P4 Confirm): centred on the panel, a destructive choice leads with
/// its mark in a 52pt red-surface circle, then the question as a 20 Bold title that names the
/// thing and one 15pt muted line that says what happens. One choice sits beside Cancel as two
/// 50pt pills (the red one repeats the verb); several choices stack above Cancel.
struct ThorbisConfirmCard: View {
    let title: String
    var message: String? = nil
    let actions: [ThorbisConfirmAction]
    let onChoose: (ThorbisConfirmAction) -> Void
    let onCancel: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var destructive: ThorbisConfirmAction? { actions.first { $0.role == .destructive } }
    /// Two pills side by side only when there is one choice and the type is not enlarged.
    private var sideBySide: Bool { actions.count == 1 && !typeSize.isAccessibilitySize }
    /// The bin for a delete or remove; a warning triangle for any other destructive choice.
    private var markSymbol: String {
        let word = (destructive?.title ?? "").lowercased()
        return word.hasPrefix("delete") || word.hasPrefix("remove") ? "trash" : "exclamationmark.triangle"
    }

    var body: some View {
        // Only the words scroll. The choices stay pinned under them, so at an accessibility size a
        // long title or message can never push Cancel or the action below the screen.
        VStack(spacing: 20) {
            ScrollView {
                VStack(spacing: 10) {
                    if destructive != nil {
                        Image(systemName: markSymbol)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Theme.destructive)
                            .frame(width: 52, height: 52)
                            .background(Theme.destructiveSurface, in: Circle())
                            .padding(.bottom, 4)
                            .accessibilityHidden(true)
                    }
                    Text(title).font(Theme.font(20, weight: .bold)).foregroundStyle(Theme.foreground)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let message {
                        Text(message).font(Theme.font(15)).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
            }
            .scrollBounceBehavior(.basedOnSize)

            if sideBySide {
                HStack(spacing: 10) {
                    cancelButton
                    ForEach(actions) { action in choiceButton(action) }
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(actions) { action in choiceButton(action) }
                    cancelButton
                }
            }
        }
        .padding(.horizontal, Theme.gutter).padding(.bottom, 8)
        .background(Theme.surface)
        // Fitted height, biased up for Dynamic Type; `.large` is the escape hatch so a long
        // title/message at an AX size can't clip the buttons.
        .thorbisSheetPresentation(typeSize.isAccessibilitySize || verticalSizeClass == .compact
                                  ? [.large] : [.height(estimatedHeight), .large])
    }

    private func choiceButton(_ action: ThorbisConfirmAction) -> some View {
        Button { onChoose(action) } label: {
            if action.role == .destructive {
                Text(action.title).dangerCommit()
            } else {
                Text(action.title).inkCommit()
            }
        }
        .buttonStyle(PressStyle())
    }

    private var cancelButton: some View {
        Button(action: onCancel) {
            Text("Cancel").paperButton(.commit, tone: .quiet, fills: true)
        }
        .buttonStyle(PressStyle())
    }

    private var estimatedHeight: CGFloat {
        let mark: CGFloat = destructive == nil ? 0 : 66
        let words: CGFloat = message == nil ? 56 : 124
        let buttons: CGFloat = actions.count == 1 ? 50 : CGFloat(actions.count) * 60 + 50
        return (24 + mark + words + 20 + buttons + 36) * typeSize.sheetHeightScale
    }
}

/// The reason field of a confirm-with-reason: its label above the well, an example inside it, and
/// whether the action needs an answer.
struct ThorbisConfirmReason {
    var label: String = "Reason"
    var placeholder: String = ""
    /// When true the action is still pressable; pressed with no reason it says what is missing
    /// under the field and does not run.
    var required = false
    var missingMessage: String = "Add a reason."
    var identifier: String = "confirm-reason"
}

/// The confirm modal with a reason (Paper P4 Confirm plus a field): the mark for a destructive
/// choice, the 20 Bold question, one 15pt muted line, then a labelled reason field (13 Semibold
/// label, 50pt well), and Cancel beside the action as two 50pt pills. The words and the field
/// scroll; the pills stay pinned above the keyboard. The action gets the trimmed reason.
struct ThorbisReasonConfirmCard: View {
    let title: String
    var message: String? = nil
    var reason = ThorbisConfirmReason()
    let actionTitle: String
    var role: ButtonRole? = nil
    let onChoose: (String) -> Void
    let onCancel: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var text = ""
    @State private var showMissing = false
    @FocusState private var focused: Bool

    private var isDestructive: Bool { role == .destructive }
    private var markSymbol: String {
        let word = actionTitle.lowercased()
        return word.hasPrefix("delete") || word.hasPrefix("remove") ? "trash" : "exclamationmark.triangle"
    }
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 20) {
            ScrollView {
                VStack(spacing: 10) {
                    if isDestructive {
                        Image(systemName: markSymbol)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Theme.destructive)
                            .frame(width: 52, height: 52)
                            .background(Theme.destructiveSurface, in: Circle())
                            .padding(.bottom, 4)
                            .accessibilityHidden(true)
                    }
                    Text(title).font(Theme.font(20, weight: .bold)).foregroundStyle(Theme.foreground)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let message {
                        Text(message).font(Theme.font(15)).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(reason.label).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                            .padding(.horizontal, 4)
                        TextField(reason.label, text: $text, prompt: .placeholder(reason.placeholder))
                            .font(Theme.font(16)).foregroundStyle(Theme.foreground)
                            .focused($focused)
                            .submitLabel(.done)
                            .onSubmit { focused = false }
                            .fieldWell()
                            .accessibilityIdentifier(reason.identifier)
                        if showMissing && trimmed.isEmpty {
                            FieldProblem(message: reason.missingMessage)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)

            if typeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    actionButton
                    cancelButton
                }
            } else {
                HStack(spacing: 10) {
                    cancelButton
                    actionButton
                }
            }
        }
        .padding(.horizontal, Theme.gutter).padding(.bottom, 8)
        .background(Theme.surface)
        // Half height leaves room for the field; the system lifts the sheet over the keyboard and
        // the pills ride above it. Full height at accessibility sizes and in landscape.
        .thorbisSheetPresentation(typeSize.isAccessibilitySize || verticalSizeClass == .compact
                                  ? [.large] : [.medium, .large])
    }

    private var actionButton: some View {
        Button {
            if reason.required && trimmed.isEmpty {
                showMissing = true
                focused = true
            } else {
                onChoose(trimmed)
            }
        } label: {
            if isDestructive {
                Text(actionTitle).dangerCommit()
            } else {
                Text(actionTitle).inkCommit()
            }
        }
        .buttonStyle(PressStyle())
    }

    private var cancelButton: some View {
        Button(action: onCancel) {
            Text("Cancel").paperButton(.commit, tone: .quiet, fills: true)
        }
        .buttonStyle(PressStyle())
    }
}

extension View {
    /// Present a confirm sheet that asks for a reason, in place of an alert with a text field. The
    /// action gets the trimmed reason (empty when none was typed and it is not required).
    func thorbisConfirm(_ title: String, message: String? = nil, isPresented: Binding<Bool>,
                        reason: ThorbisConfirmReason, actionTitle: String, role: ButtonRole? = nil,
                        action: @escaping (String) -> Void) -> some View {
        sheet(isPresented: isPresented) {
            ThorbisReasonConfirmCard(title: title, message: message, reason: reason,
                                     actionTitle: actionTitle, role: role,
                                     onChoose: { typed in isPresented.wrappedValue = false; action(typed) },
                                     onCancel: { isPresented.wrappedValue = false })
        }
    }

    /// The same, bound to an optional item: shows while `item` is non-nil and clears it on dismiss
    /// (a swipe-away reads as Cancel).
    func thorbisConfirm<Item: Identifiable>(item: Binding<Item?>,
                                            title: @escaping (Item) -> String,
                                            message: ((Item) -> String)? = nil,
                                            reason: ThorbisConfirmReason,
                                            actionTitle: String, role: ButtonRole? = nil,
                                            action: @escaping (Item, String) -> Void) -> some View {
        sheet(item: item) { value in
            ThorbisReasonConfirmCard(title: title(value), message: message?(value), reason: reason,
                                     actionTitle: actionTitle, role: role,
                                     onChoose: { typed in item.wrappedValue = nil; action(value, typed) },
                                     onCancel: { item.wrappedValue = nil })
        }
    }

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
            .background(Theme.canvas)
        }
    }
    return Demo()
}

#Preview("ThorbisConfirm card") {
    ThorbisConfirmCard(title: "Remove this item from the price book?",
                       message: "It stays on past invoices and estimates.",
                       actions: [ThorbisConfirmAction("Remove", role: .destructive) {}],
                       onChoose: { _ in }, onCancel: {})
    .background(Theme.canvas)
}
#endif
