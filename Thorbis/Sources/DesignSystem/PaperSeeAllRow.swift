import SwiftUI

/// The last row of a capped list ("See all 354"): a page about something else shows a list's first
/// few rows and this row opens the whole list, so hundreds of records never bury the page.
/// 16 Medium brand words with the chevron, 52 tall; `inset` is the row's side padding (the card's
/// inset inside a card, the gutter on the canvas).
///
///     PaperSeeAllRow(count: all.count, label: "See all \(all.count) waiting jobs") { showsAll = true }
struct PaperSeeAllRow: View {
    let count: Int
    /// VoiceOver's fuller words ("See all 354 waiting jobs").
    var label: String? = nil
    var inset: CGFloat = PaperCardMetrics.inset
    var identifier: String? = nil
    let action: () -> Void

    /// How many rows a capped list shows before this row.
    static let preview = 3

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("See all \(PaperCount.text(count))").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.brandText)
                Spacer(minLength: 8)
                PaperChevron()
            }
            .padding(.horizontal, inset).frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel(label ?? "See all \(count)")
        .modifier(OptionalIdentifier(identifier: identifier))
    }
}

/// Counts as people read them: "1,284" with grouping, and "999+" where a badge has no room.
enum PaperCount {
    static func text(_ count: Int, locale: Locale = .current) -> String { count.formatted(.number.grouping(.automatic).locale(locale)) }
    /// A badge or pill: "999+" past 999.
    static func badge(_ count: Int, cap: Int = 999) -> String { count > cap ? "\(cap)+" : "\(count)" }
}

/// How long ago, in the unit a person reads at a glance: days under two weeks, then weeks, then
/// months, then years ("121 days" makes you count; "4 months" doesn't).
enum PaperAge {
    /// Whole calendar days from `date` to `now`, never negative.
    static func days(from date: Date, to now: Date = .now, calendar: Calendar = .current) -> Int {
        max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0)
    }

    /// "3 days", "2 weeks", "4 months", "2 years"; "1 day" for one.
    static func span(days: Int) -> String {
        func unit(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        switch days {
        case ..<14: return unit(max(0, days), "day")
        case 14..<60: return unit(days / 7, "week")
        case 60..<730: return unit(days / 30, "month")
        default: return unit(days / 365, "year")
        }
    }

    /// "issued today", "issued yesterday", "issued 3 days ago", "issued 4 months ago".
    static func ago(_ verb: String, days: Int) -> String {
        switch days {
        case ...0: return "\(verb) today"
        case 1: return "\(verb) yesterday"
        default: return "\(verb) \(span(days: days)) ago"
        }
    }
}
