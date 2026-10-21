import SwiftUI

/// Tokens from the Paper "Thorbis Mobile" file (get_tokens).
enum Theme {
    static let background = Color(hex: 0x1F1F1F)
    static let surface = Color(hex: 0x191919)
    static let chrome = Color(hex: 0x141414)
    static let accent = Color(hex: 0x262626)
    static let foreground = Color(hex: 0xEDEDED)
    static let muted = Color(hex: 0xA0A0A0)
    static let fill = Color(hex: 0x2A2A2A)
    static let border = Color.white.opacity(0.08)
    static let brand = Color(hex: 0x2F6BFF)
    static let brandSurface = Color(hex: 0x182642)
    static let success = Color(hex: 0x22C55E)
    static let warning = Color(hex: 0xF59E0B)
    static let warningSurface = Color(hex: 0x2A2008)
    static let destructive = Color(hex: 0xEF4444)
    static let mono = Font.system(size: 12, weight: .medium, design: .monospaced)
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
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .semibold)) }
            Text(text).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(bg, in: RoundedRectangle(cornerRadius: 6))
    }
}

struct Avatar: View {
    let name: String
    var size: CGFloat = 24
    var body: some View {
        Text(initials(name)).font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(Theme.muted)
            .frame(width: size, height: size)
            .background(Theme.fill, in: Circle())
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
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
            if let count { Text("\(count)").font(.system(size: 12)).foregroundStyle(Theme.muted.opacity(0.7)) }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 6)
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
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity).frame(height: 44)
            .foregroundStyle(.white)
            .background(Theme.brand, in: RoundedRectangle(cornerRadius: 10))
        }
        .disabled(busy)
    }
}
