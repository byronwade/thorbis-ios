import SwiftUI

/// The visit's drive and on-site time from the steps the tech already taps (`JobHours` rules): no
/// clock of its own, and a missing tap is left out rather than filled in from the schedule.
struct JobTimeSpans: Equatable {
    /// On my way to Mark arrived; while still driving, On my way to now.
    var drive: TimeInterval?
    /// Mark arrived to Wrap up; while the job is open, Mark arrived to now.
    var onSite: TimeInterval?
    /// True while either span is still counting.
    var running = false

    var total: TimeInterval? {
        guard drive != nil || onSite != nil else { return nil }
        return (drive ?? 0) + (onSite ?? 0)
    }

    static func make(_ job: JobRecord, now: Date = Date()) -> JobTimeSpans {
        let enRoute = JobFiltering.date(job.enRouteAt)
        let arrived = JobFiltering.date(job.arrivedAt)
        let completed = job.status == "completed" ? JobFiltering.date(job.completedAt) : nil
        let isOpen = ["arrived", "in_progress", "paused"].contains(job.status)
        var spans = JobTimeSpans()
        if let enRoute, let arrived, arrived >= enRoute {
            spans.drive = arrived.timeIntervalSince(enRoute)
        } else if let enRoute, arrived == nil, job.status == "en_route" {
            spans.drive = max(0, now.timeIntervalSince(enRoute))
            spans.running = true
        }
        if let arrived {
            if let completed, completed >= arrived {
                spans.onSite = completed.timeIntervalSince(arrived)
            } else if isOpen {
                spans.onSite = max(0, now.timeIntervalSince(arrived))
                spans.running = true
            }
        }
        return spans
    }

    /// Paper 21J's durations: "24 min", "1 h 12 min".
    static func words(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval / 60))
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }
}

/// Paper 21J "Time and profit" (More › Time and profit): the 34 Bold title over "AC not cooling ·
/// finished today", then "Time" (a two-tone bar over Drive, On site and Total, 48pt rows) and "By
/// technician" (the assigned tech and their time on a 56pt card). Paper's "Profit" card needs the
/// job's parts and labor cost, which the server does not send, so it is left out.
struct JobTimeView: View {
    let job: JobRecord
    /// The job's name as its sheets write it ("AC not cooling").
    let title: String
    /// Who the job is assigned to, when their name is known.
    let technician: String?

    var body: some View {
        TimelineView(.everyMinute) { context in
            let spans = JobTimeSpans.make(job, now: context.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PaperPageTitle(title: "Time and profit", subtitle: subtitle(now: context.date), columnInset: PaperCardMetrics.margin)
                    if spans.total == nil {
                        Text("Time shows here once the drive or the work starts.")
                            .font(Theme.font(15)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    } else {
                        section("Time") { timeCard(spans) }
                    }
                    if let technician, let total = spans.total {
                        section("By technician") {
                            HStack(spacing: 12) {
                                PaperInitials(name: technician).accessibilityHidden(true)
                                Text(technician).font(Theme.font(16, weight: .medium)).tracking(-0.16)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(JobTimeSpans.words(total)).font(Theme.font(16)).foregroundStyle(Theme.muted)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .frame(minHeight: 56)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 28)
            }
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .accessibilityIdentifier("job-time")
    }

    /// "AC not cooling · finished today": the job, then where it stands.
    private func subtitle(now: Date) -> String {
        var state = job.status.statusLabel.lowercased()
        if job.status == "completed" {
            state = "finished"
            if let done = JobFiltering.date(job.completedAt) {
                state += Calendar.current.isDate(done, inSameDayAs: now) ? " today"
                    : " \(done.formatted(.dateTime.month(.abbreviated).day()))"
            }
        }
        return "\(title) \u{00B7} \(state)"
    }

    /// Paper: an 8pt bar, the drive's share in the warning tone and the work in brand, 3 apart,
    /// then the rows.
    private func timeCard(_ spans: JobTimeSpans) -> some View {
        let drive = spans.drive ?? 0
        let onSite = spans.onSite ?? 0
        let total = max(1, drive + onSite)
        return VStack(spacing: 0) {
            GeometryReader { proxy in
                let both = spans.drive != nil && spans.onSite != nil
                let width = proxy.size.width - (both ? 3 : 0)
                HStack(spacing: 3) {
                    if spans.drive != nil {
                        Capsule().fill(Theme.warning).frame(width: both ? max(8, (width * drive / total).rounded()) : nil)
                    }
                    if spans.onSite != nil { Capsule().fill(Theme.brand) }
                }
            }
            .frame(height: 8)
            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 6)
            .accessibilityHidden(true)
            if let drive = spans.drive { timeRow("Drive", value: JobTimeSpans.words(drive), dot: Theme.warning, first: true) }
            if let onSite = spans.onSite { timeRow("On site", value: JobTimeSpans.words(onSite), dot: Theme.brand, first: spans.drive == nil) }
            if let all = spans.total {
                timeRow(spans.running ? "Total so far" : "Total", value: JobTimeSpans.words(all), dot: nil, first: false, strong: true)
            }
        }
    }

    /// Paper: a 48pt row, a 10pt dot, the name 16 Medium and its time 16 in the muted tone (the
    /// total 16 Semibold in the foreground), a hairline above every row but the first.
    private func timeRow(_ label: String, value: String, dot: Color?, first: Bool, strong: Bool = false) -> some View {
        HStack(spacing: 10) {
            if let dot { Circle().fill(dot).frame(width: 10, height: 10).accessibilityHidden(true) }
            Text(label).font(Theme.font(16, weight: .medium)).tracking(-0.16)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value).font(Theme.font(16, weight: strong ? .semibold : .regular))
                .foregroundStyle(strong ? Theme.foreground : Theme.muted)
        }
        .padding(.trailing, 16).padding(.vertical, 6)
        .frame(minHeight: 48)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Theme.border).frame(height: 1) } }
        .padding(.leading, 16)
        .accessibilityElement(children: .combine)
    }

    /// Paper: a 13 Semibold label 8 over a radius-20 card.
    private func section<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { rows() }
                .panelBackground(cornerRadius: Theme.cardRadius)
        }
    }
}
