import SwiftUI
import UIKit

/// Tokens from the Paper "Thorbis Mobile" file (get_tokens).
enum Theme {
    /// Paper's type ramp at its default size. Each step scales with the
    /// Dynamic Type style closest to its size (HIG-008).
    /// design.thorbis.com MA-09: weights 400 and 500 only, nothing smaller than 12. Heavier
    /// requests resolve to 500 and smaller sizes to 12, so every call site follows the rule.
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let size = onRamp(size)
        return Font.custom("Inter-Regular", size: size, relativeTo: textStyle(for: size)).weight(allowed(weight))
    }
    /// Numbers, times and record numbers. Inter with tabular digits, so amounts line up in a
    /// column without a typewriter face (the 2026-10-30 modern pass retired Geist Mono here).
    static func monoFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let size = onRamp(size)
        return Font.custom("Inter-Regular", size: size, relativeTo: textStyle(for: size))
            .weight(allowed(weight)).monospacedDigit()
    }
    static let minimumSize: CGFloat = 12
    /// design.thorbis.com MF-02: four money sizes, nothing smaller. Hero is what the screen is
    /// about (balance due, the amount being collected, an estimate's total); total sits in cards
    /// and Total / Paid rows; row is a list row's amount; line is a line item. Hero is 34 on a
    /// phone and 40 on iPad (above the staff ramp, like customer mode); all scale with Dynamic Type.
    enum MoneySize {
        case hero, total, row, line
    }
    static func moneyFont(_ size: MoneySize, regular: Bool = false, wide: Bool = false) -> Font {
        let weight: Font.Weight = regular || size == .line ? .regular : .medium
        switch size {
        case .hero:
            return Font.custom("Inter-Regular", size: wide ? 40 : 34, relativeTo: .largeTitle).weight(weight).monospacedDigit()
        case .total: return monoFont(24, weight: weight)
        case .row: return monoFont(17, weight: weight)
        case .line: return monoFont(15, weight: weight)
        }
    }
    /// MA-09: every size lands on the ramp 12/13/15/17/20/24/30 (16 stays for inputs, so
    /// iOS never zooms a field). Stray sizes like 14 or 26 snap to the nearest step.
    static func onRamp(_ size: CGFloat) -> CGFloat {
        switch size {
        case ..<13: minimumSize
        case 13..<14: 13
        case 14..<16: 15
        case 16..<17: 16
        case 17..<18.5: 17
        case 18.5..<22: 20
        case 22..<27: 24
        default: 30
        }
    }
    static func allowed(_ weight: Font.Weight) -> Font.Weight {
        let heavier: [Font.Weight] = [.semibold, .bold, .heavy, .black]
        return heavier.contains(weight) ? .medium : weight
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
    /// MA-10: controls and fields 12, cards and sheets 14; chips and pill tabs are capsules.
    static let controlRadius: CGFloat = 12
    static let cardRadius: CGFloat = 14
    /// MA-10: chips start at 28 tall and grow with accessible text.
    static let chipHeight: CGFloat = 28
    /// MA-08: the commit starts at 50 tall and grows with accessible text.
    static let commitHeight: CGFloat = 50
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
    /// MA-08: a commit is ink (the type colour) with inverse type and a hairline rim.
    static let ink = foreground
    static let onInk = adaptive(light: 0xFDFCFA, dark: 0x191919, highLight: 0xFFFFFF, highDark: 0x000000)
    static let brand = Color(hex: 0x2F6BFF)
    /// Brand used as text or a link; plain brand is below 4.5:1 on both grounds.
    /// Dark is lifted so links hold 4.5:1 on the field well and the brand surface too.
    static let brandText = adaptive(light: 0x2558E0, dark: 0x6090FF)
    static let brandSurface = adaptive(light: 0xE5ECFF, dark: 0x182642)
    static let success = adaptive(light: 0x18743A, dark: 0x22C55E)
    static let warning = adaptive(light: 0x895400, dark: 0xF59E0B)
    static let warningSurface = adaptive(light: 0xFFF0CB, dark: 0x2A2008)
    /// Red as a word or glyph. Dark is a lighter red so it holds 4.5:1 on card and well.
    static let destructive = adaptive(light: 0xB3262D, dark: 0xF87171)
    /// Red as a fill under white type or a white glyph (a badge, a destructive button): 5.6:1 or better.
    static let destructiveFill = adaptive(light: 0xB3262D, dark: 0xC62828)
    /// The chosen segment's raised pill. In dark it sits lighter than the well so the choice shows.
    static let selectedSegment = adaptive(light: 0xFDFCFA, dark: 0x3A3A3A)
    /// Soft place-mark hues for menu icons (design.thorbis.com Color: olive, forest, pumpkin,
    /// burnt, or accent mixed down). Only the mark is tinted; the word stays body.
    static let markOlive = adaptive(light: 0x6E6A2E, dark: 0xB5B07A)
    static let markForest = adaptive(light: 0x2F6B4A, dark: 0x7FB394)
    static let markPumpkin = adaptive(light: 0x9A5A1E, dark: 0xD9A06A)
    static let markBurnt = adaptive(light: 0x8E4630, dark: 0xC98A72)
    static let markAccent = adaptive(light: 0x3D5FB8, dark: 0x8BA6E8)

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

/// MA-10: a chip is a word on the neutral well. A status hue colours the glyph only, never the
/// word or the pill, so state reads the same in light, dark and for colour-blind people.
struct Chip: View {
    let text: String
    var icon: String? = nil
    var tint: Color = Theme.muted
    /// Kept so call sites read the same; chips always sit on `Theme.fill`.
    var bg: Color = Theme.fill
    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 12, weight: .medium)).foregroundStyle(tint) }
            Text(text).font(Theme.font(12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(tint == Theme.muted ? Theme.muted : Theme.foreground)
        }
        .padding(.horizontal, 10).padding(.vertical, 5).frame(minHeight: Theme.chipHeight)
        .background(Theme.fill, in: Capsule())
    }
}

struct Avatar: View {
    let name: String
    var size: CGFloat = 24
    var fill: Color = Theme.fill
    var body: some View {
        Text(initials(name)).font(Theme.font(size * 0.38, weight: .medium))
            .foregroundStyle(Theme.muted)
            .frame(width: size, height: size)
            .background(fill, in: Circle())
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
            if let count { Text("\(count)").font(Theme.font( 12)).foregroundStyle(Theme.muted) }
            Spacer()
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 18).padding(.bottom, 6)
    }
}

private struct InkCommit: ViewModifier {
    let enabled: Bool?
    let height: CGFloat
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .font(Theme.font(17, weight: .medium))
            .foregroundStyle(Theme.onInk)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Theme.ink.opacity((enabled ?? isEnabled) ? 1 : 0.35), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).stroke(Theme.border))
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }
}

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var busy = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if busy { ProgressView().tint(Theme.onInk) } else if let icon { Image(systemName: icon) }
                Text(title)
            }
            // MA-08: follows `.disabled(...)`, from the call site or busy, so disabled looks disabled.
            .inkCommit()
        }
        .buttonStyle(PressStyle())
        .disabled(busy)
    }
}

extension View {
    /// MA-08: the screen's one commit. Ink fill, inverse type 17/500, at least 50 tall, radius 12, a
    /// hairline rim so it holds its edge on the dark canvas. Disabled fades the ink, never turns it grey-blue.
    /// With `enabled` left nil the commit follows the button's own `.disabled(...)`.
    func inkCommit(enabled: Bool? = nil, height: CGFloat = Theme.commitHeight) -> some View {
        modifier(InkCommit(enabled: enabled, height: height))
    }

    /// MF-02..MF-06: an amount in one of the four money sizes. Ink unless the call site tints it
    /// (red only when overdue), tabular, never truncated (scales to 70% on one line), and the
    /// digits roll when the amount changes.
    func moneyStyle(_ size: Theme.MoneySize, regular: Bool = false) -> some View {
        modifier(MoneyStyle(size: size, regular: regular))
    }
}

private struct MoneyStyle: ViewModifier {
    let size: Theme.MoneySize
    let regular: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content
            .font(Theme.moneyFont(size, regular: regular, wide: sizeClass == .regular))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .contentTransition(.numericText())
    }
}

/// MA-07: every button answers the finger at once. It dips to 0.97 and 85% opacity while
/// pressed and comes back in 120 ms; with Reduce Motion only the opacity changes.
struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// MA-07: a list row shows the well fill while pressed, edge to edge of its content.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.fill : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// MA-13: the shape of what is coming. Rows the size of the real ones, static (no shimmer),
/// so Reduce Motion needs nothing different; VoiceOver hears one "Loading" instead.
struct SkeletonRows: View {
    var count = 6
    var leading = true
    /// Zero when the parent already pads to the gutter.
    var inset: CGFloat = Theme.gutter

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                HStack(spacing: 12) {
                    if leading { Circle().fill(Theme.fill).frame(width: 22, height: 22) }
                    VStack(alignment: .leading, spacing: 7) {
                        Capsule().fill(Theme.fill).frame(width: index.isMultiple(of: 2) ? 190 : 150, height: 12)
                        Capsule().fill(Theme.fill.opacity(0.7)).frame(width: index.isMultiple(of: 3) ? 120 : 170, height: 10)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 52)
            }
        }
        .padding(.horizontal, inset)
        .padding(.top, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

extension Date {
    /// One way to say when a visit is, used on every list and header: "Today 4:00 PM",
    /// "Tomorrow 9:00 AM", otherwise "Thu, Oct 30, 9:00 AM".
    func visitLabel(now: Date = .now, calendar: Calendar = .current) -> String {
        let time = tradeTime
        if calendar.isDate(self, inSameDayAs: now) { return "Today \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(self, inSameDayAs: tomorrow) {
            return "Tomorrow \(time)"
        }
        return "\(formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())), \(tradeTime)"
    }
}

/// MA-03: with Reduce Motion on, every animation becomes a short 150ms ease-out
/// with no spring or travel; otherwise the given animation runs as written.
@MainActor func withMotion<Result>(_ animation: Animation = .default, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(UIAccessibility.isReduceMotionEnabled ? .easeOut(duration: 0.15) : animation, body)
}
