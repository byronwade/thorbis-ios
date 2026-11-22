import SwiftUI
import UIKit

/// Tokens from the Paper "Thorbis Mobile" file (get_tokens).
enum Theme {
    /// Paper's type ramp at its default size. Each step scales with the
    /// Dynamic Type style closest to its size (HIG-008).
    /// Weights 400 to 700 (Paper v2, 2026-11-16), nothing smaller than 12. Heavy and black resolve
    /// to bold and smaller sizes to 12, so every call site follows the rule (`allowed(_:)`).
    /// Paper v2: every screen title is 34 Bold (Jobs, Dashboard, a job, a customer); a size that
    /// lands on 34 is drawn bold whatever weight the call site asked for.
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let size = onRamp(size)
        let weight: Font.Weight = size >= 34 ? .bold : allowed(weight)
        return Font.custom("Inter-Regular", size: size, relativeTo: textStyle(for: size)).weight(weight)
    }
    /// Paper's 28 Bold: the street on a stop card, "You're here", an iPad column title. It is the
    /// one size between 24 and 34, asked for by name so sizes passed to `font(_:)` keep snapping.
    static func heading(weight: Font.Weight = .bold) -> Font {
        Font.custom("Inter-Regular", size: 28, relativeTo: .title).weight(allowed(weight))
    }
    /// Paper's display figure: the one number a screen is about (52/58 Dashboard revenue, 54/59
    /// Money, 91A My scorecard). 44 Bold tabular on a phone, 60 on iPad (T12E "Outstanding"). Set it
    /// with `displayTracking(wide:)` and keep it on one line with `minimumScaleFactor`, so a long
    /// amount shrinks on a small phone or at an accessibility size instead of clipping.
    static func display(wide: Bool = false) -> Font {
        Font.custom("Inter-Regular", size: wide ? 60 : 44, relativeTo: .largeTitle).weight(.bold).monospacedDigit()
    }
    /// Paper's -0.03em on the display figure.
    static func displayTracking(wide: Bool = false) -> CGFloat { wide ? -1.8 : -1.32 }
    /// Paper's payment amount (39 Collect payment, 39A Payment received, 39C Scan to pay): 52 Bold
    /// tabular, the amount being collected as the screen. Same one-line rule as `display()`.
    static func paymentAmountFont() -> Font {
        Font.custom("Inter-Regular", size: 52, relativeTo: .largeTitle).weight(.bold).monospacedDigit()
    }
    /// Paper's -0.03em on the 52 payment amount.
    static let paymentAmountTracking: CGFloat = -1.56
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
    /// Paper v2 (2026-11-16): Paper's own sizes, at the default Dynamic Type size. Captions 12,
    /// labels 13, subtitles 14, body 15, rows 16, sheet titles 17, sub-heads 20, sheet heads 22,
    /// money totals 24, and every screen title 34 (lists and records alike). Requested sizes snap
    /// to the nearest Paper size at or below. All scale with Dynamic Type through `textStyle(for:)`.
    ///
    /// requested: <13 → 12 · 13 · 14 · 15 · 16 · 17-19 → 17 · 20-21 → 20 · 22-23 → 22 ·
    /// 24-26 → 24 · 27+ → 34.
    static func onRamp(_ size: CGFloat) -> CGFloat {
        switch size {
        case ..<13: minimumSize
        case 13..<14: 13
        case 14..<15: 14
        case 15..<16: 15
        case 16..<17: 16
        case 17..<20: 17
        case 20..<22: 20
        case 22..<24: 22
        case 24..<27: 24
        // Paper draws record titles and totals at 28 and 30 (48D customer name, 35 estimate total).
        case 27..<29: 28
        case 29..<32: 30
        default: 34
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
    /// Paper v2 (2026-11-16): Inter 400 to 700. Paper sets titles and amounts in 600-700, so
    /// semibold and bold pass; heavy and black resolve to bold; ultralight, thin and light to regular.
    static func allowed(_ weight: Font.Weight) -> Font.Weight {
        if [.heavy, .black].contains(weight) { return .bold }
        if [.ultraLight, .thin, .light].contains(weight) { return .regular }
        return weight
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
    /// Paper v2 radius: fields 14 (search 12), grouped cards 20, commits and chips are pills, icons
    /// are circles. `controlRadius` stays 10 for small controls.
    static let controlRadius: CGFloat = 10
    static let cardRadius: CGFloat = 20
    /// MA-10: chips start at 28 tall and grow with accessible text.
    static let chipHeight: CGFloat = 28
    /// MA-08: the commit starts at 50 tall and grows with accessible text.
    static let commitHeight: CGFloat = 50
    // Paper v2 (decided 2026-11-16): the "Thorbis Mobile" Paper files own the palette. Values are
    // Paper's tokens (get_tokens), light and dark. Token names are unchanged, so every screen follows.
    // `card`/`well` is the panel rows sit on (Paper `card`); `surface` is a sheet's panel; `fill` is
    // a chip or a circle (Paper `muted`); `field` is the sunk well under a text field (Paper
    // `surface`, a step below the card); `sidebar` is the drawer and the iPad sidebar. Text holds
    // 4.5:1 and marks 3:1 in both themes and in Increase Contrast (`scripts/tests/contrast.py`).
    // Eight Paper values sat just under that floor and are one shade off Paper (1-4%, not visible):
    // light muted 6B6B6B→686868, AI 7C5BC2→7757BA, success text 15803D→157D3C, warning text B45309→B15209, the
    // in-progress mark D97706→D07206 and the done mark 16A34A→159E48; dark brand text 5285FF→5587FF;
    // and brand 2F6BFF→2F6AFF, so the white words on every blue commit and pill hold 4.5:1.
    static let card = adaptive(light: 0xFFFFFF, dark: 0x232323)
    /// The panel grouped rows sit on (radius 14). Same as `card`, named for what it is.
    static let well = card
    /// Body: Paper `secondary-foreground`, the grey of supporting lines.
    static let subtle = adaptive(light: 0x555555, dark: 0xB4B4B4, highLight: 0x1A1A1A, highDark: 0xFFFFFF)
    static let successSurface = adaptive(light: 0xDCF5E4, dark: 0x122B1C)
    static let destructiveSurface = adaptive(light: 0xFCE4E4, dark: 0x2A1414)
    /// The canvas every screen is drawn on. Paper draws screens on its `sidebar` token (#F3F2EE /
    /// #141414) with cards on top; Paper's own `background` (#FAF9F6 / #1F1F1F) only frames the drawer.
    static let background = adaptive(light: 0xF3F2EE, dark: 0x141414)
    /// A sheet's or an overlay's panel: the card.
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x232323)
    /// Top bars sit on the canvas.
    static let chrome = adaptive(light: 0xF3F2EE, dark: 0x141414)
    /// The drawer and the iPad sidebar (Paper `sidebar`), and the chosen place in it (`sidebar-accent`).
    static let sidebar = adaptive(light: 0xF3F2EE, dark: 0x141414)
    static let sidebarAccent = adaptive(light: 0xE9E7E1, dark: 0x262626)
    /// The phone drawer's floating panel (Paper 29N / 57N / 58N "Panel": #1B1B1B on the dark
    /// frame, #FFFFFF in the Light copy), a step off the canvas the place behind it is drawn on.
    static let drawerPanel = adaptive(light: 0xFFFFFF, dark: 0x1B1B1B)
    /// A neutral step (kept for call sites); never the electric blue, which is `brand`.
    static let accent = adaptive(light: 0xECEAE5, dark: 0x2A2A2A)
    /// Type (Paper `foreground`).
    static let foreground = adaptive(light: 0x1A1A1A, dark: 0xEDEDED, highLight: 0x000000, highDark: 0xFFFFFF)
    /// The marker: times, counts, labels (Paper `muted-foreground`). Dimmer than body.
    static let muted = adaptive(light: 0x686868, dark: 0xA0A0A0, highLight: 0x1A1A1A, highDark: 0xEDEDED)
    /// A chip's or a circle's ground (Paper `muted`).
    static let fill = adaptive(light: 0xECEAE5, dark: 0x2A2A2A)
    /// The field well (`fieldWell()`): Paper fills a text field with ink at 9% over the card, a step
    /// lighter than the card in dark and darker in light; never the same tone as the card.
    static let field = adaptive(light: 0xECEAE5, dark: 0x2E2E2E)
    /// The 1px rim (Paper `border`: black 10% in light, white 8% in dark). Paper also draws it as the
    /// hairline between rows inside a grouped card (`WellDivider`), never between cards.
    static let border = Color(uiColor: UIColor { traits in
        let high = traits.accessibilityContrast == .high
        return (traits.userInterfaceStyle == .dark ? UIColor.white : UIColor.black)
            .withAlphaComponent(high ? 0.6 : traits.userInterfaceStyle == .dark ? 0.08 : 0.10)
    })
    /// The hairline between rows inside one grouped card. Same colour as the rim.
    static let hairline = border
    /// MA-08: a commit is ink (the type colour) with inverse type, a 1px rim and a short bevel.
    static let ink = foreground
    static let onInk = adaptive(light: 0xFFFFFF, dark: 0x1A1A1A, highLight: 0xFFFFFF, highDark: 0x000000)
    /// Paper's electric blue (#2F6BFF, drawn one step greener as #2F6AFF so white type on it holds
    /// 4.5:1): selected, focus, switches, the one live thing. Never a wash.
    static let brand = Color(hex: 0x2F6AFF)
    /// Brand used as text or a link (Paper `brand-text`).
    static let brandText = adaptive(light: 0x1F55E0, dark: 0x5587FF, highLight: 0x1A44B7, highDark: 0xBDD8FF)
    static let brandSurface = adaptive(light: 0xE3ECFF, dark: 0x182642)
    /// Success as a word (Paper `success-text`); `statusDone` is the mark.
    static let success = adaptive(light: 0x157D3C, dark: 0x4ADE80, highLight: 0x005E00, highDark: 0x94E4A3)
    /// Warning as a word (Paper `warning-text`); `statusInProgress` is the mark.
    static let warning = adaptive(light: 0xB15209, dark: 0xFBBF24, highLight: 0x7E3E00, highDark: 0xFFD27A)
    static let warningSurface = adaptive(light: 0xFCEFD2, dark: 0x2A2008)
    /// Error as a word (Paper `destructive-text`); `statusAttention` is the mark.
    static let destructive = adaptive(light: 0xC81E1E, dark: 0xF15A5A, highLight: 0xA10015, highDark: 0xFFB1AC)
    /// Red as a fill under white type or a white glyph (a badge, a destructive commit): 4.5:1 or better.
    static let destructiveFill = adaptive(light: 0xDC2626, dark: 0xC81E1E)
    /// The chosen segment's raised pill. In dark it sits lighter than the panel so the choice shows.
    /// Paper: ink at 16% over the card track (#434343 dark, #DADADA light), with a short shadow.
    /// Segmented tabs (Today | Week | Map): a quiet track with the chosen segment raised on it,
    /// white in light mode and a lighter grey in dark, under a soft shadow. One look everywhere.
    static let selectedSegment = adaptive(light: 0xFFFFFF, dark: 0x4A4A4A)
    static let segmentTrack = adaptive(light: 0xE7E5E0, dark: 0x262626)
    static let segmentShadow = Color.black.opacity(0.12)
    /// Paper's AI accent: the AI help button, suggestions and drafts. Never for status.
    static let ai = adaptive(light: 0x7757BA, dark: 0x9D7FD1)
    static let aiSurface = adaptive(light: 0xEEE8FA, dark: 0x241B33)
    static let aiBorder = adaptive(light: 0xD6C9F0, dark: 0x3A2E52)

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
    /// Paper `warning`, `success` and `destructive` are the marks; the words use their `-text` twins.
    static let statusInProgress = adaptive(light: 0xD07206, dark: 0xF59E0B)
    static let statusInProgressText = warning
    static let statusInProgressSurface = warningSurface
    static let statusDone = adaptive(light: 0x159E48, dark: 0x22C55E)
    static let statusDoneText = success
    static let statusDoneSurface = successSurface
    static let statusAttention = adaptive(light: 0xDC2626, dark: 0xEF4444)
    static let statusAttentionText = destructive
    static let statusAttentionSurface = destructiveSurface
    /// Paid reads as success too; the word ("Paid", "Invoiced") tells it from Done.
    static let statusInvoiced = adaptive(light: 0x159E48, dark: 0x22C55E)
    static let statusInvoicedText = adaptive(light: 0x157D3C, dark: 0x4ADE80, highLight: 0x005E00, highDark: 0x94E4A3)
    static let statusInvoicedSurface = adaptive(light: 0xDCF5E4, dark: 0x122B1C)

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

/// A grouped section's header: the one section label (`PaperSectionLabel`), kept under this
/// name for the list rooms that pass their own horizontal inset.
struct SectionHeader<Trailing: View>: View {
    let title: String
    var count: Int? = nil
    var horizontalPadding: CGFloat = 4
    @ViewBuilder var trailing: Trailing

    var body: some View {
        PaperSectionLabel(title: title, count: count, inset: horizontalPadding) { trailing }
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
/// Paper v2 commit: a brand-blue pill, 50 tall, white 16 Semibold words. The danger commit is the
/// same pill in the red fill. Disabled fades the fill; a disabled commit should carry a reason.
private struct InkCommit: ViewModifier {
    let enabled: Bool?
    let height: CGFloat
    var fill: Color = Theme.brand
    var type: Color = .white
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.thorbisPressed) private var pressed

    func body(content: Content) -> some View {
        let on = enabled ?? isEnabled
        content
            // Paper: 16 Semibold at 50 and 48; Field mode's 60pt action is 18 Semibold.
            .font(Theme.font(height >= 60 ? 18 : 16, weight: .semibold))
            .foregroundStyle(type.opacity(on ? 1 : 0.7))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(fill.opacity(on ? (pressed ? 0.85 : 1) : 0.4), in: Capsule())
            .contentShape(Capsule())
    }
}

// MARK: - Sheet surfaces

private struct ThorbisSheetCanvasKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// True inside a sheet (and every screen pushed in it): the canvas is the panel, and groups of
    /// rows sink one step below it (golden rules: a modal is "a clean system sheet on the panel").
    var thorbisSheetCanvas: Bool {
        get { self[ThorbisSheetCanvasKey.self] }
        set { self[ThorbisSheetCanvasKey.self] = newValue }
    }
}

/// The ground a screen is drawn on: the canvas on a route, the panel inside a sheet, so a screen
/// shown in a sheet (Settings, an invoice's lines) matches the modals beside it.
struct ThorbisCanvasStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        (environment.thorbisSheetCanvas ? Theme.surface : Theme.background).resolve(in: environment)
    }
}

/// The ground a group of rows sits on: the panel (`Theme.well`) on a route; inside a sheet, where
/// the canvas already is the panel, the sink (`Theme.field`), as `ThorbisSheetGroup` draws it.
struct ThorbisPanelStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        (environment.thorbisSheetCanvas ? Theme.field : Theme.well).resolve(in: environment)
    }
}

extension Theme {
    /// A screen's ground: `background` on a route, `surface` in a sheet. Use for a screen's own
    /// background and for bars pinned to it, so nothing shows as a band of another tone.
    static let canvas = ThorbisCanvasStyle()
}

/// A group's rounded ground: the panel on a route (no rim, v2); in a sheet the sink with its 1px rim.
private struct PanelBackground: ViewModifier {
    let radius: CGFloat
    @Environment(\.thorbisSheetCanvas) private var inSheet
    func body(content: Content) -> some View {
        content
            .background(ThorbisPanelStyle(), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                if inSheet {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.border, lineWidth: 1)
                }
            }
    }
}

extension View {
    /// The rounded ground under a group of rows (`Well`, a card): see `PanelBackground`.
    func panelBackground(cornerRadius: CGFloat = Theme.cardRadius) -> some View {
        modifier(PanelBackground(radius: cornerRadius))
    }

    /// A sheet that shows whole screens (a NavigationStack, Settings, an editor): the panel behind it
    /// (no Liquid Glass) and `thorbisSheetCanvas` for every screen inside, pushed ones included.
    /// Put it outside the sheet's NavigationStack, at the `.sheet` content.
    func thorbisSheetSurface() -> some View {
        self
            .environment(\.thorbisSheetCanvas, true)
            .presentationBackground(Theme.surface)
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
                if busy { ProgressView().tint(.white) } else if let icon { Image(systemName: icon) }
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
    /// The screen's one commit (Paper DS "Buttons"): a brand pill, white 16 Semibold, 50 tall
    /// (`PaperControl.Size.commit`). `height` takes only the ramp's other values: 48 on a card, 60 in
    /// Field mode. Disabled fades the fill, never turns it grey-blue.
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
    /// One way to say when a visit is, used on every list and header (Paper 20): "Today, 4:00 PM",
    /// "Tomorrow, 9:00 AM", otherwise "Thu, Oct 30, 9:00 AM".
    func visitLabel(now: Date = .now, calendar: Calendar = .current) -> String {
        let time = tradeTime
        if calendar.isDate(self, inSameDayAs: now) { return "Today, \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(self, inSameDayAs: tomorrow) {
            return "Tomorrow, \(time)"
        }
        return weekdayStampLabel
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
