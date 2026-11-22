import AppIntents
import SwiftUI
import UIKit
import WidgetKit

// The out-of-app surfaces (Lock Screen card, Dynamic Island, Home and Lock Screen widgets) in the
// 2026-10-30 design: cream ground, ink text, street first, status as a dot and a word, one ink
// commit. Compiled into the app and the widget extension so the app's DEBUG preview can draw them.

/// Thorbis tokens for the widget extension, which cannot see the app's `Theme`. Same hex values.
enum WidgetInk {
    // Paper v2 (2026-11-16), the same values as `Theme`.
    static let ground = adaptive(light: 0xFAF9F6, dark: 0x1F1F1F)
    static let panel = adaptive(light: 0xFFFFFF, dark: 0x232323)
    static let field = adaptive(light: 0xECEAE5, dark: 0x2A2A2A)
    static let ink = adaptive(light: 0x1A1A1A, dark: 0xEDEDED)
    static let onInk = adaptive(light: 0xFFFFFF, dark: 0x1A1A1A)
    static let body = adaptive(light: 0x555555, dark: 0xA0A0A0)
    static let accent = adaptive(light: 0x1F55E0, dark: 0x5587FF)
    static let success = adaptive(light: 0x157D3C, dark: 0x4ADE80)
    static let warning = adaptive(light: 0xB15209, dark: 0xFBBF24)
    /// Paper `secondary-foreground` (`Theme.subtle`): the line under a title.
    static let subtle = adaptive(light: 0x555555, dark: 0xB4B4B4)
    /// Paper `brand` (`Theme.brand`).
    static let brand = Color(hex6: 0x2F6BFF)
    /// The ground of a brand action pill (Paper brand at 16 to 24%, `Theme.brandSurface`); its
    /// label is `accent`.
    static let brandSurface = adaptive(light: 0xE3ECFF, dark: 0x182642)
    /// Kept for older callers: the muted line colour.
    static let muted = body

    /// The Dynamic Island is always black, so its tokens are fixed light-on-dark.
    enum Island {
        static let text = Color.white
        static let body = Color.white.opacity(0.62)
        static let track = Color.white.opacity(0.16)
        static let accent = Color(hex6: 0x6090FF)
        static let success = Color(hex6: 0x22C55E)
        static let warning = Color(hex6: 0xF59E0B)
    }

    /// Inter (bundled in both targets) at weights 400 to 700, like `Theme.font`.
    static func font(_ size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        let resolved: Font.Weight = [.heavy, .black].contains(weight) ? .bold
            : [.ultraLight, .thin, .light].contains(weight) ? .regular : weight
        return Font.custom("Inter-Regular", size: size, relativeTo: style).weight(resolved)
    }

    /// Times and counts: Inter with tabular digits.
    static func number(_ size: CGFloat, weight: Font.Weight = .medium, relativeTo style: Font.TextStyle = .body) -> Font {
        font(size, weight: weight, relativeTo: style).monospacedDigit()
    }

    /// The status word's dot colour, matching the job screen's status line.
    static func tint(_ status: String, island: Bool = false) -> Color {
        switch status {
        case "completed", "arrived", "in_progress": island ? Island.success : success
        case "en_route", "dispatched": island ? Island.accent : accent
        case "scheduled", "canceled": island ? Island.body : body
        default: island ? Island.warning : warning
        }
    }

    /// The status as a word: On my way, On site, Working and Paused while under way; the job's
    /// own status ("Dispatched", "Scheduled") before.
    static func word(_ status: String) -> String {
        switch status {
        case "en_route": return "On my way"
        case "arrived": return "On site"
        case "in_progress": return "Working"
        case "paused": return "Paused"
        default:
            let words = status.replacingOccurrences(of: "_", with: " ").lowercased()
            return words.prefix(1).uppercased() + words.dropFirst()
        }
    }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex6: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex6: UInt32) {
        self.init(red: CGFloat((hex6 >> 16) & 0xFF) / 255, green: CGFloat((hex6 >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex6 & 0xFF) / 255, alpha: 1)
    }
}

private extension Color {
    init(hex6: UInt32) { self.init(uiColor: UIColor(hex6: hex6)) }
}

/// A small dot and the status word, the one way status shows anywhere.
struct GlanceStatusWord: View {
    let text: String
    let tint: Color
    var size: CGFloat = 13
    var textColor: Color = WidgetInk.ink

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(text).font(WidgetInk.font(size, weight: .medium)).foregroundStyle(textColor).lineLimit(1)
        }
    }
}

// MARK: - Live Activity

/// The Lock Screen card (Paper 94): the job number and the status word, the problem with the
/// customer and street under it, access facts once on site, the big timer, and the one next step.
struct JobLockScreenView: View {
    let attributes: JobActivityAttributes
    let state: JobActivityAttributes.ContentState

    var body: some View {
        // iOS gives a Lock Screen card 160pt and clips the rest. Four short rows fit: the job
        // and its step, who and where, what is on record for the site, then the time in this
        // step beside the one next step.
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(attributes.cardTitle)
                    .font(WidgetInk.font(17, weight: .semibold, relativeTo: .headline))
                    .foregroundStyle(WidgetInk.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(state.label)
                    .font(WidgetInk.font(13, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(WidgetInk.tint(state.status))
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            Text(detailLine)
                .font(WidgetInk.font(14, relativeTo: .subheadline))
                .foregroundStyle(state.waitingToSync ? WidgetInk.warning : WidgetInk.subtle)
                .lineLimit(1)
            if state.isOnSite, let access = attributes.access {
                Label(access, systemImage: "key")
                    .font(WidgetInk.font(14, weight: .medium, relativeTo: .subheadline))
                    .foregroundStyle(WidgetInk.ink)
                    .lineLimit(1)
                    .accessibilityLabel("On record for this site: \(access)")
            }
            HStack(alignment: .center, spacing: 12) {
                TimerRow(state: state, scheduledFor: attributes.scheduledFor)
                NextStepButton(jobID: attributes.jobID, state: state, compact: true)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        // Text never grows past what the card's fixed height can hold.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    /// "Danielle Marlowe · 412 Birchwood Ln", or the sync warning in its place.
    private var detailLine: String {
        state.waitingToSync ? "Waiting to sync" : attributes.cardDetail
    }
}

/// The time in this step, big, and beside it where the person is: "On site" with its mark once
/// there, or "Booked 10:30 AM" while driving.
private struct TimerRow: View {
    let state: JobActivityAttributes.ContentState
    let scheduledFor: Date?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ElapsedText(since: state.since, alignment: .leading)
                .font(WidgetInk.number(26, weight: .bold, relativeTo: .title))
                .foregroundStyle(WidgetInk.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: 130, alignment: .leading)
                .accessibilityLabel("Time in this step")
            Spacer(minLength: 0)
            // While driving, when the visit is booked for; the step itself is the word on row one.
            if state.status == "en_route", let scheduledFor {
                Text(scheduledFor.formatted(date: .omitted, time: .shortened))
                    .font(WidgetInk.font(14, relativeTo: .subheadline))
                    .foregroundStyle(WidgetInk.body)
                    .lineLimit(1)
                    .accessibilityLabel("Booked \(scheduledFor.formatted(date: .omitted, time: .shortened))")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ElapsedText: View {
    let since: Date
    var alignment: TextAlignment = .trailing

    var body: some View {
        // A step left open for more than a day reads "19d 15h" (as the app's on-site clock does),
        // not "471:15:49", and short enough for the island's compact slot.
        let seconds = Int(Date().timeIntervalSince(since))
        if seconds >= 86_400 {
            Text("\(seconds / 86_400)d \((seconds / 3600) % 24)h").multilineTextAlignment(alignment).lineLimit(1)
        } else {
            Text(timerInterval: since...Date.distantFuture, countsDown: false)
                .multilineTextAlignment(alignment)
        }
    }
}

/// The one forward step: On my way → Arrived → Start through `AdvanceJobStepIntent`, and Wrap up,
/// which needs the app, as a link into the job. The card only changes once the server or the
/// phone's outbox has the step; nothing shows success early.
struct NextStepButton: View {
    let jobID: String
    let state: JobActivityAttributes.ContentState
    var island = false
    /// Beside the timer on the Lock Screen card: as wide as its words, not the whole row.
    var compact = false

    var body: some View {
        if let next = state.nextStep {
            Button(intent: AdvanceJobStepIntent(jobID: jobID, target: next.target)) {
                label(next.buttonTitle)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Updates this job's status.")
        } else if state.status == "in_progress", let url = JobActivityLink.url(jobID: jobID) {
            Link(destination: url) { label("Finish job") }
                .accessibilityHint("Opens the job to finish it.")
        }
    }

    /// Paper 94: a 44pt pill, brand type on the brand surface; white on the always-black island.
    private func label(_ title: String) -> some View {
        Text(title)
            .font(WidgetInk.font(15, weight: .semibold, relativeTo: .subheadline))
            .foregroundStyle(island ? Color.black : WidgetInk.accent)
            .lineLimit(1)
            .padding(.horizontal, compact ? 18 : 0)
            .frame(maxWidth: compact ? nil : .infinity, minHeight: 44)
            .background(Capsule().fill(island ? Color.white : WidgetInk.brandSurface))
            .contentShape(Capsule())
    }
}

/// Driving → On site → Working as three short bars beside the status word.
struct StepTrack: View {
    let step: Int
    let tint: Color
    let empty: Color
    private let names = ["Driving", "On site", "Working"]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(names.indices, id: \.self) { index in
                Capsule().fill(index <= step ? tint : empty).frame(width: 12, height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step + 1) of 3, \(names[step])")
    }
}

/// The expanded Dynamic Island's bottom region: street, problem and customer, access facts on
/// site, then the next step.
struct IslandExpandedBottom: View {
    let attributes: JobActivityAttributes
    let state: JobActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(attributes.headline)
                    .font(WidgetInk.font(17, weight: .medium, relativeTo: .headline))
                    .foregroundStyle(WidgetInk.Island.text)
                    .lineLimit(1)
                Text(state.waitingToSync ? "Waiting to sync" : attributes.subline)
                    .font(WidgetInk.font(13, relativeTo: .footnote))
                    .foregroundStyle(state.waitingToSync ? WidgetInk.Island.warning : WidgetInk.Island.body)
                    .lineLimit(1)
                if state.isOnSite, let access = attributes.access {
                    Label(access, systemImage: "key")
                        .font(WidgetInk.font(13, relativeTo: .footnote))
                        .foregroundStyle(WidgetInk.Island.body)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            NextStepButton(jobID: attributes.jobID, state: state, island: true)
        }
    }
}

// MARK: - Today widgets

struct TodayEntry: TimelineEntry {
    let date: Date
    let items: [TodaySnapshot.Item]
    /// No snapshot yet: the person has not opened the app signed in.
    let signedOut: Bool
    /// "3 of 6 visits" for the day, when there are visits today.
    var progress: TodaySnapshot.DayProgress? = nil
}

/// The time column: a booked time, or the live status word while under way.
func glanceTime(_ item: TodaySnapshot.Item) -> String {
    if TodaySnapshot.liveStatuses.contains(item.status) { return WidgetInk.word(item.status) }
    return item.at?.formatted(date: .omitted, time: .shortened) ?? "Today"
}

struct TodayJobsView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    let entry: TodayEntry
    /// The app's DEBUG preview draws each family itself; WidgetKit sets the real one.
    var previewFamily: WidgetFamily? = nil

    private var family: WidgetFamily { previewFamily ?? widgetFamily }

    var body: some View {
        switch family {
        case .accessoryRectangular: rectangular
        case .accessoryCircular: circular
        case .accessoryInline: inline
        case .systemLarge: large
        case .systemMedium: medium
        default: small
        }
    }

    private var countText: String? { entry.progress?.text }

    /// Paper 94D's header count, "3 of 4 left": what is still to do out of today's visits.
    private var leftOfTotalText: String {
        if let progress = entry.progress, case .visit(_, let total) = progress, entry.items.count <= total {
            return "\(entry.items.count) of \(total) left"
        }
        return TodayJobsView.leftText(entry.items.count)
    }

    // MARK: Home Screen

    @ViewBuilder private var small: some View {
        if let next = entry.items.first {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(TodaySnapshot.liveStatuses.contains(next.status) ? "Now" : "Next stop")
                        .font(WidgetInk.font(13, weight: .semibold, relativeTo: .footnote)).foregroundStyle(WidgetInk.body)
                    Spacer(minLength: 4)
                    if let countText {
                        Text(countText).font(WidgetInk.number(12, weight: .regular, relativeTo: .caption))
                            .foregroundStyle(WidgetInk.body).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                if !TodaySnapshot.liveStatuses.contains(next.status) {
                    // Under way, the status word below says it; the time line would repeat it.
                    Text(glanceTime(next))
                        .font(WidgetInk.number(15, relativeTo: .subheadline))
                        .foregroundStyle(WidgetInk.ink)
                        .padding(.top, 6)
                }
                Spacer(minLength: 4)
                Text(next.headline)
                    .font(WidgetInk.font(17, weight: .medium, relativeTo: .headline))
                    .foregroundStyle(WidgetInk.ink).lineLimit(2).minimumScaleFactor(0.85)
                Text(next.subline)
                    .font(WidgetInk.font(13, relativeTo: .footnote)).foregroundStyle(WidgetInk.body).lineLimit(1)
                GlanceStatusWord(text: WidgetInk.word(next.status), tint: WidgetInk.tint(next.status), size: 12)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(JobActivityLink.url(jobID: next.id))
        } else {
            empty
        }
    }

    @ViewBuilder private var medium: some View {
        if entry.items.isEmpty {
            empty
        } else {
            VStack(alignment: .leading, spacing: 10) {
                header
                Spacer(minLength: 0)
                rows(Array(entry.items.prefix(3)), leadFirst: true)
            }
        }
    }

    @ViewBuilder private var large: some View {
        if let next = entry.items.first {
            VStack(alignment: .leading, spacing: 12) {
                header
                Link(destination: JobActivityLink.url(jobID: next.id) ?? Self.scheduleURL) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(TodaySnapshot.liveStatuses.contains(next.status) ? "Now" : glanceTime(next))
                                .font(WidgetInk.number(14, weight: .semibold, relativeTo: .subheadline))
                                .foregroundStyle(WidgetInk.accent)
                            Spacer(minLength: 8)
                            GlanceStatusWord(text: WidgetInk.word(next.status), tint: WidgetInk.tint(next.status))
                        }
                        Text(next.headline).font(WidgetInk.font(20, weight: .semibold, relativeTo: .title3))
                            .foregroundStyle(WidgetInk.ink).lineLimit(2)
                        Text(next.subline).font(WidgetInk.font(15, relativeTo: .subheadline))
                            .foregroundStyle(WidgetInk.subtle).lineLimit(1)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // The widget's own ground is the card now, so the lead stop sits on the fill.
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(WidgetInk.field))
                }
                let rest = Array(entry.items.dropFirst().prefix(4))
                if !rest.isEmpty {
                    Text("Later today").font(WidgetInk.font(13, weight: .semibold, relativeTo: .footnote)).foregroundStyle(WidgetInk.body)
                    rows(rest, leadFirst: false)
                }
                Spacer(minLength: 0)
            }
        } else {
            empty
        }
    }

    /// Paper 94D: "Today's jobs" and, trailing, "3 of 4 left".
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Today's jobs").font(WidgetInk.font(15, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(WidgetInk.ink).lineLimit(1)
            Spacer(minLength: 4)
            Text(leftOfTotalText)
                .font(WidgetInk.number(13, weight: .regular, relativeTo: .footnote)).foregroundStyle(WidgetInk.body)
                .lineLimit(1)
        }
    }

    /// The rows under the header, 9 apart; the first one's time is the brand's when it leads.
    private func rows(_ items: [TodaySnapshot.Item], leadFirst: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(items) { item in
                row(item, lead: leadFirst && item.id == items.first?.id)
            }
        }
    }

    /// One row (Paper 94D): a 70pt time column, then the problem.
    private func row(_ item: TodaySnapshot.Item, lead: Bool) -> some View {
        Link(destination: JobActivityLink.url(jobID: item.id) ?? Self.scheduleURL) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(TodaySnapshot.liveStatuses.contains(item.status) ? "Now" : glanceTime(item))
                    .font(WidgetInk.number(14, weight: lead ? .semibold : .medium, relativeTo: .subheadline))
                    .foregroundStyle(lead ? WidgetInk.accent : WidgetInk.body)
                    .frame(width: 70, alignment: .leading)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(item.title.isEmpty ? item.headline : item.title)
                    .font(WidgetInk.font(15, weight: .medium, relativeTo: .subheadline))
                    .foregroundStyle(WidgetInk.ink).lineLimit(1)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(rowLabel(item))
        }
    }

    /// VoiceOver keeps what the row no longer draws: the status, the street and the customer.
    private func rowLabel(_ item: TodaySnapshot.Item) -> String {
        let time = TodaySnapshot.liveStatuses.contains(item.status) ? "Now" : glanceTime(item)
        let parts: [String?] = [time, item.title, item.street, item.customer, WidgetInk.word(item.status)]
        return parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    // MARK: Lock Screen

    @ViewBuilder private var rectangular: some View {
        if let next = entry.items.first {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(glanceTime(next)).font(WidgetInk.number(13, relativeTo: .footnote)).widgetAccentable()
                    if !TodaySnapshot.liveStatuses.contains(next.status) {
                        Text("· \(WidgetInk.word(next.status))").font(WidgetInk.font(13, relativeTo: .footnote)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                Text(next.headline).font(WidgetInk.font(15, weight: .medium, relativeTo: .headline)).lineLimit(1)
                Text(countText ?? next.subline).font(WidgetInk.font(13, relativeTo: .footnote))
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(JobActivityLink.url(jobID: next.id))
        } else {
            Text(entry.signedOut ? "Open Thorbis to sign in" : "No more jobs today").font(WidgetInk.font(13, relativeTo: .footnote))
        }
    }

    /// Jobs left today, as a number with the word "left" under it.
    @ViewBuilder private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if entry.signedOut {
                Image(systemName: "person.crop.circle").font(.title3)
                    .accessibilityLabel("Open Thorbis to sign in")
            } else {
                VStack(spacing: 0) {
                    Text("\(entry.items.count)").font(WidgetInk.number(20, relativeTo: .title3)).widgetAccentable()
                    Text("left").font(WidgetInk.font(12, relativeTo: .caption))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(TodayJobsView.leftText(entry.items.count) + " today")
            }
        }
        .widgetURL(entry.items.first.flatMap { JobActivityLink.url(jobID: $0.id) } ?? Self.scheduleURL)
    }

    /// One line next to the Lock Screen clock: the next job's time and street.
    @ViewBuilder private var inline: some View {
        if let next = entry.items.first {
            Text("\(glanceTime(next)) · \(next.headline)")
                .widgetURL(JobActivityLink.url(jobID: next.id))
        } else {
            Text(entry.signedOut ? "Open Thorbis to sign in" : "No more jobs today")
        }
    }

    static func leftText(_ count: Int) -> String {
        count == 1 ? "1 job left" : "\(count) jobs left"
    }

    static let scheduleURL = URL(string: "thorbis://schedule")!

    private var empty: some View {
        GlanceEmpty(signedOut: entry.signedOut, done: entry.progress)
    }
}

/// Nothing left: signed out, or the day is done.
struct GlanceEmpty: View {
    let signedOut: Bool
    var done: TodaySnapshot.DayProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today").font(WidgetInk.font(13, weight: .semibold, relativeTo: .footnote)).foregroundStyle(WidgetInk.body)
            Spacer(minLength: 0)
            Text(signedOut ? "Open Thorbis to sign in" : "No more jobs today")
                .font(WidgetInk.font(17, weight: .semibold, relativeTo: .headline)).foregroundStyle(WidgetInk.ink)
            Text(signedOut ? "Your day shows here." : doneText)
                .font(WidgetInk.font(13, relativeTo: .footnote)).foregroundStyle(WidgetInk.body)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(TodayJobsView.scheduleURL)
    }

    private var doneText: String {
        if case .allDone = done, let done { return "\(done.text). You're all caught up." }
        return "You're all caught up."
    }
}

// MARK: - Next stop widget

/// One stop, big (Paper 94D): "Next stop", the street, the booked time in large type, and the
/// next step as a brand pill.
struct NextStopView: View {
    let entry: TodayEntry

    var body: some View {
        if let next = entry.items.first {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(TodaySnapshot.liveStatuses.contains(next.status) ? "Now" : "Next stop")
                        .font(WidgetInk.font(13, weight: .semibold, relativeTo: .footnote)).foregroundStyle(WidgetInk.body)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if let count = entry.progress, case .visit(let index, let total) = count {
                        Text("\(index)/\(total)").font(WidgetInk.number(12, weight: .regular, relativeTo: .caption))
                            .foregroundStyle(WidgetInk.body)
                            .accessibilityLabel("Visit \(index) of \(total)")
                    }
                }
                Text(next.headline)
                    .font(WidgetInk.font(14, weight: .medium, relativeTo: .subheadline))
                    .foregroundStyle(WidgetInk.ink).lineLimit(1)
                    .accessibilityLabel([next.headline, next.subline].filter { !$0.isEmpty }.joined(separator: ", "))
                // Paper draws the drive time here; the widget has no route, so it is the booked
                // time, or the status word once the job is under way.
                Text(glanceTime(next))
                    .font(WidgetInk.number(30, weight: .bold, relativeTo: .largeTitle))
                    .foregroundStyle(WidgetInk.ink)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .padding(.top, 2)
                Spacer(minLength: 4)
                action(next)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(JobActivityLink.url(jobID: next.id))
        } else {
            GlanceEmpty(signedOut: entry.signedOut, done: entry.progress)
        }
    }

    /// The same next step as the Lock Screen card; Wrap up and anything else open the job.
    @ViewBuilder private func action(_ item: TodaySnapshot.Item) -> some View {
        if let step = JobNextStep.after(item.status) {
            Button(intent: AdvanceJobStepIntent(jobID: item.id, target: step.target)) {
                pill(step.buttonTitle)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Updates this job's status.")
        } else {
            GlanceStatusWord(text: WidgetInk.word(item.status), tint: WidgetInk.tint(item.status), size: 12)
                .frame(minHeight: 44)
        }
    }

    private func pill(_ title: String) -> some View {
        Text(title)
            .font(WidgetInk.font(14, weight: .semibold, relativeTo: .subheadline))
            .foregroundStyle(WidgetInk.accent)
            .lineLimit(1).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Capsule().fill(WidgetInk.brandSurface))
            .contentShape(Capsule())
    }
}
