import AppIntents
import SwiftUI
import UIKit
import WidgetKit

// The out-of-app surfaces (Lock Screen card, Dynamic Island, Home and Lock Screen widgets) in the
// 2026-10-30 design: cream ground, ink text, street first, status as a dot and a word, one ink
// commit. Compiled into the app and the widget extension so the app's DEBUG preview can draw them.

/// Thorbis tokens for the widget extension, which cannot see the app's `Theme`. Same hex values.
enum WidgetInk {
    static let ground = adaptive(light: 0xF7F4EE, dark: 0x1F1F1F)
    static let panel = adaptive(light: 0xFDFCFA, dark: 0x232323)
    static let field = adaptive(light: 0xEDE9E2, dark: 0x2A2A2A)
    static let ink = adaptive(light: 0x201B14, dark: 0xEDEDED)
    static let onInk = adaptive(light: 0xFDFCFA, dark: 0x191919)
    static let body = adaptive(light: 0x59544D, dark: 0xA0A0A0)
    static let accent = adaptive(light: 0x2558E0, dark: 0x6090FF)
    static let success = adaptive(light: 0x18743A, dark: 0x22C55E)
    static let warning = adaptive(light: 0x895400, dark: 0xF59E0B)
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

    /// Inter (bundled in both targets) at weights 400 and 500 only, like `Theme.font`.
    static func font(_ size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        Font.custom("Inter-Regular", size: size, relativeTo: style).weight(weight == .regular ? .regular : .medium)
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

/// The Lock Screen card: status word and timer, the street, the problem and customer, access
/// facts once on site, and the one next step in ink.
struct JobLockScreenView: View {
    let attributes: JobActivityAttributes
    let state: JobActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                GlanceStatusWord(text: state.label, tint: WidgetInk.tint(state.status))
                StepTrack(step: state.step, tint: WidgetInk.tint(state.status), empty: WidgetInk.field)
                Spacer(minLength: 8)
                TimerLine(state: state, scheduledFor: attributes.scheduledFor, color: WidgetInk.ink, quiet: WidgetInk.body)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(attributes.headline)
                    .font(WidgetInk.font(20, weight: .medium, relativeTo: .title3))
                    .foregroundStyle(WidgetInk.ink)
                    .lineLimit(1)
                Text(detailLine)
                    .font(WidgetInk.font(13, relativeTo: .footnote))
                    .foregroundStyle(state.waitingToSync ? WidgetInk.warning : WidgetInk.body)
                    .lineLimit(1)
            }
            if state.isOnSite, let access = attributes.access {
                Label(access, systemImage: "key")
                    .font(WidgetInk.font(13, weight: .medium, relativeTo: .footnote))
                    .foregroundStyle(WidgetInk.ink)
                    .lineLimit(1)
                    .accessibilityLabel("On record for this site: \(access)")
            }
            NextStepButton(jobID: attributes.jobID, state: state)
        }
        .padding(16)
    }

    /// "AC not cooling · Danielle Marlowe · JOB-2214", or the sync warning in its place.
    private var detailLine: String {
        if state.waitingToSync { return "\(attributes.jobNumber) · Waiting to sync" }
        return [attributes.subline, attributes.jobNumber].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// While driving: "Booked 10:30 AM" and the drive so far; on site: the time there, counting up.
private struct TimerLine: View {
    let state: JobActivityAttributes.ContentState
    let scheduledFor: Date?
    let color: Color
    let quiet: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // The status word beside it already says on site or working; only the drive adds
            // something: when the visit is booked.
            if state.status == "en_route", let scheduledFor {
                Text("Booked \(scheduledFor.formatted(date: .omitted, time: .shortened))")
                    .font(WidgetInk.font(13, relativeTo: .footnote)).foregroundStyle(quiet).lineLimit(1)
            }
            ElapsedText(since: state.since)
                .font(WidgetInk.number(15, relativeTo: .subheadline))
                .foregroundStyle(color)
                .frame(maxWidth: 64, alignment: .trailing)
                .accessibilityLabel("Time in this step")
        }
        .accessibilityElement(children: .combine)
    }
}

struct ElapsedText: View {
    let since: Date
    var body: some View {
        Text(timerInterval: since...Date.distantFuture, countsDown: false)
            .multilineTextAlignment(.trailing)
    }
}

/// The one forward step: On my way → Arrived → Start through `AdvanceJobStepIntent`, and Wrap up,
/// which needs the app, as a link into the job. The card only changes once the server or the
/// phone's outbox has the step; nothing shows success early.
struct NextStepButton: View {
    let jobID: String
    let state: JobActivityAttributes.ContentState
    var island = false

    var body: some View {
        if let next = state.nextStep {
            Button(intent: AdvanceJobStepIntent(jobID: jobID, target: next.target)) {
                label(next.buttonTitle, symbol: next.symbol)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Updates this job's status.")
        } else if state.status == "in_progress", let url = JobActivityLink.url(jobID: jobID) {
            Link(destination: url) { label("Wrap up", symbol: "checkmark") }
                .accessibilityHint("Opens the job to finish it.")
        }
    }

    private func label(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(WidgetInk.font(15, weight: .medium, relativeTo: .subheadline))
            .foregroundStyle(island ? Color.black : WidgetInk.onInk)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Capsule().fill(island ? Color.white : WidgetInk.ink))
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

    // MARK: Home Screen

    @ViewBuilder private var small: some View {
        if let next = entry.items.first {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(TodaySnapshot.liveStatuses.contains(next.status) ? "Now" : "Next stop")
                        .font(WidgetInk.font(13, weight: .medium, relativeTo: .footnote)).foregroundStyle(WidgetInk.body)
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
            VStack(alignment: .leading, spacing: 8) {
                header
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entry.items.prefix(3)) { item in row(item) }
                }
                Spacer(minLength: 0)
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
                                .font(WidgetInk.number(15, relativeTo: .subheadline)).foregroundStyle(WidgetInk.ink)
                            Spacer(minLength: 8)
                            GlanceStatusWord(text: WidgetInk.word(next.status), tint: WidgetInk.tint(next.status))
                        }
                        Text(next.headline).font(WidgetInk.font(20, weight: .medium, relativeTo: .title3))
                            .foregroundStyle(WidgetInk.ink).lineLimit(2)
                        Text(next.subline).font(WidgetInk.font(15, relativeTo: .subheadline))
                            .foregroundStyle(WidgetInk.body).lineLimit(1)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(WidgetInk.panel))
                }
                let rest = Array(entry.items.dropFirst().prefix(4))
                if !rest.isEmpty {
                    Text("Later today").font(WidgetInk.font(13, weight: .medium, relativeTo: .footnote)).foregroundStyle(WidgetInk.body)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(rest) { item in row(item) }
                    }
                }
                Spacer(minLength: 0)
            }
        } else {
            empty
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Today").font(WidgetInk.font(15, weight: .medium, relativeTo: .subheadline)).foregroundStyle(WidgetInk.ink)
            Spacer()
            Text(countText ?? TodayJobsView.leftText(entry.items.count))
                .font(WidgetInk.number(13, weight: .regular, relativeTo: .footnote)).foregroundStyle(WidgetInk.body)
        }
    }

    /// One row: time column, street (or title), problem · customer, status word on the right.
    private func row(_ item: TodaySnapshot.Item) -> some View {
        Link(destination: JobActivityLink.url(jobID: item.id) ?? Self.scheduleURL) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(TodaySnapshot.liveStatuses.contains(item.status) ? "Now" : glanceTime(item))
                    .font(WidgetInk.number(13, relativeTo: .footnote))
                    .foregroundStyle(WidgetInk.ink)
                    .frame(width: 62, alignment: .leading)
                    .lineLimit(1).minimumScaleFactor(0.8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.headline).font(WidgetInk.font(15, weight: .medium, relativeTo: .subheadline))
                        .foregroundStyle(WidgetInk.ink).lineLimit(1)
                    Text(item.subline).font(WidgetInk.font(13, relativeTo: .footnote))
                        .foregroundStyle(WidgetInk.body).lineLimit(1)
                }
                Spacer(minLength: 4)
                GlanceStatusWord(text: WidgetInk.word(item.status), tint: WidgetInk.tint(item.status), size: 12)
            }
        }
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
            Text("Today").font(WidgetInk.font(13, weight: .medium, relativeTo: .footnote)).foregroundStyle(WidgetInk.body)
            Spacer(minLength: 0)
            Text(signedOut ? "Open Thorbis to sign in" : "No more jobs today")
                .font(WidgetInk.font(17, weight: .medium, relativeTo: .headline)).foregroundStyle(WidgetInk.ink)
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

/// One stop, big: where to go, what for, and the next step as an ink button.
struct NextStopView: View {
    let entry: TodayEntry

    var body: some View {
        if let next = entry.items.first {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(glanceTime(next)).font(WidgetInk.number(13, relativeTo: .footnote)).foregroundStyle(WidgetInk.ink)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if let count = entry.progress, case .visit(let index, let total) = count {
                        Text("\(index)/\(total)").font(WidgetInk.number(12, weight: .regular, relativeTo: .caption))
                            .foregroundStyle(WidgetInk.body)
                            .accessibilityLabel("Visit \(index) of \(total)")
                    }
                }
                Spacer(minLength: 4)
                Text(next.headline)
                    .font(WidgetInk.font(17, weight: .medium, relativeTo: .headline))
                    .foregroundStyle(WidgetInk.ink).lineLimit(2).minimumScaleFactor(0.85)
                Text(next.street == nil ? next.customer : next.title)
                    .font(WidgetInk.font(13, relativeTo: .footnote)).foregroundStyle(WidgetInk.body).lineLimit(1)
                Spacer(minLength: 6)
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
                .frame(minHeight: 36)
        }
    }

    private func pill(_ title: String) -> some View {
        Text(title)
            .font(WidgetInk.font(15, weight: .medium, relativeTo: .subheadline))
            .foregroundStyle(WidgetInk.onInk)
            .lineLimit(1).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(Capsule().fill(WidgetInk.ink))
            .contentShape(Capsule())
    }
}
