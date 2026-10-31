import SwiftUI

/// `PropertyChip` for a header that must never cut a word: the same tinted capsule with a leading
/// glyph or avatar, but its words wrap onto more lines at accessibility sizes instead of
/// truncating, it can end in a small chevron (it opens a menu), and its hit area reaches 44pt tall
/// without spacing the row apart. Used by the job screen's property row (redesign phase 2).
struct WrappingPropertyChip<Leading: View>: View {
    let text: String
    var tint: Color = Theme.fill
    var textColor: Color = Theme.foreground
    /// A chevron after the words, for a chip that opens a menu.
    var showsChevron = false
    var action: (() -> Void)? = nil
    @ViewBuilder var leading: Leading
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let action {
            Button(action: action) { label }.buttonStyle(PressStyle())
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            leading
            Text(text)
                .font(Theme.font(13, weight: .medium))
                .foregroundStyle(textColor)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(Theme.font(10, weight: .medium))
                    .foregroundStyle(textColor)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .frame(minHeight: Theme.chipHeight)
        .background(tint, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
        // 44pt tall to the finger, 28 to the eye.
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .padding(.vertical, -8)
    }
}

extension WrappingPropertyChip where Leading == AnyView {
    /// A chip with an SF Symbol (or nothing) before the words.
    init(_ text: String, symbol: String? = nil, tint: Color = Theme.fill, textColor: Color = Theme.foreground,
         showsChevron: Bool = false, action: (() -> Void)? = nil) {
        self.init(text: text, tint: tint, textColor: textColor, showsChevron: showsChevron, action: action) {
            AnyView(Group {
                if let symbol {
                    Image(systemName: symbol).font(Theme.font(12, weight: .medium)).accessibilityHidden(true)
                        .foregroundStyle(textColor)
                }
            })
        }
    }
}
