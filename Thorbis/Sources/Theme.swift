import SwiftUI
import UIKit

/// Tokens from the Paper "Thorbis Mobile" file (get_tokens).
enum Theme {
    /// Paper's type ramp at its default size. Each step scales with the
    /// Dynamic Type style closest to its size (HIG-008).
    /// Weights 400 and 500 only (design.thorbis.com, v2 2026-10-31), nothing smaller than 12.
    /// Semibold, bold, heavy and black resolve to Medium and smaller sizes to 12, so every call site
    /// follows the rule. Medium is a heading, a row, a commit; Regular is the body of a note.
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
    /// Customer-facing presentation (rule 13): the size asked for, on the older, larger ramp, so the
    /// 17pt floor holds while staff screens use the compact v2 ramp. Still scales with Dynamic Type.
    static func customerFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let size = customerRamp(size)
        return Font.custom("Inter-Regular", size: size, relativeTo: textStyle(for: size)).weight(allowed(weight))
    }
    static func customerMonoFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        customerFont(size, weight: weight).monospacedDigit()
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
            // v2: 30 on a phone, 34 on iPad (design.thorbis.com keeps display for the hero only).
            return Font.custom("Inter-Regular", size: wide ? 34 : 30, relativeTo: .largeTitle).weight(weight).monospacedDigit()
        case .total: return monoFont(24, weight: weight)
        case .row: return monoFont(16, weight: weight)
        case .line: return monoFont(15, weight: weight)
        }
    }
    /// v2 (owner, 31 Oct 2026: "the font size is too big"): staff screens use design.thorbis.com's
    /// compact ramp at the default Dynamic Type size, and every requested size snaps onto it so call
    /// sites shrink together. Body and row titles 15, supporting lines 14, chrome 13, captions 12,
    /// sheet titles 16-17, detail titles 24, root titles 26 (the old 34 step is gone). All scale
    /// with Dynamic Type through `textStyle(for:)`; hit targets stay 44pt where the type shrinks.
    ///
    /// requested: <13 → 12 · 13 → 13 · 14-15 → 14 · 16-17 → 15 · 18-19 → 16 · 20-21 → 17 ·
    /// 22-26 → 20 · 27-31 → 24 · 32+ → 26.
    static func onRamp(_ size: CGFloat) -> CGFloat {
        switch size {
        case ..<13: minimumSize
        case 13..<14: 13
        case 14..<16: 14
        case 16..<18: 15
        case 18..<20: 16
        case 20..<22: 17
        case 22..<27: 20
        case 27..<32: 24
        default: 26
        }
    }
    /// The pre-v2 ramp 12/13/15/17/20/24/30/34, kept for customer-facing presentation only.
    static func customerRamp(_ size: CGFloat) -> CGFloat {
        switch size {
        case ..<13: minimumSize
        case 13..<14: 13
        case 14..<16: 15
        case 16..<17: 16
        case 17..<18.5: 17
        case 18.5..<22: 20
        case 22..<27: 24
        case 27..<32: 30
        default: 34
        }
    }
    static func allowed(_ weight: Font.Weight) -> Font.Weight {
        let heavier: [Font.Weight] = [.semibold, .bold, .heavy, .black]
        return heavier.contains(weight) ? .medium : weight
    }
    static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 26...: .largeTitle
        case 24..<26: .title
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
    /// design.thorbis.com Radius: commits and fields 10, sheets and panels 14, chips are pills,
    /// icons are circles.
    static let controlRadius: CGFloat = 10
    static let cardRadius: CGFloat = 14
    /// MA-10: chips start at 28 tall and grow with accessible text.
    static let chipHeight: CGFloat = 28
    /// MA-08: the commit starts at 50 tall and grows with accessible text.
    static let commitHeight: CGFloat = 50
    // v2 (2026-10-31): design.thorbis.com tokens on Linear's grammar. Dark is the first drawing:
    // Linear's greys (canvas oklch 14.5%, panel 20.5%), cream type (oklch 96.8% 0.009 84.6) and a
    // cool grey body. Light is the warm cream sheet that shipped before PR #200, a retune of
    // lightness rather than an invert. Token names are unchanged, so every screen follows.
    // `card`/`well` is the panel rows sit on; `surface` is a sheet's panel; `fill` is a chip or a
    // circle (a step lighter than the panel in dark); `field` is the sunk well under a text field or
    // a select (a step darker than the panel). Lightness was tuned, never saturation, so text holds
    // 4.5:1 and marks 3:1 in both themes and in Increase Contrast (`scripts/tests/contrast.py`).
    static let card = adaptive(light: 0xFDFCFA, dark: 0x171717)
    /// The panel grouped rows sit on (radius 14). Same as `card`, named for what it is.
    static let well = card
    /// Body: the cool grey of supporting lines (light keeps the warm ink family).
    static let subtle = adaptive(light: 0x4A453E, dark: 0xBFC5CC, highLight: 0x201B14, highDark: 0xF7F4EE)
    static let successSurface = adaptive(light: 0xDFF6E2, dark: 0x0D2412)
    static let destructiveSurface = adaptive(light: 0xFFE6E4, dark: 0x301514)
    /// The canvas.
    static let background = adaptive(light: 0xF7F4EE, dark: 0x0A0A0A)
    /// A sheet's or an overlay's panel.
    static let surface = adaptive(light: 0xFDFCFA, dark: 0x171717)
    static let chrome = adaptive(light: 0xF7F4EE, dark: 0x0A0A0A)
    /// A neutral step (kept for call sites); never the electric blue, which is `brand`.
    static let accent = adaptive(light: 0xEDE9E2, dark: 0x262626)
    /// Type: ink on cream in light, cream on the dark greys.
    static let foreground = adaptive(light: 0x201B14, dark: 0xF7F4EE, highLight: 0x000000, highDark: 0xFFFFFF)
    /// The marker: times, counts, labels. Dimmer than body.
    static let muted = adaptive(light: 0x66615A, dark: 0x9A9FA6, highLight: 0x201B14, highDark: 0xF7F4EE)
    /// A chip's or a circle's ground.
    static let fill = adaptive(light: 0xEDE9E2, dark: 0x262626)
    /// Sink: the field well, one step darker than the panel, with a 1px rim (`fieldWell()`).
    static let field = adaptive(light: 0xF1EDE6, dark: 0x0F0F0F)
    /// The 1px rim. A border is a use case (a field, a commit, a chip, a photo), never a separator.
    static let border = Color(uiColor: UIColor { traits in
        let high = traits.accessibilityContrast == .high
        return (traits.userInterfaceStyle == .dark ? UIColor.white : UIColor.black)
            .withAlphaComponent(high ? 0.6 : traits.userInterfaceStyle == .dark ? 0.10 : 0.10)
    })
    /// Kept for call sites; draws the same 1px rim. Never a line between rows.
    static let hairline = border
    /// MA-08: a commit is ink (the type colour) with inverse type, a 1px rim and a short bevel.
    static let ink = foreground
    static let onInk = adaptive(light: 0xFDFCFA, dark: 0x0A0A0A, highLight: 0xFFFFFF, highDark: 0x000000)
    /// Electric blue, oklch(55.8% 0.188 264.4): selected, focus, the one live thing. Never a wash.
    static let brand = Color(hex: 0x3A6AE0)
    /// Brand used as text or a link: lightness tuned for 4.5:1 on the canvas, the panel and its surface.
    static let brandText = adaptive(light: 0x3260D6, dark: 0x5387FF, highLight: 0x1A44B7, highDark: 0xBDD8FF)
    static let brandSurface = adaptive(light: 0xE3EFFF, dark: 0x131D33)
    /// success oklch(62.7% 0.17 149.2), as a word.
    static let success = adaptive(light: 0x007B21, dark: 0x33B45A, highLight: 0x005E00, highDark: 0x94E4A3)
    /// warning oklch(82.7% 0.171 80.5), as a word: darkened in light so it reads on cream.
    static let warning = adaptive(light: 0x9A5900, dark: 0xFFB800, highLight: 0x7E3E00, highDark: 0xFFD27A)
    static let warningSurface = adaptive(light: 0xFBEDD5, dark: 0x291B02)
    /// error oklch(62.6% 0.193 23), as a word.
    static let destructive = adaptive(light: 0xC82A36, dark: 0xF35659, highLight: 0xA10015, highDark: 0xFFB1AC)
    /// Red as a fill under white type or a white glyph (a badge, a destructive commit): 4.5:1 or better.
    static let destructiveFill = adaptive(light: 0xC82A36, dark: 0xB3262D)
    /// The chosen segment's raised pill. In dark it sits lighter than the panel so the choice shows.
    static let selectedSegment = adaptive(light: 0xFDFCFA, dark: 0x2E2E2E)

    // Status hues: the site's four (success, error, info, warning) plus the marker grey and the
    // accent. `status*` colours a mark (non-text, 3:1); `status*Text` is the word's twin (4.5:1 on
    // canvas, panel and its own surface); `status*Surface` is a chip's tinted ground. A status is a
    // word first (`StatusLabel`); the mark sits beside it, never alone.
    static let statusUnscheduled = adaptive(light: 0x7C8186, dark: 0x82878C)
    /// Scheduled reads as info, oklch(62.3% 0.188 259.8).
    static let statusScheduled = adaptive(light: 0x3B82F6, dark: 0x3B82F6)
    static let statusScheduledText = adaptive(light: 0x1C64D5, dark: 0x5C9BFF, highLight: 0x0047B7, highDark: 0xC1D9FF)
    static let statusScheduledSurface = adaptive(light: 0xE1F0FF, dark: 0x111E33)
    /// Dispatched (en route) is the one live thing: the accent.
    static let statusDispatched = brand
    static let statusDispatchedText = brandText
    static let statusDispatchedSurface = brandSurface
    static let statusInProgress = adaptive(light: 0xBE7A00, dark: 0xFFB800)
    static let statusInProgressText = warning
    static let statusInProgressSurface = warningSurface
    static let statusDone = adaptive(light: 0x0DA047, dark: 0x16A34A)
    static let statusDoneText = success
    static let statusDoneSurface = successSurface
    static let statusAttention = adaptive(light: 0xE5484D, dark: 0xE5484D)
    static let statusAttentionText = destructive
    static let statusAttentionSurface = destructiveSurface
    /// Paid reads as success too; the word ("Paid", "Invoiced") tells it from Done.
    static let statusInvoiced = adaptive(light: 0x0DA047, dark: 0x16A34A)
    static let statusInvoicedText = adaptive(light: 0x007B21, dark: 0x33B45A, highLight: 0x005E00, highDark: 0x94E4A3)
    static let statusInvoicedSurface = adaptive(light: 0xDFF6E2, dark: 0x0D2412)

    /// The toast: a dark capsule in both themes. In dark it sits a step above the panel so it
    /// still reads as raised; `toastText` and `toastMuted` hold 4.5:1 on it.
    static let toastFill = adaptive(light: 0x201B14, dark: 0x2E2E2E, highLight: 0x000000, highDark: 0x3A3A3A)
    static let toastText = adaptive(light: 0xF7F4EE, dark: 0xF7F4EE, highLight: 0xFFFFFF, highDark: 0xFFFFFF)
    static let toastMuted = adaptive(light: 0xB5AFA6, dark: 0xA8ADB4, highLight: 0xE0DCD5, highDark: 0xD4D7DB)

    /// Place marks (design.thorbis.com Color): olive, forest, pumpkin, burnt, and the accent mixed
    /// down. Quiet colour on chrome: the mark is outlined at rest and filled when it is the place;
    /// the word beside it stays cream or body. Dark lifts lightness so each mark holds 3:1.
    static let markOlive = adaptive(light: 0x5C6140, dark: 0x979C79)
    static let markForest = adaptive(light: 0x2F4A32, dark: 0x7E9B80)
    static let markPumpkin = adaptive(light: 0xC45C19, dark: 0xDF8353)
    static let markBurnt = adaptive(light: 0xA33B24, dark: 0xCA6F5A)
    static let markAccent = adaptive(light: 0x5773AF, dark: 0x829ED7)
    /// Older names, folded onto the five: blue is the accent mixed down, teal is forest, red is burnt.
    static let markBlue = adaptive(light: 0x5773AF, dark: 0x829ED7)
    static let markTeal = adaptive(light: 0x2F4A32, dark: 0x7E9B80)
    static let markRed = adaptive(light: 0xA33B24, dark: 0xCA6F5A)
    static let markGrey = adaptive(light: 0x7C8186, dark: 0x82878C)

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
        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
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

/// v2: a grouped section's header, chrome 13 Medium in the marker colour with the
/// count beside it ("Up next  2"), and an optional trailing accessory. Sits above a `Well`.
struct SectionHeader<Trailing: View>: View {
    let title: String
    var count: Int? = nil
    var horizontalPadding: CGFloat = 4
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(Theme.font(13, weight: .medium))
                .accessibilityAddTraits(.isHeader)
            if let count, count > 0 {
                Text("\(count)").font(Theme.font(13)).monospacedDigit()
                    .accessibilityLabel("\(count)")
            }
            Spacer(minLength: 0)
            trailing
        }
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, horizontalPadding)
        .frame(minHeight: 32)
        .accessibilityElement(children: .contain)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, count: Int? = nil, horizontalPadding: CGFloat = 4) {
        self.init(title: title, count: count, horizontalPadding: horizontalPadding) { EmptyView() }
    }
}

/// Lift (design.thorbis.com Depth): the commit is ink with inverse type, radius 10, a 1px rim, a
/// short bevel (1px light from above, 1px drop) and it sinks while pressed (the drop goes, it settles
/// 1px). Disabled fades the ink; a disabled commit should carry a reason (`PaperActionBar`).
private struct InkCommit: ViewModifier {
    let enabled: Bool?
    let height: CGFloat
    var fill: Color = Theme.ink
    var type: Color = Theme.onInk
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.thorbisPressed) private var pressed

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
        let on = enabled ?? isEnabled
        content
            .font(Theme.font(17, weight: .medium))
            .foregroundStyle(type)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(fill.opacity(on ? 1 : 0.35), in: shape)
            // Light from above: a 1px highlight inside the top edge, gone while pressed.
            .overlay(shape.inset(by: 0.5).stroke(LinearGradient(colors: [Color.white.opacity(pressed || !on ? 0 : 0.22), .clear],
                                                                startPoint: .top, endPoint: .center), lineWidth: 1))
            .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
            // The 1px drop. Press sinks: the drop goes and the commit settles onto the page.
            .shadow(color: .black.opacity(pressed || !on ? 0 : 0.28), radius: 0, x: 0, y: 1)
            .offset(y: pressed ? 1 : 0)
            .contentShape(shape)
    }
}

private struct ThorbisPressedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// True while the enclosing `PressStyle` button is held, so a lifted commit can sink.
    var thorbisPressed: Bool {
        get { self[ThorbisPressedKey.self] }
        set { self[ThorbisPressedKey.self] = newValue }
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

    /// The same lifted commit in the danger tone (Cancel job, Void invoice): white type on red.
    func dangerCommit(enabled: Bool? = nil, height: CGFloat = Theme.commitHeight) -> some View {
        modifier(InkCommit(enabled: enabled, height: height, fill: Theme.destructiveFill, type: .white))
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

/// MA-07: every button answers the finger at once. It dips to 0.98 and 88% opacity while
/// pressed and comes back in 120 ms ease-out; with Reduce Motion only the opacity changes. It also
/// tells its label it is pressed (`thorbisPressed`) so a lifted commit sinks.
struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.thorbisPressed, configuration.isPressed)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
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
extension Theme {
    /// Phase 4: the small spring a chosen pill, segment or chip settles with; a short fade under
    /// Reduce Motion.
    /// v2 (design.thorbis.com Motion): 120ms ease-out, no spring or bounce on routine work. The name
    /// is kept so call sites follow; Reduce Motion gets the same short fade.
    static func selectionSpring(reduceMotion: Bool) -> Animation {
        .easeOut(duration: 0.12)
    }
    /// Menus, chips and segments: 120ms ease-out.
    static let quick: Animation = .easeOut(duration: 0.12)
}

@MainActor func withMotion<Result>(_ animation: Animation = .default, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(UIAccessibility.isReduceMotionEnabled ? .easeOut(duration: 0.15) : animation, body)
}
