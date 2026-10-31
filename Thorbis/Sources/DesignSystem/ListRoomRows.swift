import SwiftUI

// v2 List room (design.thorbis.com "Rooms" and "How we show the work", after Linear mobile's lists):
// rows sit straight on the canvas, with no panel, no line and no card. Space between groups and a
// 13 Medium label with its count do the grouping. The street (or the name) leads in 15 Medium, a
// quieter line says what and who, and the status is a word with its mark at the trailing edge.
// Used by Jobs, Customers, Search, Inbox and a customer's job history. The older `JobListRowContent`
// and `CustomerListRowContent` stay for the screens that still sit on wells.

enum ListRoom {
    /// Rows and labels line up with the screen's gutter.
    static let gutter: CGFloat = Theme.gutter
    /// The pause above a group's label: generous between groups, tight inside one.
    static let groupGap: CGFloat = 24
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
            .padding(.bottom, 2)
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
                Text(street ?? job.title).font(Theme.font(15, weight: .medium))
                    .foregroundStyle(finished ? Theme.muted : Theme.foreground)
                    .lineLimit(stacked ? nil : titleLines)
                    .fixedSize(horizontal: false, vertical: true)
                whatLine(stacked: stacked)
                if !meta.isEmpty {
                    Text(meta).font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                        .lineLimit(stacked ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

    /// The problem, then the customer: two texts so either can be read or found on its own.
    @ViewBuilder private func whatLine(stacked: Bool) -> some View {
        let problem = street != nil ? job.title : nil
        if problem != nil || customer != nil {
            let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                                 : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 4))
            layout {
                if let problem {
                    Text(problem).font(Theme.font(14)).foregroundStyle(Theme.subtle)
                        .lineLimit(stacked ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                }
                if let customer, !customer.isEmpty {
                    Text(problem == nil || stacked ? customer : "· \(customer)").font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
        }
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

/// A customer in a list room: the name (15 Medium), then street · phone; the open job's status word
/// and when trail, or how many jobs, or "Archived".
struct CustomerRoomRow: View {
    let name: String
    /// Street · phone.
    var detail: String? = nil
    /// The open job's status as a word with its mark, and what VoiceOver says for it.
    var status: (tone: StatusTone, word: String, spoken: String)? = nil
    /// When the open visit is ("Today 4 p.m.").
    var when: String? = nil
    /// "3 jobs", shown when there is no open job to name.
    var jobs: String? = nil
    var archived = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                             : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(Theme.font(15, weight: .medium))
                    .foregroundStyle(archived ? Theme.muted : Theme.foreground)
                    .lineLimit(stacked ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail, !detail.isEmpty {
                    Text(detail).font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.subtle)
                        .lineLimit(stacked ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing(stacked: stacked)
        }
        .padding(.horizontal, ListRoom.gutter).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func trailing(stacked: Bool) -> some View {
        VStack(alignment: stacked ? .leading : .trailing, spacing: 2) {
            if archived {
                Text("Archived").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
            } else if let status {
                StatusLabel(tone: status.tone, word: status.word, emphasis: .quiet)
                    .accessibilityLabel(status.spoken)
                    .fixedSize(horizontal: !stacked, vertical: true)
                if let when {
                    Text(when).font(Theme.font(12)).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1)
                }
            } else if let jobs {
                Text(jobs).font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
            }
        }
        .fixedSize(horizontal: !stacked, vertical: true)
    }
}

/// A notice in the Inbox: what happened (Medium while unread, with the accent dot), then the job it
/// is about; the time trails in tabular figures. Unread is weight and the dot only, no word; VoiceOver
/// still says "Unread".
struct InboxRoomRow: View {
    let title: String
    var detail: String? = nil
    var time: String? = nil
    var unread = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var dotColumn: CGFloat = 14

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            // The dot sits in a fixed column so read and unread titles line up.
            Circle().fill(unread ? Theme.brand : .clear).frame(width: 7, height: 7)
                .frame(width: dotColumn, alignment: .leading)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                .accessibilityHidden(true)
            let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                 : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.font(15, weight: unread ? .medium : .regular))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(stacked ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail, !detail.isEmpty {
                        Text(detail).font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .lineLimit(stacked ? nil : 1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let time, !time.isEmpty {
                    Text(time).font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                        .fixedSize()
                }
            }
        }
        .padding(.leading, ListRoom.gutter - 4).padding(.trailing, ListRoom.gutter).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Loading in a list room: the rows' own shape on the canvas (a title bar, a quieter line, a short
/// trailing word), under a label-sized bar. Breathes slowly; still under Reduce Motion. One
/// "Loading" for VoiceOver.
struct ListRoomSkeleton: View {
    var count = 6
    /// A third, short bar for the when-and-who line of a job row.
    var threeLines = true
    var label = true

    var body: some View {
        SkeletonPulse {
            VStack(alignment: .leading, spacing: 0) {
                if label {
                    Capsule().fill(Theme.fill).frame(width: 78, height: 10)
                        .frame(minHeight: 32, alignment: .leading)
                        .padding(.horizontal, ListRoom.gutter).padding(.top, 8).padding(.bottom, 2)
                }
                ForEach(0..<count, id: \.self) { index in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Capsule().fill(Theme.fill).frame(width: Self.titleWidth(index), height: 11)
                            Capsule().fill(Theme.fill.opacity(0.75)).frame(width: Self.lineWidth(index), height: 9)
                            if threeLines {
                                Capsule().fill(Theme.fill.opacity(0.6)).frame(width: 84, height: 8)
                            }
                        }
                        Spacer(minLength: 0)
                        Capsule().fill(Theme.fill.opacity(0.75)).frame(width: 58, height: 9).padding(.top, 2)
                    }
                    .padding(.horizontal, ListRoom.gutter).padding(.vertical, 12)
                    .frame(minHeight: threeLines ? 64 : 52, alignment: .top)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }

    private static func titleWidth(_ index: Int) -> CGFloat { [150, 122, 168, 136, 110, 158][index % 6] }
    private static func lineWidth(_ index: Int) -> CGFloat { [196, 170, 140, 184, 206, 150][index % 6] }
}

/// The view bar under a list room's title (design.thorbis.com: "Display for this list lives on the
/// view bar"): text tabs, then a filter circle that opens its popover. The circle reads as on while a
/// filter narrows the list.
struct ListViewBar<Popover: View>: View {
    let options: [String]
    @Binding var selection: String
    var filterLabel: String? = nil
    var filterActive = false
    @Binding var showFilter: Bool
    @ViewBuilder var popover: Popover

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            PaperTabs(options: options, selection: $selection, textTabs: true)
            if let filterLabel {
                PaperCircleButton(symbol: "line.3.horizontal.decrease", label: filterLabel, size: 36,
                                  fill: filterActive ? Theme.brandSurface : Theme.fill) { showFilter = true }
                    .accessibilityValue(filterActive ? "Filtered" : "")
                    .accessibilityIdentifier("header-filter")
                    .popover(isPresented: $showFilter, arrowEdge: .top) {
                        popover
                            .frame(idealWidth: 320, maxWidth: 360)
                            .presentationCompactAdaptation(.popover)
                            .presentationBackground(Theme.card)
                    }
                    .padding(.trailing, ListRoom.gutter - 4)
            }
        }
    }
}

extension ListViewBar where Popover == EmptyView {
    init(options: [String], selection: Binding<String>) {
        self.init(options: options, selection: selection, filterLabel: nil, showFilter: .constant(false)) { EmptyView() }
    }
}

/// An empty room: what belongs here and the one action that starts it ("No customers yet. Add a
/// customer."). Left-aligned on the canvas like the rows it stands in for; no illustration.
struct ListRoomEmpty: View {
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
            if let message, !message.isEmpty {
                Text(message).font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: "plus")
                        .inkCommit(height: 44)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(PressStyle())
                .padding(.top, 12)
                .accessibilityIdentifier("empty-state-action")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ListRoom.gutter).padding(.top, 24).padding(.bottom, 16)
        .accessibilityElement(children: .contain)
    }
}
