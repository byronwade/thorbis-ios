import SwiftUI

/// Where a job stands, as one of the redesign's status hues (spec "Colour roles"). The app's job
/// statuses are strings from the API; `init(job:scheduled:)` maps every one of them here.
enum StatusTone: Equatable, CaseIterable {
    case unscheduled, scheduled, dispatched, inProgress, done, cancelled, attention, invoiced

    /// draft and booked-without-a-time read as Unscheduled; dispatched and en_route as Dispatched;
    /// arrived, in_progress and paused as In progress; completed as Done; canceled as Cancelled;
    /// invoiced and paid as Invoiced. Anything unknown reads as Scheduled (an empty ring).
    init(jobStatus status: String, hasTime: Bool = true) {
        switch status {
        case "draft", "unscheduled": self = .unscheduled
        case "scheduled": self = hasTime ? .scheduled : .unscheduled
        case "dispatched", "en_route": self = .dispatched
        case "arrived", "in_progress", "paused": self = .inProgress
        case "completed": self = .done
        case "canceled", "cancelled": self = .cancelled
        case "invoiced", "paid": self = .invoiced
        case "overdue", "needs_attention": self = .attention
        default: self = hasTime ? .scheduled : .unscheduled
        }
    }

    /// The glyph's hue (non-text).
    var hue: Color {
        switch self {
        case .unscheduled, .cancelled: Theme.statusUnscheduled
        case .scheduled: Theme.statusScheduled
        case .dispatched: Theme.statusDispatched
        case .inProgress: Theme.statusInProgress
        case .done: Theme.statusDone
        case .attention: Theme.statusAttention
        case .invoiced: Theme.statusInvoiced
        }
    }

    /// The same hue made safe for words (4.5:1 on background, well and `surface`).
    var text: Color {
        switch self {
        case .unscheduled, .cancelled: Theme.muted
        case .scheduled: Theme.statusScheduledText
        case .dispatched: Theme.statusDispatchedText
        case .inProgress: Theme.statusInProgressText
        case .done: Theme.statusDoneText
        case .attention: Theme.statusAttentionText
        case .invoiced: Theme.statusInvoicedText
        }
    }

    /// A chip's tinted ground.
    var surface: Color {
        switch self {
        case .unscheduled, .cancelled: Theme.fill
        case .scheduled: Theme.statusScheduledSurface
        case .dispatched: Theme.statusDispatchedSurface
        case .inProgress: Theme.statusInProgressSurface
        case .done: Theme.statusDoneSurface
        case .attention: Theme.statusAttentionSurface
        case .invoiced: Theme.statusInvoicedSurface
        }
    }

    /// How much of the ring is filled, Linear style: empty, a quarter, a half, or full.
    var fill: Double {
        switch self {
        case .unscheduled, .scheduled: 0
        case .dispatched: 0.25
        case .inProgress: 0.5
        case .done, .cancelled, .attention, .invoiced: 1
        }
    }

    /// The mark inside a full circle.
    var mark: String? {
        switch self {
        case .done: "checkmark"
        case .cancelled: "xmark"
        case .attention: "exclamationmark"
        case .invoiced: "dollarsign"
        default: nil
        }
    }
}

/// Linear's progress ring for a job's status (redesign 2026-10-31): dashed ring for unscheduled, empty
/// ring for scheduled, a quarter for dispatched, half for in progress, full with a check for done,
/// grey with an × for cancelled, red with ! for attention. 16pt at the default size and scales with
/// Dynamic Type. VoiceOver reads the status word, never the shape. `pending` adds a small clock badge
/// for a step saved on this phone and still waiting to sync.
struct StatusGlyph: View {
    let tone: StatusTone
    /// The spoken word ("In progress", "Paused"); the status string's own label.
    let label: String
    var pending = false
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 16

    init(tone: StatusTone, label: String, pending: Bool = false) {
        self.tone = tone
        self.label = label
        self.pending = pending
    }

    /// A job's status string, with whether it has a time (booked without one reads as Unscheduled).
    init(jobStatus status: String, hasTime: Bool = true, pending: Bool = false) {
        self.init(tone: StatusTone(jobStatus: status, hasTime: hasTime), label: status.statusLabel, pending: pending)
    }

    var body: some View {
        let line = max(1.5, size * 0.1)
        ZStack {
            if tone.fill >= 1 {
                Circle().fill(tone.hue)
                if let mark = tone.mark {
                    Image(systemName: mark)
                        .font(.system(size: size * 0.55, weight: .bold))
                        .foregroundStyle(.white)
                }
            } else {
                Circle()
                    .strokeBorder(tone.hue, style: StrokeStyle(lineWidth: line, dash: tone == .unscheduled ? [line * 1.4, line * 1.4] : []))
                if tone.fill > 0 {
                    RingSlice(fraction: tone.fill)
                        .fill(tone.hue)
                        .padding(line * 2)
                }
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if pending {
                Image(systemName: "clock.fill")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(Theme.warning)
                    .background(Circle().fill(Theme.background).padding(-1))
                    .offset(x: size * 0.2, y: size * 0.2)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(pending ? "\(label), waiting to sync" : label)
    }
}

/// A pie slice from twelve o'clock, clockwise.
private struct RingSlice: Shape {
    let fraction: Double
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: center)
        path.addArc(center: center, radius: min(rect.width, rect.height) / 2,
                    startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * fraction), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// A property in Linear's chip row: a tinted capsule with an optional glyph or avatar and a word.
/// With an action it is a button (PressStyle); without one it is a plain label.
struct PropertyChip<Leading: View>: View {
    let text: String
    var tint: Color = Theme.fill
    var textColor: Color = Theme.foreground
    var action: (() -> Void)? = nil
    @ViewBuilder var leading: Leading

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
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .frame(minHeight: Theme.chipHeight)
        .background(tint, in: Capsule())
        .contentShape(Capsule())
    }
}

extension PropertyChip where Leading == AnyView {
    /// A chip with an SF Symbol (or nothing) before the word.
    init(_ text: String, symbol: String? = nil, tint: Color = Theme.fill, textColor: Color = Theme.foreground,
         action: (() -> Void)? = nil) {
        self.init(text: text, tint: tint, textColor: textColor, action: action) {
            AnyView(Group {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).accessibilityHidden(true)
                        .foregroundStyle(textColor)
                }
            })
        }
    }

    /// A job's status as a tinted chip led by its glyph.
    init(jobStatus status: String, hasTime: Bool = true, pending: Bool = false, action: (() -> Void)? = nil) {
        let tone = StatusTone(jobStatus: status, hasTime: hasTime)
        self.init(text: pending ? "\(status.statusLabel) · waiting to sync" : status.statusLabel,
                  tint: tone.surface, textColor: tone.text, action: action) {
            AnyView(StatusGlyph(tone: tone, label: status.statusLabel, pending: pending).accessibilityHidden(true))
        }
    }
}

/// A person as an initials circle on a tinted fill (redesign: avatars are allowed). The hue is
/// picked from the name so a person keeps one colour; white initials hold 4.5:1 on every hue.
struct InitialsAvatar: View {
    let name: String
    var size: CGFloat = 24

    /// Fixed in both themes, each at least 4.5:1 under white.
    static let hues: [Color] = [0x4A55BD, 0x0B6B67, 0x2457DB, 0x17703A, 0x895400, 0xB3262D, 0x6B4FBB].map { Color(hex: $0) }

    static func hue(for name: String) -> Color {
        let sum = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return hues[sum % hues.count]
    }

    var body: some View {
        Text(initials(name))
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Self.hue(for: name), in: Circle())
            .dynamicTypeSize(...DynamicTypeSize.large)
            .accessibilityLabel(name)
    }
}

/// A place's mark in menus and section headers: a small tinted rounded square with a white glyph,
/// like Linear's project icons. Decorative; the word beside it carries the meaning.
struct PlaceMark: View {
    let symbol: String
    var tint: Color = Theme.markGrey
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 26

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .symbolVariant(.fill)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A grouped well (redesign): rows sit on one #F4F4F5 rounded surface (radius 14), separated by
/// inset hairlines. Use `Well { ... }` for hand-built content and `WellDivider` between rows, or
/// `WellList` for a collection.
struct Well<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .environment(\.paperRowInset, PaperCardMetrics.inset)
    }
}

/// The inset hairline between rows in a well. `leading` lines it up with the row's text.
struct WellDivider: View {
    var leading: CGFloat = PaperCardMetrics.inset
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1 / UIScreen.main.scale)
            .padding(.leading, leading)
            .accessibilityHidden(true)
    }
}

/// A collection on one well, with inset hairlines between rows.
struct WellList<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    let data: Data
    var dividerInset: CGFloat = PaperCardMetrics.inset
    @ViewBuilder var row: (Data.Element) -> Row

    var body: some View {
        let items = Array(data)
        Well {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item)
                if index < items.count - 1 { WellDivider(leading: dividerInset) }
            }
        }
    }
}
