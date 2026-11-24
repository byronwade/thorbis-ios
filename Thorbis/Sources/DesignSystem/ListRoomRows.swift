import SwiftUI

// v2 List room (design.thorbis.com "Rooms" and "How we show the work", after Linear mobile's lists):
// rows sit straight on the canvas, with no panel, no line and no card. Space between groups and a
// 13 Medium label with its count do the grouping. The street (or the name) leads in 15 Medium, a
// quieter line says what and who, and the status is a word with its mark at the trailing edge.
// Used by Jobs, Search, Inbox, Needs attention and a customer's or property's job history.
// `CustomerListRowContent` (`ListRows.swift`) stays for Book a job's customer picker, on a well.

enum ListRoom {
    /// Rows and labels line up with the screen's gutter.
    static let gutter: CGFloat = Theme.gutter
    /// The pause above a group's label: generous between groups, tight inside one.
    static let groupGap: CGFloat = 22
}

/// A group's label on the canvas: 13 Medium in the marker grey with its count ("Scheduled  4"),
/// more space above than below, and an optional trailing accessory (Clear, +).
struct ListGroupLabel<Trailing: View>: View {
    let title: String
    var count: Int? = nil
    var first = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        SectionHeader(title: title, count: count, horizontalPadding: ListRoom.gutter) { trailing }
            .padding(.top, first ? 8 : ListRoom.groupGap)
    }
}

extension ListGroupLabel where Trailing == EmptyView {
    init(title: String, count: Int? = nil, first: Bool = false) {
        self.init(title: title, count: count, first: first) { EmptyView() }
    }
}

/// A job in a list room. Street (15 Medium), then the problem · customer, then when and who; the
/// status word and its mark trail. Finished work reads quieter. The problem stays its own text so a
/// row can be found by it. A row is one VoiceOver stop (its button combines the words).
extension String {
    /// "Kitchen sink backup — Petrov": a no-break space before the dash, so a wrap leaves the dash at the
    /// end of a line ("backup —" / "Petrov") instead of opening the next one with it.
    var dashKeptWithWordBefore: String { replacingOccurrences(of: " \u{2014} ", with: "\u{00A0}\u{2014} ") }
}

struct JobRoomRow: View {
    let job: Job
    /// The street the tech drives to; nil leads with the problem.
    var street: String? = nil
    /// Nil on a customer's own page, where the name is the page.
    var customer: String? = nil
    /// "Today 4 p.m.", "No time yet", or a date for history.
    var when: String? = nil
    /// The assigned tech ("Rosa Martinez", "You").
    var who: String? = nil
    /// A quieter third line (a past job's notes, photos, paid).
    var note: String? = nil
    var pendingStatus: String? = nil
    /// A booked visit whose time has passed: the word reads "Late" in the error hue.
    var late = false
    /// False where the row carries its own Schedule control and its group already names the status.
    var showsStatus = true
    var titleLines = 2
    /// The row's side padding: the gutter on the canvas, the panel's inset inside a record's section.
    var inset: CGFloat = ListRoom.gutter
    @Environment(\.dynamicTypeSize) private var typeSize

    private var status: String { pendingStatus ?? job.status }
    private var meta: String { [when, who].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ") }
    private var finished: Bool { ["completed", "canceled"].contains(job.status) }

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                             : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text((street ?? job.title).dashKeptWithWordBefore).font(Theme.font(16, weight: .medium))
                    .foregroundStyle(finished ? Theme.muted : Theme.foreground)
                    .lineLimit(stacked ? nil : titleLines)
                    .fixedSize(horizontal: false, vertical: true)
                whatLine(stacked: stacked)
                if !meta.isEmpty { metaLine(stacked: stacked) }
                if let note, !note.isEmpty {
                    ExpandableNoteText(text: note, lines: 2, size: 13)
                        .padding(.top, 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsStatus { statusWord }
        }
        .padding(.horizontal, inset).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// The problem, then the customer: two texts so either can be read or found on its own. When both
    /// fit on one line they share it ("Leak · Danielle Marlowe"); otherwise the problem may take two
    /// lines and the customer drops to its own, so the "·" never dangles and a name is never cut to
    /// make room for the other.
    @ViewBuilder private func whatLine(stacked: Bool) -> some View {
        let problem = street != nil ? job.title : nil
        let customer = customer.flatMap { $0.isEmpty ? nil : $0 }
        if let problem, let customer, !stacked {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    problemText(problem, lines: 1)
                    Text("·").font(Theme.font(14)).foregroundStyle(Theme.muted).accessibilityHidden(true)
                    customerText(customer, lines: 1)
                }
                .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 2) {
                    problemText(problem, lines: 2)
                    customerText(customer, lines: 2)
                }
            }
        } else if problem != nil || customer != nil {
            VStack(alignment: .leading, spacing: 2) {
                if let problem { problemText(problem, lines: stacked ? nil : 2) }
                if let customer { customerText(customer, lines: stacked ? nil : 2) }
            }
        }
    }

    /// When and who: one line when it fits, otherwise the tech drops to its own line so the "·" never
    /// dangles at a line end.
    @ViewBuilder private func metaLine(stacked: Bool) -> some View {
        let parts = [when, who].compactMap { $0 }.filter { !$0.isEmpty }
        if parts.count == 2 && !stacked {
            ViewThatFits(in: .horizontal) {
                metaText(meta).fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 2) { ForEach(parts, id: \.self) { metaText($0) } }
            }
        } else {
            metaText(meta)
        }
    }

    private func metaText(_ text: String) -> some View {
        Text(text).font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func problemText(_ text: String, lines: Int?) -> some View {
        Text(text.dashKeptWithWordBefore).font(Theme.font(14)).foregroundStyle(Theme.muted)
            .lineLimit(lines)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func customerText(_ text: String, lines: Int?) -> some View {
        Text(text).font(Theme.font(14)).foregroundStyle(Theme.muted)
            .lineLimit(lines)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var statusWord: some View {
        if late {
            StatusLabel(tone: .attention, word: "Late", emphasis: .quiet)
                .accessibilityLabel("Late, \(status.statusLabel)")
                .fixedSize()
        } else {
            StatusLabel(jobStatus: status, hasTime: job.scheduledFor != nil, pending: pendingStatus != nil, emphasis: .quiet)
                .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
        }
    }
}

/// Loading in a list room (Paper 73E): shapes stand in for rows while they load. Each row is a
/// 14pt title bar over one or two 12pt bars, 8 apart, in the quiet accent tone, under a
/// label-sized bar. Breathes slowly; still under Reduce Motion. One "Loading" for VoiceOver.
struct ListRoomSkeleton: View {
    var count = 6
    /// A third, short bar for the when-and-who line of a job row.
    var threeLines = true
    var label = true

    var body: some View {
        SkeletonPulse {
            VStack(alignment: .leading, spacing: 0) {
                if label {
                    Capsule().fill(Theme.sidebarAccent).frame(width: 78, height: 12)
                        .frame(minHeight: 32, alignment: .leading)
                        .padding(.horizontal, ListRoom.gutter).padding(.top, 8).padding(.bottom, 2)
                }
                ForEach(0..<count, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        Capsule().fill(Theme.sidebarAccent).frame(width: Self.titleWidth(index), height: 14)
                        Capsule().fill(Theme.sidebarAccent).frame(width: Self.lineWidth(index), height: 12)
                        if threeLines {
                            Capsule().fill(Theme.sidebarAccent).frame(width: Self.tailWidth(index), height: 12)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ListRoom.gutter).padding(.vertical, 18)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }

    private static func titleWidth(_ index: Int) -> CGFloat { [180, 150, 200, 160, 130, 170][index % 6] }
    private static func lineWidth(_ index: Int) -> CGFloat { [250, 270, 230, 240, 260, 220][index % 6] }
    private static func tailWidth(_ index: Int) -> CGFloat { [120, 100, 140, 110, 130, 90][index % 6] }
}

/// An empty room: what belongs here and the one action that starts it ("No customers yet", "Add a
/// customer"). It is the shared empty state at screen size (Paper 19), so a list room reads the
/// same as every other empty screen; `symbol` is the room's glyph.
struct ListRoomEmpty: View {
    var symbol: String = "tray"
    /// Paper's glyph for the room (`.jobs`, `.calendar`, `.person`…); the tray only where none fits.
    var glyph: PaperGlyph? = nil
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        PaperEmptyState(symbol: symbol, glyph: glyph, title: title, message: message, actionTitle: actionTitle,
                        prominent: true, action: action)
    }
}
