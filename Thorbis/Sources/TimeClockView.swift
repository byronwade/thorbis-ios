import SwiftUI

/// Opens the signed-in person's own hours for the active workspace and republishes after each change.
@MainActor
final class TimeClockModel: ObservableObject {
    @Published private(set) var revision = 0
    @Published private(set) var loadError: String?
    @Published var actionError: String?
    private(set) var identity: String?
    private var store: TimeClockStore?

    var isBound: Bool { store != nil }
    var entries: [TimeClockEntry] { store?.entries ?? [] }
    var timeOff: [TimeClockTimeOff] { store?.timeOff ?? [] }
    var active: TimeClockEntry? { store?.active }

    static func key(userID: String?, organizationID: String?) -> String {
        "\(userID?.lowercased() ?? "")|\(organizationID?.lowercased() ?? "")"
    }

    func bind(userID: String?, organizationID: String?, directory: URL? = nil) {
        let next = Self.key(userID: userID, organizationID: organizationID)
        guard identity != next || store == nil else { return }
        // Drop the last person's hours before anything else can read them.
        store = nil
        identity = next
        actionError = nil
        loadError = nil
        defer { revision += 1 }
        guard let userID, let organizationID else {
            loadError = TimeClockProblem.invalidIdentity.errorDescription
            return
        }
        do {
            #if DEBUG
            if PaperPreview.enabled, directory == nil {
                store = try PlacesPreviewData.timeClock(userID: userID, organizationID: organizationID)
                return
            }
            #endif
            store = try TimeClockStore(userID: userID, organizationID: organizationID, directory: directory)
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Runs one change. False (with the reason in `actionError`) when it was not saved.
    @discardableResult
    func perform(_ change: (TimeClockStore) throws -> Void) -> Bool {
        guard let store else {
            actionError = loadError ?? TimeClockProblem.invalidIdentity.errorDescription
            return false
        }
        do {
            try change(store)
            actionError = nil
            revision += 1
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    /// The same, for a sheet that shows its own error.
    func attempt(_ change: (TimeClockStore) throws -> Void) throws {
        guard let store else { throw TimeClockProblem.invalidIdentity }
        try change(store)
        actionError = nil
        revision += 1
    }
}

/// How this place writes days and times. Times are the app's one clock (`tradeTime`).
enum TimeClockWords {
    static let dot = " \u{00B7} "

    /// "Tue · Jul 21"
    static func dayChip(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated)) + dot + date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "Mon, Jul 20"
    static func longDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "Jul 13 – Jul 19"
    static func weekRange(_ week: DateInterval) -> String {
        let last = week.end.addingTimeInterval(-1)
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return "\(week.start.formatted(style)) \u{2013} \(last.formatted(style))"
    }

    /// A punch said with its day when it is not on `day` ("Mon, Jul 20, 10:00 p.m.").
    static func punch(_ date: Date, on day: Date, calendar: Calendar = .current) -> String {
        calendar.isDate(date, inSameDayAs: day) ? date.tradeTime : "\(longDay(date)), \(date.tradeTime)"
    }

    /// "7:15 a.m. – 3:45 p.m.", "7:58 a.m. – now"
    static func span(_ day: TimeClockMath.Day) -> String {
        guard let first = day.firstIn else { return "No hours" }
        if day.isOpen { return "\(first.tradeTime) \u{2013} now" }
        guard let last = day.lastOut else { return first.tradeTime }
        return "\(first.tradeTime) \u{2013} \(last.tradeTime)"
    }

    /// Paper 56C's row: "8:00\u{2013}4:30", the hours without their AM and PM.
    static func shortSpan(_ day: TimeClockMath.Day) -> String {
        guard let first = day.firstIn else { return "No hours" }
        func plain(_ date: Date) -> String {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            return String(format: "%d:%02d", ((parts.hour ?? 0) + 11) % 12 + 1, parts.minute ?? 0)
        }
        guard let last = day.lastOut else { return plain(first) }
        return "\(plain(first))\u{2013}\(plain(last))"
    }

    /// "Jul 13\u{2013}19", or "Jul 27 \u{2013} Aug 2" across two months.
    static func shortRange(from start: Date, to end: Date, calendar: Calendar = .current) -> String {
        let month = Date.FormatStyle.dateTime.month(.abbreviated).day()
        if calendar.isDate(start, equalTo: end, toGranularity: .month) {
            return "\(start.formatted(month))\u{2013}\(end.formatted(.dateTime.day()))"
        }
        return "\(start.formatted(month)) \u{2013} \(end.formatted(month))"
    }

    static func span(_ entry: TimeClockEntry) -> String {
        guard let out = entry.clockOut else { return "In since \(entry.clockIn.tradeTime)" }
        return "\(entry.clockIn.tradeTime) \u{2013} \(punch(out, on: entry.clockIn))"
    }

    static func timeOffRange(_ request: TimeClockTimeOff, calendar: Calendar = .current) -> String {
        if request.allDay {
            return calendar.isDate(request.from, inSameDayAs: request.to)
                ? longDay(request.from) : "\(longDay(request.from)) \u{2013} \(longDay(request.to))"
        }
        return "\(longDay(request.from)), \(request.from.tradeTime) \u{2013} \(punch(request.to, on: request.from, calendar: calendar))"
    }

    static func timeOffLength(_ request: TimeClockTimeOff, calendar: Calendar = .current) -> String {
        if request.allDay {
            let days = TimeClockMath.timeOffDays(request, calendar: calendar)
            return days == 1 ? "1 day" : "\(days) days"
        }
        return TimeClockMath.durationLabel(request.to.timeIntervalSince(request.from))
    }
}

enum TimeClockSheet: Identifiable {
    case add
    case edit(TimeClockEntry)
    case fix(TimeClockEntry)
    case timeOff(TimeClockTimeOff?)

    var id: String {
        switch self {
        case .add: "add"
        case .edit(let entry): "edit-\(entry.id)"
        case .fix(let entry): "fix-\(entry.id)"
        case .timeOff(let request): "timeoff-\(request?.id ?? "new")"
        }
    }
}

enum TimeClockRoute: String, Hashable {
    case timesheet, entries, timeOff
}

private struct TimeClockSheetHost: ViewModifier {
    @ObservedObject var model: TimeClockModel
    @Binding var sheet: TimeClockSheet?

    func body(content: Content) -> some View {
        content.sheet(item: $sheet) { item in
            SheetSurface {
                switch item {
                case .add: TimeClockEntryEditor(mode: .add, model: model)
                case .edit(let entry): TimeClockEntryEditor(mode: .edit(entry), model: model)
                case .fix(let entry): TimeClockEntryEditor(mode: .fix(entry), model: model)
                case .timeOff(let request): TimeClockTimeOffEditor(request: request, model: model)
                }
            }
        }
    }
}

extension View {
    func timeClockSheets(_ sheet: Binding<TimeClockSheet?>, model: TimeClockModel) -> some View {
        modifier(TimeClockSheetHost(model: model, sheet: sheet))
    }
}

// MARK: - Parts

/// Paper 27: a grouped card, radius 20, rows clipped to it.
struct TimeClockCard<Content: View>: View {
    var radius: CGFloat = Theme.cardRadius
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// A section's label (13 Semibold, muted) with an optional figure at the trailing edge.
struct TimeClockSectionLabel: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(Theme.font(13, weight: .semibold)).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let trailing { Text(trailing).font(Theme.font(13)) }
        }
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 4).padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }
}

/// A label and its value, 56 tall; the value drops under the label when the two don't fit.
struct TimeClockValueRow: View {
    let label: String
    let value: String
    var strong = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { labelText; Spacer(minLength: 12); valueText }
            VStack(alignment: .leading, spacing: 2) { labelText; valueText }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var labelText: some View {
        Text(label).font(Theme.font(16, weight: strong ? .semibold : .regular))
            .foregroundStyle(strong ? Theme.foreground : Theme.subtle)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valueText: some View {
        Text(value).font(Theme.font(16, weight: strong ? .bold : .medium))
            .foregroundStyle(Theme.foreground)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A status pill: a 7pt dot in the hue, then the words.
struct TimeClockStatusChip: View {
    let text: String
    let dot: Color
    let ink: Color
    let surface: Color

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(dot).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(text).font(Theme.font(13, weight: .semibold)).foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .frame(minHeight: 26)
        .background(surface, in: Capsule())
    }
}

/// A commit pill from the ramp (50 tall, 16 Semibold): brand for the one main action, quiet for
/// the other. `height` and `size` are kept so older call sites compile; the ramp decides.
struct TimeClockPill: View {
    let title: String
    var primary = false
    var height: CGFloat = 50
    var size: CGFloat = 16

    var body: some View {
        Text(title).paperButton(.commit, tone: primary ? .brand : .quiet, fills: true)
    }
}

/// "Kept on this phone", said the same way on every time screen.
struct TimeClockPhoneNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "iphone").font(.system(size: 12, weight: .medium)).accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(Theme.font(13)).foregroundStyle(Theme.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}

/// A pushed page's title: 34 Bold over a muted line.
struct TimeClockPageTitle: View {
    let title: String
    let subtitle: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.font(34, weight: .bold)).tracking(-0.85)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(identifier)
            Text(subtitle).font(Theme.font(15)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Root

/// Paper 27 "Time clock" (with 27C "On break"): today's running total, the day's punches, this
/// week by day, and the clock in / break / clock out bar. Hours are this person's own and are kept
/// on this phone; the screen says so where Paper shows "Synced".
struct TimeClockView: View {
    @EnvironmentObject private var session: SessionController
    @StateObject private var model = TimeClockModel()
    @State private var sheet: TimeClockSheet?
    @State private var route: TimeClockRoute?
    @Environment(\.dynamicTypeSize) private var typeSize

    init() {}

    private var identityKey: String {
        TimeClockModel.key(userID: session.user?.id, organizationID: session.activeOrganization?.id)
    }

    var body: some View {
        ScrollView {
            TimelineView(.periodic(from: .now, by: model.active == nil ? 30 : 1)) { context in
                page(now: context.date)
            }
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ThorbisToolbarItem(placement: .topBarTrailing) { moreMenu } }
        .safeAreaInset(edge: .bottom, spacing: 0) { if model.isBound { bar } }
        .task(id: identityKey) {
            sheet = nil
            route = nil
            model.bind(userID: session.user?.id, organizationID: session.activeOrganization?.id)
            #if DEBUG
            if PaperPreview.enabled {
                switch PaperPreview.screen {
                case "time-clock-timeoff", "time-clock-date": sheet = .timeOff(nil)
                case "time-clock-fix": if let open = model.active { sheet = .fix(open) }
                case "time-clock-timesheet": route = .timesheet
                default: break
                }
            }
            #endif
        }
        .thorbisDestination(item: $route) { place in
            switch place {
            case .timesheet: TimeClockTimesheetView(model: model)
            case .entries: TimeClockEntriesView(model: model)
            case .timeOff: TimeClockTimeOffView(model: model)
            }
        }
        .timeClockSheets($sheet, model: model)
    }

    // MARK: Header

    /// Paper 27: the menu circle and the ••• circle share the top row (here the navigation bar);
    /// under them the 34 Bold title, 4 in from the cards' edge and 14 above the first card.
    private var header: some View {
        Text("Time clock").font(Theme.font(34, weight: .bold)).tracking(-0.85)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("timeclock-root")
            .padding(.horizontal, 4)
            .padding(.top, 2).padding(.bottom, 14)
    }

    private var moreMenu: some View {
        ThorbisMenu(items: [
            ThorbisMenuItem("Timesheet", icon: "calendar") { route = .timesheet },
            ThorbisMenuItem("Past entries", icon: "list.bullet") { route = .entries },
            ThorbisMenuItem("Time off", icon: "sun.max") { route = .timeOff },
            ThorbisMenuItem("Add missed punch", icon: "plus", startsGroup: true) { sheet = .add },
        ], accessibilityLabel: "More for time clock") {
            PaperCircleLabel(symbol: "ellipsis", size: 44, fill: Theme.card)
        }
        .accessibilityIdentifier("timeclock-more")
    }

    // MARK: Page

    @ViewBuilder private func page(now: Date) -> some View {
        let calendar = Calendar.current
        let entries = model.entries
        let week = TimeClockMath.weekInterval(containing: now, calendar: calendar)
        let days = TimeClockMath.days(entries, in: week, now: now, calendar: calendar)
        let today = days.first { calendar.isDate($0.date, inSameDayAs: now) }
        let active = model.active
        VStack(alignment: .leading, spacing: 0) {
            header
            if let problem = model.actionError ?? model.loadError {
                Text(problem).font(Theme.font(15)).foregroundStyle(Theme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4).padding(.bottom, 12)
                    .accessibilityIdentifier("timeclock-error")
            }
            if let active, TimeClockMath.isMissedClockOut(active, now: now) {
                missedCard(active).padding(.bottom, 12)
            }
            hero(now: now, active: active, today: today)
            if let today, !today.entries.isEmpty {
                todayCard(today, active: active, now: now).padding(.top, 22)
            }
            if active?.openBreak != nil {
                // Paper 27C: on break the page is the break and today; the week is in the ••• menu's
                // Timesheet. Its note promises a reminder and dispatch; this one says what is true.
                Text("Kept on this phone \u{00B7} nobody is told you\u{2019}re on break.")
                    .font(Theme.font(13)).foregroundStyle(Theme.subtleForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4).padding(.top, 10)
            } else {
                weekCard(days, now: now, calendar: calendar).padding(.top, 22)
                // Where Paper prints "Synced 2m ago": these hours are not synced.
                PlacePhoneLine(text: "Kept on this phone \u{00B7} not sent to payroll")
                    .padding(.horizontal, -(PaperCardMetrics.margin + 4))
                    .padding(.top, 16)
            }
        }
        .padding(.horizontal, PaperCardMetrics.margin)
        .padding(.bottom, 24)
    }

    /// Paper 27B's entry point: yesterday's shift is still running.
    private func missedCard(_ entry: TimeClockEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("You didn\u{2019}t clock out").font(Theme.font(16, weight: .semibold))
                Text("Clocked in \(TimeClockWords.longDay(entry.clockIn)) at \(entry.clockIn.tradeTime). Set when you stopped so the day\u{2019}s hours are right.")
                    .font(Theme.font(14))
            }
            .foregroundStyle(Theme.warning)
            .fixedSize(horizontal: false, vertical: true)
            Button { sheet = .fix(entry) } label: {
                Text("Fix clock-out").font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.brandText)
                    .frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("timeclock-fix-banner")
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warningSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    // MARK: Hero

    private func chip(now: Date, active: TimeClockEntry?) -> TimeClockStatusChip {
        guard let active else {
            return TimeClockStatusChip(text: "Clocked out", dot: Theme.muted, ink: Theme.subtle, surface: Theme.fill)
        }
        if TimeClockMath.isMissedClockOut(active, now: now) {
            return TimeClockStatusChip(text: "No clock-out", dot: Theme.warning, ink: Theme.warning, surface: Theme.warningSurface)
        }
        if active.openBreak != nil {
            return TimeClockStatusChip(text: "On break\(TimeClockWords.dot)unpaid", dot: Theme.warning, ink: Theme.warning, surface: Theme.warningSurface)
        }
        return TimeClockStatusChip(text: "Clocked in\(TimeClockWords.dot)since \(TimeClockWords.punch(active.clockIn, on: now))",
                                   dot: Theme.success, ink: Theme.success, surface: Theme.successSurface)
    }

    private func hero(now: Date, active: TimeClockEntry?, today: TimeClockMath.Day?) -> some View {
        let pause = active?.openBreak
        let worked = today?.seconds ?? 0
        let figure = pause.map { TimeClockMath.clockLabel(now.timeIntervalSince($0.start), short: true) }
            ?? TimeClockMath.clockLabel(worked)
        let line: String = {
            if let pause {
                guard let planned = pause.plannedMinutes else { return "Break\(TimeClockWords.dot)unpaid" }
                return "Break\(TimeClockWords.dot)\(TimeClockMath.minutesLabel(planned)) unpaid"
            }
            // Paper prints the job being worked; an entry carries no job, so the line is left out.
            if active != nil { return "" }
            return worked > 0 ? "Worked today" : "Clock in to start today\u{2019}s hours"
        }()
        let status = chip(now: now, active: active)
        return VStack(alignment: .leading, spacing: pause == nil ? 10 : 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { dayLabel(now); Spacer(minLength: 8); status }
                VStack(alignment: .leading, spacing: 6) { dayLabel(now); status }
            }
            // Paper 27: 52 Bold; 27C: 64 Bold while the break runs.
            ViewThatFits(in: .horizontal) {
                heroFigure(figure, onBreak: pause != nil).fixedSize()
                heroFigure(figure, onBreak: pause != nil).minimumScaleFactor(0.5)
            }
                .accessibilityLabel(pause == nil ? "Worked today, \(TimeClockMath.durationLabel(worked))"
                                                 : "On break for \(TimeClockMath.durationLabel(now.timeIntervalSince(pause?.start ?? now)))")
                .accessibilityIdentifier("timeclock-running-total")
            if !line.isEmpty {
                Text(line).font(Theme.font(pause == nil ? 15 : 16)).foregroundStyle(Theme.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let pause { breakProgress(pause, now: now).padding(.top, 10) }
        }
        .padding(.horizontal, 18).padding(.top, pause == nil ? 18 : 16).padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: pause == nil ? 22 : 24, style: .continuous))
    }

    /// Paper 27: 52 Bold; 27C: 64 Bold with tabular digits while the break counts.
    private func heroFigure(_ figure: String, onBreak: Bool) -> some View {
        // Past the type ramp's 34, so asked for by size.
        let font = Font.custom("Inter-Regular", size: onBreak ? 64 : 52, relativeTo: .largeTitle).weight(.bold)
        return Text(figure).font(onBreak ? font.monospacedDigit() : font).tracking(onBreak ? -2.56 : -1.56)
            .lineLimit(1)
    }

    private func dayLabel(_ now: Date) -> some View {
        Text(TimeClockWords.dayChip(now)).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
    }

    /// Paper 27C: how far through the chosen break length, when it began and when it ends.
    private func breakProgress(_ pause: TimeClockBreak, now: Date) -> some View {
        let elapsed = max(0, now.timeIntervalSince(pause.start))
        let planned = TimeInterval((pause.plannedMinutes ?? 0) * 60)
        let ending: String? = {
            guard planned > 0 else { return nil }
            let left = planned - elapsed
            if left > 0 {
                let minutes = Int((left / 60).rounded(.up))
                return "\(minutes) min left\(TimeClockWords.dot)back by \(pause.start.addingTimeInterval(planned).tradeTime)"
            }
            return "\(Int((-left / 60).rounded(.down))) min over"
        }()
        return VStack(alignment: .leading, spacing: 8) {
            if planned > 0 {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.fill)
                        Capsule().fill(Theme.warning).frame(width: proxy.size.width * min(1, elapsed / planned))
                    }
                }
                .frame(height: 8)
                .accessibilityHidden(true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Text("Started \(pause.start.tradeTime)")
                    Spacer(minLength: 8)
                    if let ending { Text(ending) }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Started \(pause.start.tradeTime)")
                    if let ending { Text(ending) }
                }
            }
            .font(Theme.font(13)).foregroundStyle(Theme.muted)
        }
    }

    // MARK: Today

    private func todayCard(_ today: TimeClockMath.Day, active: TimeClockEntry?, now: Date) -> some View {
        let first = today.entries.first?.clockIn ?? today.date
        return VStack(alignment: .leading, spacing: 0) {
            TimeClockSectionLabel(title: "Today")
            TimeClockCard {
                if active?.openBreak != nil {
                    PlaceSheetValueRow(label: "Clocked in", value: TimeClockWords.punch(first, on: now), emphasis: true)
                } else {
                    TimeClockValueRow(label: "Clocked in", value: TimeClockWords.punch(first, on: now))
                }
                if !today.isOpen, let out = today.lastOut {
                    WellDivider(leading: 16)
                    TimeClockValueRow(label: "Clocked out", value: out.tradeTime)
                }
                if active?.openBreak == nil {
                    WellDivider(leading: 16)
                    TimeClockValueRow(label: "Break", value: today.breakSeconds >= 60 ? TimeClockMath.durationLabel(today.breakSeconds) : "None")
                    WellDivider(leading: 16)
                    TimeClockValueRow(label: "Total", value: TimeClockMath.durationLabel(today.seconds), strong: true)
                } else {
                    // Paper 27C: on break the total stands still and reads "Worked before break".
                    WellDivider(leading: 0)
                    PlaceSheetValueRow(label: "Worked before break", value: TimeClockMath.durationLabel(today.seconds), emphasis: true)
                }
            }
        }
    }

    // MARK: This week

    private func weekCard(_ days: [TimeClockMath.Day], now: Date, calendar: Calendar) -> some View {
        let worked = days.filter { !$0.entries.isEmpty }
        let total = days.reduce(0) { $0 + $1.seconds }
        return VStack(alignment: .leading, spacing: 0) {
            TimeClockSectionLabel(title: "This week", trailing: "\(TimeClockMath.decimalHours(total))h")
            TimeClockCard {
                if worked.isEmpty {
                    PaperInlineEmpty("No hours this week yet.")
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                }
                ForEach(worked) { day in
                    if day.id != worked.first?.id { WellDivider(leading: 16) }
                    Button { route = .entries } label: { weekRow(day, isToday: calendar.isDate(day.date, inSameDayAs: now)) }
                        .buttonStyle(RowPressStyle())
                        .accessibilityHint("Opens past entries")
                }
                WellDivider(leading: 16)
                Button { sheet = .add } label: {
                    HStack(spacing: 10) {
                        PaperIcon(.placePlus, size: 18, color: Theme.brandText)
                        Text("Add missed punch").font(Theme.font(16, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Theme.brandText)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .accessibilityIdentifier("timeclock-add-punch")
            }
        }
    }

    /// Paper 27: the day in a 52pt column, the punches, the hours at the trailing edge.
    private func weekRow(_ day: TimeClockMath.Day, isToday: Bool) -> some View {
        let live = isToday && day.isOpen
        let name = isToday ? "Today" : day.date.formatted(.dateTime.weekday(.abbreviated))
        let hours = "\(TimeClockMath.decimalHours(day.seconds))h"
        return HStack(alignment: .center, spacing: 12) {
            Text(name).font(Theme.font(15, weight: isToday ? .semibold : .medium))
                .foregroundStyle(isToday ? Theme.foreground : Theme.subtle)
                .frame(minWidth: 52, alignment: .leading)
            Text(day.missedClockOut ? "No clock-out" : TimeClockWords.span(day))
                .font(Theme.font(16, weight: .medium))
                .foregroundStyle(day.missedClockOut ? Theme.warning : Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(hours).font(Theme.font(16, weight: live ? .semibold : .medium))
                .foregroundStyle(live ? Theme.brandText : Theme.foreground)
                .fixedSize().frame(minWidth: 48, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(day.missedClockOut ? "no clock-out" : TimeClockWords.span(day)), \(TimeClockMath.durationLabel(day.seconds))")
    }

    // MARK: Bar

    /// Paper 27: Start break beside Clock out; 27C: Clock out beside End break. Clocked out, the
    /// one action is Clock in.
    @ViewBuilder private var bar: some View {
        let active = model.active
        // Paper 27C sets Clock out at 122 beside End break at 226, 10 apart.
        let row = active?.openBreak != nil ? PlaceWeightedRow(weights: [1, 1.85], spacing: 10) : PlaceWeightedRow()
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(row)
        layout {
            if let active {
                if TimeClockMath.isMissedClockOut(active, now: Date()) {
                    Button { model.perform { try $0.clockOut() } } label: { TimeClockPill(title: "Clock out now") }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("timeclock-clock-out")
                    Button { sheet = .fix(active) } label: { TimeClockPill(title: "Fix clock-out", primary: true) }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("timeclock-fix-clock-out")
                } else if active.openBreak != nil {
                    // Paper 27C: 56-tall pills in 17 Semibold.
                    Button { model.perform { try $0.clockOut() } } label: { TimeClockPill(title: "Clock out") }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("timeclock-clock-out")
                    Button { model.perform { try $0.endBreak() } } label: { TimeClockPill(title: "End break", primary: true) }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("timeclock-end-break")
                } else {
                    ThorbisMenu(items: [
                        ThorbisMenuItem("Lunch", icon: "fork.knife", detail: "30 min") { model.perform { try $0.startBreak(plannedMinutes: 30) } },
                        ThorbisMenuItem("Short break", icon: "cup.and.saucer", detail: "15 min") { model.perform { try $0.startBreak(plannedMinutes: 15) } },
                        ThorbisMenuItem("No set length", icon: "pause") { model.perform { try $0.startBreak() } },
                    ], title: "Breaks are unpaid", accessibilityLabel: "Start break") {
                        TimeClockPill(title: "Start break")
                    }
                    .accessibilityIdentifier("timeclock-start-break")
                    Button { model.perform { try $0.clockOut() } } label: { TimeClockPill(title: "Clock out", primary: true) }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("timeclock-clock-out")
                }
            } else {
                Button { model.perform { try $0.clockIn() } } label: { TimeClockPill(title: "Clock in", primary: true) }
                    .buttonStyle(PressStyle())
                    .accessibilityIdentifier("timeclock-clock-in")
            }
        }
        .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 28).padding(.bottom, 8)
        .background(LinearGradient(stops: [.init(color: Theme.background.opacity(0), location: 0), .init(color: Theme.background, location: 0.34)],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .bottom).allowsHitTesting(false))
    }
}

// MARK: - Past entries

/// The list of past entries, newest first, grouped by week. A finished entry opens its editor; an
/// entry left running opens Fix clock-out.
struct TimeClockEntriesView: View {
    @ObservedObject var model: TimeClockModel
    @State private var sheet: TimeClockSheet?

    private struct Week: Identifiable {
        let interval: DateInterval
        var entries: [TimeClockEntry]
        var id: Date { interval.start }
    }

    private func weeks(_ entries: [TimeClockEntry], calendar: Calendar) -> [Week] {
        var result: [Week] = []
        for entry in entries {
            let interval = TimeClockMath.weekInterval(containing: entry.clockIn, calendar: calendar)
            if let index = result.firstIndex(where: { $0.interval.start == interval.start }) {
                result[index].entries.append(entry)
            } else {
                result.append(Week(interval: interval, entries: [entry]))
            }
        }
        return result
    }

    var body: some View {
        let now = Date()
        let entries = model.entries
        let groups = weeks(entries, calendar: .current)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TimeClockPageTitle(title: "Past entries",
                                   subtitle: entries.isEmpty ? "On this phone" : "\(entries.count == 1 ? "1 entry" : "\(entries.count) entries")\(TimeClockWords.dot)On this phone",
                                   identifier: "timeclock-entries")
                if let problem = model.actionError {
                    Text(problem).font(Theme.font(15)).foregroundStyle(Theme.destructive)
                        .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4).padding(.top, 12)
                }
                if entries.isEmpty {
                    PaperEmptyState(symbol: "clock", title: "No entries yet",
                                    message: "Clock in and your hours are listed here. You can also add hours you worked but didn\u{2019}t clock.",
                                    actionTitle: "Add missed punch") { sheet = .add }
                        .padding(.top, 24)
                }
                ForEach(groups) { week in
                    VStack(alignment: .leading, spacing: 0) {
                        TimeClockSectionLabel(title: TimeClockWords.weekRange(week.interval),
                                              trailing: "\(TimeClockMath.decimalHours(TimeClockMath.workedSeconds(week.entries, now: now)))h")
                        TimeClockCard {
                            ForEach(week.entries) { entry in
                                if entry.id != week.entries.first?.id { WellDivider(leading: 16) }
                                row(entry, now: now)
                            }
                        }
                    }
                    .padding(.top, 22)
                }
                if !entries.isEmpty {
                    Button { sheet = .add } label: { TimeClockPill(title: "Add missed punch") }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("timeclock-entries-add")
                        .padding(.top, 22)
                    TimeClockPhoneNote(text: "Kept on this phone. A week\u{2019}s total counts each entry in the week it began.")
                        .padding(.top, 16)
                }
            }
            .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 8).padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .timeClockSheets($sheet, model: model)
    }

    @ViewBuilder private func row(_ entry: TimeClockEntry, now: Date) -> some View {
        let missed = TimeClockMath.isMissedClockOut(entry, now: now)
        let pause = TimeClockMath.breakSeconds(entry, now: now)
        let parts: [String] = [
            missed ? "No clock-out" : TimeClockWords.span(entry),
            pause >= 60 ? "\(TimeClockMath.durationLabel(pause)) break" : "",
            entry.change.map { "Changed: \($0.reason.label.lowercased())" } ?? "",
        ].filter { !$0.isEmpty }
        let content = HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(TimeClockWords.longDay(entry.clockIn)).font(Theme.font(16, weight: .medium))
                Text(parts.joined(separator: TimeClockWords.dot)).font(Theme.font(14))
                    .foregroundStyle(missed ? Theme.warning : Theme.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(missed ? "Fix" : "\(TimeClockMath.decimalHours(TimeClockMath.workedSeconds(entry, now: now)))h")
                .font(Theme.font(16, weight: .medium))
                .foregroundStyle(missed ? Theme.brandText : Theme.foreground)
                .fixedSize()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        if entry.isOpen && !missed {
            // Still running: it is changed from the clock, not edited here.
            content
        } else {
            Button { sheet = entry.isOpen ? .fix(entry) : .edit(entry) } label: { content }
                .buttonStyle(RowPressStyle())
                .accessibilityHint(entry.isOpen ? "Fixes the missed clock-out" : "Edits this entry")
        }
    }
}

// MARK: - Timesheet

/// Paper 56C "Timesheet", for one person on their own phone: the person, two weeks of days, what
/// was worked, and the days to check. There is nobody to approve it here, so the approve bar is
/// not drawn; the ••• circle moves between pay periods.
struct TimeClockTimesheetView: View {
    @ObservedObject var model: TimeClockModel
    @EnvironmentObject private var session: SessionController
    @State private var sheet: TimeClockSheet?
    /// 0 ends with this week; -1 is the two weeks before.
    @State private var offset = 0

    var body: some View {
        ScrollView {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                page(now: context.date)
            }
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ThorbisToolbarItem(placement: .topBarTrailing) {
                ThorbisMenu(items: menuItems, accessibilityLabel: "More for timesheet") {
                    PaperCircleLabel(symbol: "ellipsis", size: 44, fill: Theme.card)
                }
                .accessibilityIdentifier("timeclock-timesheet-more")
            }
        }
        .timeClockSheets($sheet, model: model)
    }

    private var menuItems: [ThorbisMenuItem] {
        var items = [ThorbisMenuItem("Two weeks before", icon: "chevron.left") { offset -= 1 }]
        // The weeks ahead have no hours to show, so the item leaves rather than sitting disabled.
        if offset < 0 { items.append(ThorbisMenuItem("Two weeks after", icon: "chevron.right") { offset += 1 }) }
        items.append(ThorbisMenuItem("Add missed punch", icon: "plus", startsGroup: true) { sheet = .add })
        return items
    }

    @ViewBuilder private func page(now: Date) -> some View {
        let calendar = Calendar.current
        let second = TimeClockMath.weekInterval(containing: now, offsetBy: offset * 2, calendar: calendar)
        let first = TimeClockMath.weekInterval(containing: now, offsetBy: offset * 2 - 1, calendar: calendar)
        let weeks = [first, second].map { (week: $0, days: TimeClockMath.days(model.entries, in: $0, now: now, calendar: calendar)) }
        let totals = weeks.map { $0.days.reduce(0) { $0 + $1.seconds } }
        let total = totals.reduce(0, +)
        let over = totals.reduce(0) { $0 + TimeClockMath.overtimeSeconds(weekSeconds: $1) }
        let toCheck = weeks.reduce(0) { $0 + $1.days.filter(\.missedClockOut).count }
        let name = (session.user?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: 0) {
            // Paper 56C: the 44 initials circle, the name in 28 Bold over the period in 15 muted.
            HStack(alignment: .center, spacing: 12) {
                if !name.isEmpty { InitialsAvatar(name: name, size: 44) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(name.isEmpty ? "Timesheet" : name).font(Theme.heading()).tracking(-0.56)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("timeclock-timesheet")
                    Text("Timesheet\(TimeClockWords.dot)\(TimeClockWords.shortRange(from: first.start, to: second.end.addingTimeInterval(-1)))")
                        .font(Theme.font(15)).foregroundStyle(Theme.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 4)
            ViewThatFits(in: .horizontal) {
                PlaceTileRow { tileSet(total: total, over: over, toCheck: toCheck) }
                VStack(spacing: 8) { tileSet(total: total, over: over, toCheck: toCheck) }
            }
            .padding(.top, 16)
            ForEach(Array(weeks.enumerated()), id: \.offset) { index, item in
                let shown = item.days.filter { day in
                    !day.entries.isEmpty || model.timeOff.contains { TimeClockMath.timeOffCovers($0, day: day.date, calendar: calendar) }
                }
                let live = item.week.contains(now)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Week \(index + 1)\(TimeClockWords.dot)\(TimeClockWords.shortRange(from: item.week.start, to: item.week.end.addingTimeInterval(-1)))")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityAddTraits(.isHeader)
                        Text("\(TimeClockMath.decimalHours(totals[index])) h\(live ? " so far" : "")")
                    }
                    .font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    TimeClockCard {
                        if shown.isEmpty {
                            Text("No hours").font(Theme.font(14)).foregroundStyle(Theme.muted)
                                .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        }
                        ForEach(shown) { day in
                            if day.id != shown.first?.id { WellDivider(leading: 0) }
                            dayRow(day, now: now, calendar: calendar)
                        }
                    }
                }
                .padding(.top, index == 0 ? 16 : 14)
            }
            TimeClockPhoneNote(text: "This timesheet is kept on this phone. It isn\u{2019}t sent to the office or payroll, and nobody approves it here. Overtime is hours past 40 in a week, not a pay figure.")
                .padding(.top, 16)
        }
        .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 12).padding(.bottom, 24)
    }

    /// Paper 56C: So far, Overtime and To check on three tiles; To check turns warning when any.
    @ViewBuilder private func tileSet(total: TimeInterval, over: TimeInterval, toCheck: Int) -> some View {
        PlaceSummaryTile(label: offset == 0 ? "So far" : "Worked", value: "\(TimeClockMath.decimalHours(total)) h")
        PlaceSummaryTile(label: "Overtime", value: over > 0 ? "\(TimeClockMath.decimalHours(over)) h" : "0 h")
        PlaceSummaryTile(label: "To check", value: "\(toCheck)", warn: toCheck > 0)
    }

    /// Paper 56C: "Mon 13" in a 58pt column, the punches and break, the hours trailing. A day with
    /// no clock-out sits on the warning surface with its fix under it.
    @ViewBuilder private func dayRow(_ day: TimeClockMath.Day, now: Date, calendar: Calendar) -> some View {
        let label = "\(day.date.formatted(.dateTime.weekday(.abbreviated))) \(day.date.formatted(.dateTime.day()))"
        let off = model.timeOff.first { TimeClockMath.timeOffCovers($0, day: day.date, calendar: calendar) }
        let missed = day.entries.first { TimeClockMath.isMissedClockOut($0, now: now) }
        let hours = day.entries.isEmpty ? "\u{2014}" : "\(TimeClockMath.decimalHours(day.seconds)) h"
        let detail: String = {
            if day.entries.isEmpty {
                return off.map { "\($0.kind.label) time off\(TimeClockWords.dot)not sent" } ?? "No hours"
            }
            if day.isOpen, let first = day.firstIn { return "In since \(first.tradeTime)" }
            let pause = day.breakSeconds >= 60 ? "\(TimeClockMath.durationLabel(day.breakSeconds)) break" : ""
            return [TimeClockWords.shortSpan(day), pause].filter { !$0.isEmpty }.joined(separator: TimeClockWords.dot)
        }()
        let content = HStack(alignment: .center, spacing: 10) {
            Text(label).font(Theme.font(15, weight: .semibold))
                .frame(minWidth: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                if missed != nil {
                    Text("No clock-out").font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.warning)
                    Text("Fix missed clock-out").font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.brandText)
                } else {
                    HStack(alignment: .center, spacing: 6) {
                        if day.isOpen {
                            Circle().fill(Theme.success).frame(width: 8, height: 8).accessibilityHidden(true)
                        }
                        Text(detail).font(Theme.font(14)).foregroundStyle(Theme.muted)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(hours).font(Theme.font(15, weight: .semibold))
                .foregroundStyle(missed != nil ? Theme.warning : (day.entries.isEmpty ? Theme.muted : Theme.foreground))
                .fixedSize().frame(minWidth: 52, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: missed != nil ? 60 : 48, alignment: .leading)
        .background(missed != nil ? Theme.warningSurface : Color.clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        if let missed {
            Button { sheet = .fix(missed) } label: { content }
                .buttonStyle(PressStyle())
                .accessibilityHint("Fixes the missed clock-out")
                .accessibilityIdentifier("timeclock-timesheet-fix")
        } else if day.entries.count == 1, let only = day.entries.first, !only.isOpen {
            Button { sheet = .edit(only) } label: { content }
                .buttonStyle(RowPressStyle())
                .accessibilityHint("Edits this entry")
        } else {
            content
        }
    }
}

// MARK: - Time off

/// Requests the person wrote (Paper 27A). They are kept, not sent: the approve side (Paper 55A)
/// needs an office this phone can't reach, so every request reads "Not sent".
struct TimeClockTimeOffView: View {
    @ObservedObject var model: TimeClockModel
    @State private var sheet: TimeClockSheet?

    var body: some View {
        let requests = model.timeOff
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    TimeClockPageTitle(title: "Time off",
                                       subtitle: requests.isEmpty ? "On this phone" : "\(requests.count == 1 ? "1 request" : "\(requests.count) requests")\(TimeClockWords.dot)On this phone",
                                       identifier: "timeclock-timeoff")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { sheet = .timeOff(nil) } label: { CreamCircleLabel(symbol: "plus", ink: true) }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Ask for time off")
                        .accessibilityIdentifier("timeclock-timeoff-create")
                }
                if let problem = model.actionError {
                    Text(problem).font(Theme.font(15)).foregroundStyle(Theme.destructive)
                        .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4).padding(.top, 12)
                }
                if requests.isEmpty {
                    PaperEmptyState(symbol: "sun.max", title: "No time off written down",
                                    message: "Write the days you want off and keep them here. Requests can\u{2019}t be sent to the office from this phone yet.",
                                    actionTitle: "Ask for time off") { sheet = .timeOff(nil) }
                        .padding(.top, 24)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        TimeClockSectionLabel(title: "Requests")
                        TimeClockCard {
                            ForEach(requests) { request in
                                if request.id != requests.first?.id { WellDivider(leading: 16) }
                                row(request)
                            }
                        }
                    }
                    .padding(.top, 22)
                    TimeClockPhoneNote(text: "\(TimeClockTimeOff.statusLabel). Nobody has seen or approved these; tell the office yourself.")
                        .padding(.top, 16)
                }
            }
            .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 8).padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .timeClockSheets($sheet, model: model)
    }

    private func row(_ request: TimeClockTimeOff) -> some View {
        Button { sheet = .timeOff(request) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(TimeClockWords.timeOffRange(request)).font(Theme.font(16, weight: .medium))
                Text("\(request.kind.label)\(TimeClockWords.dot)\(TimeClockWords.timeOffLength(request))")
                    .font(Theme.font(14)).foregroundStyle(Theme.muted)
                Text(TimeClockTimeOff.statusLabel).font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.warning)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edits this request")
    }
}
