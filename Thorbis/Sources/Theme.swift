import SwiftUI
import UIKit

/// Tokens from the Paper "Thorbis Mobile" file (get_tokens).
enum Theme {
    /// Paper's type ramp at its default size. Each step scales with the
    /// Dynamic Type style closest to its size (HIG-008).
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom("Inter-Regular", size: size, relativeTo: textStyle(for: size)).weight(weight)
    }
    static func monoFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom("GeistMono-Regular", size: size, relativeTo: textStyle(for: size)).weight(weight)
    }
    static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 30...: .largeTitle
        case 24..<30: .title
        case 20..<24: .title2
        case 17..<20: .headline
        case 15..<17: .subheadline
        case 13..<15: .footnote
        case 12..<13: .caption
        default: .caption2
        }
    }
    /// Paper's screen gutter.
    static let gutter: CGFloat = 20
    // Dark values retain the Paper Mobile palette. Light surfaces are the
    // design.thorbis.com warm canvas/panel/well/ink tokens converted from OKLCH.
    static let card = adaptive(light: 0xFDFCFA, dark: 0x232323)
    static let subtle = adaptive(light: 0x59544D, dark: 0x949494, highLight: 0x201B14, highDark: 0xEDEDED)
    static let successSurface = adaptive(light: 0xE5F3E9, dark: 0x122B1C)
    static let destructiveSurface = adaptive(light: 0xFCE8E8, dark: 0x2A1414)
    static let background = adaptive(light: 0xF7F4EE, dark: 0x1F1F1F)
    static let surface = adaptive(light: 0xFDFCFA, dark: 0x191919)
    static let chrome = adaptive(light: 0xF7F4EE, dark: 0x141414)
    static let accent = adaptive(light: 0xEDE9E2, dark: 0x262626)
    static let foreground = adaptive(light: 0x201B14, dark: 0xEDEDED, highLight: 0x000000, highDark: 0xFFFFFF)
    static let muted = adaptive(light: 0x59544D, dark: 0xA0A0A0, highLight: 0x201B14, highDark: 0xEDEDED)
    static let fill = adaptive(light: 0xEDE9E2, dark: 0x2A2A2A)
    static let border = Color(uiColor: UIColor { traits in
        let high = traits.accessibilityContrast == .high
        return (traits.userInterfaceStyle == .dark ? UIColor.white : UIColor.black)
            .withAlphaComponent(high ? 0.6 : traits.userInterfaceStyle == .dark ? 0.08 : 0.12)
    })
    static let brand = Color(hex: 0x2F6BFF)
    /// Brand used as text or a link; plain brand is below 4.5:1 on both grounds.
    static let brandText = adaptive(light: 0x2558E0, dark: 0x5285FF)
    static let brandSurface = adaptive(light: 0xE5ECFF, dark: 0x182642)
    static let success = adaptive(light: 0x18743A, dark: 0x22C55E)
    static let warning = adaptive(light: 0x895400, dark: 0xF59E0B)
    static let warningSurface = adaptive(light: 0xFFF0CB, dark: 0x2A2008)
    static let destructive = adaptive(light: 0xB3262D, dark: 0xEF4444)

    private static func adaptive(light: UInt32, dark: UInt32,
                                 highLight: UInt32? = nil, highDark: UInt32? = nil) -> Color {
        Color(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let high = traits.accessibilityContrast == .high
            let value = isDark ? (high ? highDark ?? dark : dark) : (high ? highLight ?? light : light)
            return UIColor(red: CGFloat((value >> 16) & 0xFF) / 255,
                           green: CGFloat((value >> 8) & 0xFF) / 255,
                           blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        })
    }
    static let mono = monoFont(12, weight: .medium)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

struct Chip: View {
    let text: String
    var icon: String? = nil
    var tint: Color = Theme.muted
    var bg: Color = Theme.fill
    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(Theme.font( 10, weight: .semibold)) }
            Text(text).font(Theme.font( 12, weight: .medium)).lineLimit(1).fixedSize()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9).frame(minHeight: 24)
        .background(bg, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct Avatar: View {
    let name: String
    var size: CGFloat = 24
    var body: some View {
        Text(initials(name)).font(Theme.font( size * 0.38, weight: .semibold))
            .foregroundStyle(Theme.muted)
            .frame(width: size, height: size)
            .background(Theme.fill, in: Circle())
            .dynamicTypeSize(...DynamicTypeSize.large)
    }
}

func initials(_ name: String) -> String {
    let parts = name.split(separator: " ").prefix(2)
    let s = parts.compactMap { $0.first }.map(String.init).joined()
    return s.isEmpty ? "?" : s.uppercased()
}

struct SectionHeader: View {
    let title: String
    var count: Int? = nil
    var body: some View {
        HStack {
            Text(title).font(Theme.font( 13, weight: .medium)).foregroundStyle(Theme.muted)
            if let count { Text("\(count)").font(Theme.font( 12)).foregroundStyle(Theme.muted.opacity(0.7)) }
            Spacer()
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 18).padding(.bottom, 6)
    }
}

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var busy = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if busy { ProgressView().tint(.white) } else if let icon { Image(systemName: icon) }
                Text(title).font(Theme.font( 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity).frame(height: 46)
            .foregroundStyle(.white)
            .background(Theme.brand, in: RoundedRectangle(cornerRadius: 12))
        }
        .disabled(busy)
    }
}
