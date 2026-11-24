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
        .padding(3)
        .background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                                .shadow(color: Theme.segmentShadow, radius: 2.5, y: 1)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    // 4 more to the finger side by side; stacked, only half the 2pt gap, so
                    // neighbouring choices' touch areas never overlap (a tap between them was
                    // ambiguous, and at accessibility sizes the frames read as overlapping).
                    .contentShape(Rectangle().inset(by: horizontal ? -4 : -1))
            }
            .buttonStyle(PressStyle())
            .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        }
    }
}

// MARK: - ThorbisConfirm (replaces `.confirmationDialog` and `.alert`)

/// One choice in a `thorbisConfirm`. `.destructive` draws the red pill; otherwise it is the brand
/// pill. A Cancel pill is added automatically.
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

/// The one confirm grammar (Paper P4 "Confirm (destructive)"), shared by every confirm and alert:
/// a 342pt card centred over a 45% black scrim; radius 28, a 1px rim, 24 above, 20 at the sides and
/// below, 10 between parts. A destructive choice leads with its mark (24pt, red text colour) in a
/// 52pt red-surface circle. The title is 20 Bold and names the thing; one 15/21 muted line says
/// what happens. Buttons are 50pt pills, 16 Semibold, 10 apart: Cancel on the card colour at the
/// left, the action at the right (red for destructive, brand otherwise) repeating the verb.
/// Several choices, or enlarged type, stack with Cancel last.
enum ThorbisConfirmMetrics {
    static let width: CGFloat = 342
    static let radius: CGFloat = 28
    static let scrim = Color.black.opacity(0.45)
    /// Paper `background` (#FAF9F6 / #1F1F1F): the confirm card's own ground, a step under `card`.
    static let panel = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0x1F / 255, green: 0x1F / 255, blue: 0x1F / 255, alpha: 1)
                                           : UIColor(red: 0xFA / 255, green: 0xF9 / 255, blue: 0xF6 / 255, alpha: 1)
    })
}

/// A confirm's pill: 50pt, 16 Semibold. Cancel sits on the card colour, a destructive choice on
/// red with white words, any other choice on the brand with white words.
struct ThorbisConfirmPill: View {
    enum Kind { case cancel, primary, destructive }
    let title: String
    let kind: Kind
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Text(title)
            .font(Theme.font(16, weight: .semibold))
            .foregroundStyle(kind == .cancel ? Theme.foreground : Color.white)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: Theme.commitHeight)
            .background(kind == .cancel ? Theme.card : (kind == .destructive ? Theme.destructiveFill : Theme.brand), in: Capsule())
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.5)
    }
}

/// The mark, title and message of a confirm (Paper P4), centred.
private struct ThorbisConfirmWords: View {
    let title: String
    let message: String?
    /// The destructive choice's verb, which picks the mark; nil draws no mark.
    let destructiveVerb: String?

    private var markSymbol: String {
        let word = (destructiveVerb ?? "").lowercased()
        return word.hasPrefix("delete") || word.hasPrefix("remove") ? "trash" : "exclamationmark.triangle"
    }

    var body: some View {
        VStack(spacing: 10) {
            if destructiveVerb != nil {
                Image(systemName: markSymbol)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(Theme.destructive)
                    .frame(width: 52, height: 52)
                    .background(Theme.destructiveSurface, in: Circle())
                    .accessibilityHidden(true)
            }
            Text(title).font(Theme.font(20, weight: .bold)).tracking(-0.2).foregroundStyle(Theme.foreground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, destructiveVerb == nil ? 0 : 4)
                .accessibilityAddTraits(.isHeader)
            if let message, !message.isEmpty {
                Text(message).font(Theme.font(15)).lineSpacing(2).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The card's shell: Paper P4's panel, with the words scrolling only when they cannot fit (a long
/// message at an accessibility size) so the pills always stay on screen.
private struct ThorbisConfirmShell<Words: View, Buttons: View>: View {
    @ViewBuilder var words: Words
    @ViewBuilder var buttons: Buttons

    var body: some View {
        VStack(spacing: 20) {
            ViewThatFits(in: .vertical) {
                words
                ScrollView { words }.scrollBounceBehavior(.basedOnSize)
            }
            buttons
        }
        .padding(.top, 24).padding(.horizontal, 20).padding(.bottom, 20)
        .frame(maxWidth: ThorbisConfirmMetrics.width)
        .background(ThorbisConfirmMetrics.panel, in: RoundedRectangle(cornerRadius: ThorbisConfirmMetrics.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThorbisConfirmMetrics.radius, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("thorbis-confirm")
    }
}

/// The confirm card (Paper P4 Confirm). See `ThorbisConfirmMetrics` for the grammar.
struct ThorbisConfirmCard: View {
    let title: String
    var message: String? = nil
    let actions: [ThorbisConfirmAction]
    /// The dismiss pill's word. "Cancel" everywhere, except where the action itself is a cancel
    /// ("Cancel job"), which reads "Keep".
    var cancelTitle: String = String(localized: "Cancel")
    let onChoose: (ThorbisConfirmAction) -> Void
    let onCancel: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var destructive: ThorbisConfirmAction? { actions.first { $0.role == .destructive } }
    /// Two pills side by side only when there is one choice and the type is not enlarged.
    private var sideBySide: Bool { actions.count == 1 && !typeSize.isAccessibilitySize }

    var body: some View {
        ThorbisConfirmShell {
            ThorbisConfirmWords(title: title, message: message, destructiveVerb: destructive?.title)
        } buttons: {
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
    }

    private func choiceButton(_ action: ThorbisConfirmAction) -> some View {
        Button { onChoose(action) } label: {
            ThorbisConfirmPill(title: action.title, kind: action.role == .destructive ? .destructive : .primary)
        }
        .buttonStyle(PressStyle())
    }

    private var cancelButton: some View {
        Button(action: onCancel) { ThorbisConfirmPill(title: cancelTitle, kind: .cancel) }
            .buttonStyle(PressStyle())
    }
}

/// The text field of a confirm that asks for something typed: its label above the well, an example
/// inside it, and whether the action needs an answer.
struct ThorbisConfirmReason {
    var label: String = "Reason"
    var placeholder: String = ""
    /// When true the action is still pressable; pressed with no reason it says what is missing
    /// under the field and does not run.
    var required = false
    var missingMessage: String = "Add a reason."
    var identifier: String = "confirm-reason"
    /// What the field starts with (renaming something starts from its name).
    var initialText: String = ""
}

/// The confirm card with a field (Paper P4 Confirm plus a 50pt field well under a 13 Semibold
/// label): used for a reason and for naming something. The action gets the trimmed text.
struct ThorbisReasonConfirmCard: View {
    let title: String
    var message: String? = nil
    var reason = ThorbisConfirmReason()
    let actionTitle: String
    var role: ButtonRole? = nil
    let onChoose: (String) -> Void
    let onCancel: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var text = ""
    @State private var showMissing = false
    @FocusState private var focused: Bool

    private var isDestructive: Bool { role == .destructive }
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ThorbisConfirmShell {
            VStack(spacing: 10) {
                ThorbisConfirmWords(title: title, message: message, destructiveVerb: isDestructive ? actionTitle : nil)
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
        } buttons: {
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
        .onAppear { if text.isEmpty { text = reason.initialText } }
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
            ThorbisConfirmPill(title: actionTitle, kind: isDestructive ? .destructive : .primary)
        }
        .buttonStyle(PressStyle())
    }

    private var cancelButton: some View {
        Button(action: onCancel) { ThorbisConfirmPill(title: String(localized: "Cancel"), kind: .cancel) }
            .buttonStyle(PressStyle())
    }
}

/// One labelled field of a confirm that edits a couple of short values in place (renaming a role).
struct ThorbisConfirmField: Identifiable {
    let id = UUID()
    var label: String
    var text: Binding<String>
}

/// The confirm card with bound fields (Paper P4 Confirm plus 50pt field wells under 13 Semibold
/// labels) and one "Done" pill: the fields write straight to their bindings.
struct ThorbisFieldsConfirmCard: View {
    let title: String
    var message: String? = nil
    let fields: [ThorbisConfirmField]
    var doneTitle: String = String(localized: "Done")
    let onDone: () -> Void

    var body: some View {
        ThorbisConfirmShell {
            VStack(spacing: 10) {
                ThorbisConfirmWords(title: title, message: message, destructiveVerb: nil)
                ForEach(fields) { field in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(field.label).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                            .padding(.horizontal, 4)
                        TextField(field.label, text: field.text, prompt: .placeholder(field.label))
                            .font(Theme.font(16)).foregroundStyle(Theme.foreground)
                            .submitLabel(.done)
                            .fieldWell()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                }
            }
        } buttons: {
            Button(action: onDone) { ThorbisConfirmPill(title: doneTitle, kind: .primary) }
                .buttonStyle(PressStyle())
        }
    }
}

/// Where a confirm card stands: centred over Paper P4's scrim, above everything (a sheet
/// included). The scrim fades and the card settles in; both are still under Reduce Motion. A tap
/// on the scrim, or VoiceOver's escape, is Cancel.
private struct ThorbisConfirmStage<Card: View>: View {
    let onCancel: () -> Void
    @ViewBuilder var card: Card
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            ThorbisConfirmMetrics.scrim.ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)
                .accessibilityHidden(true)
                .opacity(shown ? 1 : 0)
            card
                .padding(.horizontal, 24).padding(.vertical, 12)
                .scaleEffect(shown || reduceMotion ? 1 : 0.94)
                .opacity(shown ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationBackground(.clear)
        .accessibilityAction(.escape, onCancel)
        .onAppear { withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.86)) { shown = true } }
    }
}

/// Presents a confirm card as a cover with no slide: the stage draws its own scrim and motion.
private struct ThorbisConfirmPresenter<Card: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder var card: () -> Card
    @State private var covering = false

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented, initial: true) { _, wanted in
                guard wanted != covering else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { covering = wanted }
            }
            .fullScreenCover(isPresented: $covering, onDismiss: { if isPresented { isPresented = false } }) {
                ThorbisConfirmStage(onCancel: { isPresented = false }) { card() }
            }
    }
}

/// The same, bound to an optional item: shows while `item` is non-nil.
private struct ThorbisConfirmItemPresenter<Item: Identifiable, Card: View>: ViewModifier {
    @Binding var item: Item?
    @ViewBuilder var card: (Item) -> Card
    @State private var covering: Item?

    func body(content: Content) -> some View {
        content
            .onChange(of: item?.id, initial: true) { _, _ in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { covering = item }
            }
            .fullScreenCover(item: $covering, onDismiss: { if item != nil { item = nil } }) { value in
                ThorbisConfirmStage(onCancel: { item = nil }) { card(value) }
            }
    }
}

extension View {
    /// Present a confirm that asks for something typed (a reason, a name), in place of an alert
    /// with a text field. The action gets the trimmed text (empty when none was typed and it is
    /// not required).
    func thorbisConfirm(_ title: String, message: String? = nil, isPresented: Binding<Bool>,
                        reason: ThorbisConfirmReason, actionTitle: String, role: ButtonRole? = nil,
                        action: @escaping (String) -> Void) -> some View {
        modifier(ThorbisConfirmPresenter(isPresented: isPresented) {
            ThorbisReasonConfirmCard(title: title, message: message, reason: reason,
                                     actionTitle: actionTitle, role: role,
                                     onChoose: { typed in isPresented.wrappedValue = false; action(typed) },
                                     onCancel: { isPresented.wrappedValue = false })
        })
    }

    /// The same, bound to an optional item: shows while `item` is non-nil and clears it on dismiss.
    func thorbisConfirm<Item: Identifiable>(item: Binding<Item?>,
                                            title: @escaping (Item) -> String,
                                            message: ((Item) -> String)? = nil,
                                            reason: ThorbisConfirmReason,
                                            actionTitle: String, role: ButtonRole? = nil,
                                            action: @escaping (Item, String) -> Void) -> some View {
        modifier(ThorbisConfirmItemPresenter(item: item) { value in
            ThorbisReasonConfirmCard(title: title(value), message: message?(value), reason: reason,
                                     actionTitle: actionTitle, role: role,
                                     onChoose: { typed in item.wrappedValue = nil; action(value, typed) },
                                     onCancel: { item.wrappedValue = nil })
        })
    }

    /// Present a confirm that edits short values in place, in place of an alert with text fields.
    func thorbisConfirm(_ title: String, message: String? = nil, isPresented: Binding<Bool>,
                        fields: [ThorbisConfirmField], onDone: @escaping () -> Void = {}) -> some View {
        modifier(ThorbisConfirmPresenter(isPresented: isPresented) {
            ThorbisFieldsConfirmCard(title: title, message: message, fields: fields,
                                     onDone: { isPresented.wrappedValue = false; onDone() })
        })
    }

    /// Present the confirm card in place of `.confirmationDialog` or `.alert`. Destructive actions
    /// draw the red pill; a Cancel is added for you (`cancelTitle` renames it where the action is
    /// itself a cancel). With no actions it is a notice with one "OK".
    func thorbisConfirm(_ title: String, message: String? = nil, isPresented: Binding<Bool>,
                        cancelTitle: String = String(localized: "Cancel"),
                        actions: [ThorbisConfirmAction]) -> some View {
        modifier(ThorbisConfirmPresenter(isPresented: isPresented) {
            ThorbisConfirmCard(title: title, message: message, actions: actions,
                               cancelTitle: actions.isEmpty ? String(localized: "OK") : cancelTitle,
                               onChoose: { action in isPresented.wrappedValue = false; action.action() },
                               onCancel: { isPresented.wrappedValue = false })
        })
    }

    /// Present a confirm bound to an optional item, in place of
    /// `.confirmationDialog(..., presenting:)`. It shows while `item` is non-nil and clears it on
    /// dismiss.
    func thorbisConfirm<Item: Identifiable>(item: Binding<Item?>,
                                            title: @escaping (Item) -> String,
                                            message: ((Item) -> String)? = nil,
                                            cancelTitle: String = String(localized: "Cancel"),
                                            actions: @escaping (Item) -> [ThorbisConfirmAction]) -> some View {
        modifier(ThorbisConfirmItemPresenter(item: item) { value in
            ThorbisConfirmCard(title: title(value), message: message?(value), actions: actions(value),
                               cancelTitle: cancelTitle,
                               onChoose: { action in item.wrappedValue = nil; action.action() },
                               onCancel: { item.wrappedValue = nil })
        })
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
    .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.canvas)
}
#endif
