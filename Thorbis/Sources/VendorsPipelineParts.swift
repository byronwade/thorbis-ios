import SwiftUI

/// Small pieces shared by Vendors and POs and by Pipeline: the sheet's title row, form cards,
/// the quantity capsule, the status chip and the brand commit, all at Paper's sizes.

/// Paper 42B / 82C / 41A: Cancel on a card capsule, the title in 17 Semibold, the brand Save.
struct SalesSheetHeader: View {
    let title: String
    var saveTitle: String? = "Save"
    var saveIdentifier: String? = nil
    let onCancel: () -> Void
    var onSave: () -> Void = {}

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(titleInRow: true)
            VStack(alignment: .leading, spacing: 10) {
                row(titleInRow: false)
                titleText.fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 2)
    }

    private var titleText: some View {
        Text(title).font(Theme.font(17, weight: .semibold)).foregroundStyle(Theme.foreground)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(titleInRow: Bool) -> some View {
        HStack(spacing: 8) {
            Button(action: onCancel) {
                Text("Cancel").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    .padding(.horizontal, 16).frame(minHeight: 44)
                    .background(Theme.card, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            Spacer(minLength: 8)
            if titleInRow { titleText.lineLimit(1).fixedSize(); Spacer(minLength: 8) }
            if let saveTitle {
                // Never pre-disabled: pressed with something missing, the sheet says what.
                Button(action: onSave) {
                    Text(saveTitle).font(Theme.font(16, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).frame(minHeight: 44)
                        .background(Theme.brand, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier(saveIdentifier ?? "sales-sheet-save")
            } else if titleInRow {
                // Balances Cancel so the title sits in the middle (Paper 41A).
                Color.clear.frame(width: 83, height: 44).accessibilityHidden(true)
            }
        }
    }
}

/// One grouped card of a form (radius 20 on the card tone).
struct SalesFormCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

/// A stacked answer: the 13 muted label over a 17 Medium answer (Paper 42B "Business name").
struct SalesStackedField: View {
    let label: String
    @Binding var text: String
    var prompt: String = ""
    var problem: String? = nil
    var keyboard: UIKeyboardType = .default
    var content: UITextContentType? = nil
    var capitalization: TextInputAutocapitalization = .sentences
    var multiline = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.font(13)).foregroundStyle(Theme.muted).accessibilityHidden(true)
            TextField("", text: $text, prompt: .placeholder(prompt), axis: multiline ? .vertical : .horizontal)
                .font(multiline ? Theme.font(15) : Theme.font(17, weight: .medium))
                .foregroundStyle(Theme.foreground)
                .keyboardType(keyboard)
                .textContentType(content)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled(keyboard != .default)
                .lineLimit(multiline ? 2...8 : 1...1)
                .frame(minHeight: 28)
                .accessibilityLabel(label)
            if let problem { FieldProblem(message: problem) }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
    }
}

/// An inline answer: the 16 label on the left, the answer muted on the right, 56 tall.
struct SalesInlineField: View {
    let label: String
    @Binding var text: String
    var prompt: String = "Optional"
    var problem: String? = nil
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(label).font(Theme.font(16)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                TextField("", text: $text, prompt: .placeholder(prompt))
                    .font(Theme.font(16)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(capitalization)
                    .autocorrectionDisabled(keyboard != .default)
                    .frame(minHeight: 40)
                    .accessibilityLabel(label)
            }
            if let problem { FieldProblem(message: problem) }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    }
}

/// Paper 41 / 41A: minus, the count in 17 Semibold, plus, on one 44-tall capsule. At the floor
/// the minus fades, or becomes remove when the caller gives one.
struct SalesQuantityStepper: View {
    let value: Int
    let range: ClosedRange<Int>
    let name: String
    let onChange: (Int) -> Void
    /// At the lowest count, minus becomes a red bin that removes the item.
    var onRemove: (() -> Void)? = nil

    private var atFloor: Bool { value <= range.lowerBound }
    private var atCeiling: Bool { value >= range.upperBound }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                if atFloor { onRemove?() } else { onChange(value - 1) }
            } label: {
                Image(systemName: atFloor && onRemove != nil ? "trash" : "minus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(atFloor ? (onRemove != nil ? Theme.destructive : Theme.muted.opacity(0.5)) : Theme.foreground)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .disabled(atFloor && onRemove == nil)
            .accessibilityLabel(atFloor && onRemove != nil ? "Remove \(name)" : "One fewer \(name)")
            Text("\(value)").font(Theme.font(17, weight: .semibold)).monospacedDigit()
                .foregroundStyle(Theme.foreground)
                .frame(minWidth: 22)
                .accessibilityLabel("\(value) \(name)")
            Button { onChange(value + 1) } label: {
                Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(atCeiling ? Theme.muted.opacity(0.5) : Theme.foreground)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .disabled(atCeiling)
            .accessibilityLabel("One more \(name)")
        }
        .background(Theme.fill, in: Capsule())
    }
}

/// Paper 43: a status word on its tinted surface, 24 tall, 13 Medium.
struct SalesStatusChip: View {
    let text: String
    var ink: Color = Theme.muted
    var surface: Color = Theme.fill

    var body: some View {
        Text(text).font(Theme.font(13, weight: .medium)).foregroundStyle(ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8).frame(minHeight: 24)
            .background(surface, in: Capsule())
    }
}

/// Paper 42A / 82B: the brand commit, 52 tall, white 17 Semibold, an optional mark before the words.
struct SalesBrandCommit: View {
    let title: String
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).accessibilityHidden(true)
            }
            Text(title).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .paperButton(.commit, tone: .brand, fills: true)
    }
}

/// A quiet pill beside or under the commit (Paper 82B "Book a visit"): the card tone, 16 Semibold.
struct SalesQuietPill: View {
    let title: String
    var symbol: String? = nil
    var ink: Color = Theme.foreground

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).accessibilityHidden(true)
            }
            Text(title).font(Theme.font(16, weight: .semibold)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: PaperControl.Size.card.height)
        .background(Theme.quietFill, in: Capsule())
        .contentShape(Capsule())
    }
}

/// The plain line that says where these records live.
struct SalesPhoneNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "iphone").font(.system(size: 12, weight: .medium)).accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(Theme.font(13)).foregroundStyle(Theme.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

/// A red line for something that did not save.
struct SalesProblemLine: View {
    let message: String

    var body: some View {
        Text(message).font(Theme.font(15)).foregroundStyle(Theme.destructive)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

/// The address-style search on the card (46 tall, radius 14); it narrows the list under it.
struct SalesSearchField: View {
    @Binding var query: String
    let prompt: String
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.muted).accessibilityHidden(true)
            TextField("", text: $query, prompt: .placeholder(prompt))
                .font(Theme.font(16)).foregroundStyle(Theme.foreground)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .frame(minHeight: 46)
                .accessibilityLabel(label)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                        .frame(width: 32, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 46)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
