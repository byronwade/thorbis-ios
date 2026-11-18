import SwiftUI

extension PaperGlyph {
    /// Paper P1's month arrows (18pt, brand ink).
    static let placeMonthBack = PaperGlyph(box: 20, [.stroke("M12.5 4L6.5 10L12.5 16", 1.8)])
    static let placeMonthForward = PaperGlyph(box: 20, [.stroke("M7.5 4L13.5 10L7.5 16", 1.8)])
}

/// Paper P1's calendar card: "July 2026" in 17 Semibold with the two brand arrows, the weekday
/// letters in 12 Semibold, then 44 by 40 day cells. Today wears a brand ring, the chosen day the
/// brand fill, and days that can't be chosen sit back in the subtle ink.
struct PlaceCalendarCard: View {
    @Binding var date: Date
    var lower: Date? = nil
    var upper: Date? = nil
    var calendar: Calendar = .current
    @State private var month: Date

    init(date: Binding<Date>, lower: Date? = nil, upper: Date? = nil, calendar: Calendar = .current) {
        _date = date
        self.lower = lower
        self.upper = upper
        self.calendar = calendar
        _month = State(initialValue: calendar.dateInterval(of: .month, for: date.wrappedValue)?.start ?? date.wrappedValue)
    }

    private var weeks: [[Date?]] {
        guard let days = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let lead = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: lead)
        for day in days { cells.append(calendar.date(byAdding: .day, value: day - 1, to: month)) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    private var weekdays: [String] {
        let names = calendar.shortStandaloneWeekdaySymbols
        return (0..<7).map { names[($0 + calendar.firstWeekday - 1) % 7].uppercased() }
    }

    private func allowed(_ day: Date) -> Bool {
        if let lower, day < calendar.startOfDay(for: lower) { return false }
        if let upper, calendar.startOfDay(for: day) > upper { return false }
        return true
    }

    private func canStep(_ by: Int) -> Bool {
        guard let next = calendar.date(byAdding: .month, value: by, to: month) else { return false }
        if by < 0, let lower { return (calendar.dateInterval(of: .month, for: next)?.end ?? next) > lower }
        if by > 0, let upper { return next <= upper }
        return true
    }

    private func choose(_ day: Date) {
        // Keeps the time of day; only the day moves.
        let time = calendar.dateComponents([.hour, .minute], from: date)
        date = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day) ?? day
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Text(month.formatted(.dateTime.month(.wide).year())).font(Theme.font(17, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                arrow(.placeMonthBack, by: -1, label: "Month before")
                arrow(.placeMonthForward, by: 1, label: "Month after")
            }
            .padding(.leading, 8).padding(.trailing, 2).padding(.bottom, 2)
            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { name in
                    Text(name).font(.custom("Inter-Regular", fixedSize: 12).weight(.semibold))
                        .foregroundStyle(Theme.subtleForeground)
                        .frame(maxWidth: .infinity, minHeight: 20)
                }
            }
            .accessibilityHidden(true)
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day { cell(day) } else { Color.clear.frame(maxWidth: .infinity, minHeight: 40).accessibilityHidden(true) }
                    }
                }
            }
        }
        .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func arrow(_ glyph: PaperGlyph, by: Int, label: String) -> some View {
        let can = canStep(by)
        return Button {
            if let next = calendar.date(byAdding: .month, value: by, to: month) { month = next }
        } label: {
            PaperIcon(glyph, size: 18, color: can ? Theme.brandText : Theme.subtleForeground)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!can)
        .accessibilityLabel(label)
    }

    private func cell(_ day: Date) -> some View {
        let chosen = calendar.isDate(day, inSameDayAs: date)
        let today = calendar.isDateInToday(day)
        let can = allowed(day)
        return Button { choose(day) } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(Theme.font(16, weight: chosen || today ? .semibold : .regular))
                .foregroundStyle(chosen ? Color.white : (today ? Theme.brandText : (can ? Theme.foreground : Theme.subtleForeground)))
                .frame(width: 36, height: 36)
                .background { if chosen { Circle().fill(Theme.brand) } }
                .overlay { if today && !chosen { Circle().strokeBorder(Theme.brandText, lineWidth: 1.5) } }
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!can)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }
}

/// Paper P1 "Date and time picker" as a sheet: the grabber, Cancel, the title and the brand Done,
/// the calendar card, and a Time row when the answer carries a time of day.
struct PlaceDatePickerSheet: View {
    let title: String
    var includesTime = false
    var lower: Date? = nil
    var upper: Date? = nil
    let onDone: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    init(title: String, date: Date, includesTime: Bool = false, lower: Date? = nil, upper: Date? = nil,
         onDone: @escaping (Date) -> Void) {
        self.title = title
        self.includesTime = includesTime
        self.lower = lower
        self.upper = upper
        self.onDone = onDone
        _date = State(initialValue: date)
    }

    private var clamped: Date {
        var value = date
        if let lower, value < lower { value = lower }
        if let upper, value > upper { value = upper }
        return value
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Button { dismiss() } label: {
                        Text("Cancel").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                            .padding(.horizontal, 16).frame(minHeight: 44)
                            .background(Theme.card, in: Capsule()).contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle())
                    Text(title).font(Theme.font(17, weight: .semibold)).foregroundStyle(Theme.foreground)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .accessibilityAddTraits(.isHeader)
                    Button { onDone(clamped); dismiss() } label: {
                        Text("Done").font(Theme.font(16, weight: .semibold)).foregroundStyle(Color.white)
                            .padding(.horizontal, 18).frame(minHeight: 44)
                            .background(Theme.brand, in: Capsule()).contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityIdentifier("place-date-done")
                }
                PlaceCalendarCard(date: $date, lower: lower, upper: upper)
                if includesTime {
                    HStack(spacing: 8) {
                        Text("Time").font(Theme.font(16)).foregroundStyle(Theme.foreground)
                        Spacer(minLength: 8)
                        DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                            .labelsHidden().tint(Theme.brand)
                    }
                    .padding(.horizontal, 16).frame(minHeight: 56)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                }
            }
            .padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.background.ignoresSafeArea())
        .presentationDetents([.height(includesTime ? 520 : 450), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }
}

/// What a date answer is opened with; `id` keeps each field's sheet its own.
struct PlaceDatePick: Identifiable {
    let id: String
    let title: String
    let date: Date
    var includesTime = false
    var lower: Date? = nil
    var upper: Date? = nil
    let onDone: (Date) -> Void
}

extension View {
    /// Presents Paper P1's picker for whichever date answer was tapped.
    func placeDatePicker(_ pick: Binding<PlaceDatePick?>) -> some View {
        sheet(item: pick) { item in
            PlaceDatePickerSheet(title: item.title, date: item.date, includesTime: item.includesTime,
                                 lower: item.lower, upper: item.upper, onDone: item.onDone)
        }
    }
}
