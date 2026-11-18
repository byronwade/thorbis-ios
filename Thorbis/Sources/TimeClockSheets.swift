import SwiftUI

/// Cancel on the left, the title, and an optional brand commit on the right (Paper 27A / 27B).
private struct TimeClockSheetHeader: View {
    let title: String
    var commit: String? = nil
    var commitIdentifier: String? = nil
    let onCancel: () -> Void
    var onCommit: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onCancel) {
                Text("Cancel").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    .padding(.horizontal, 16).frame(minHeight: 44)
                    .background(Theme.card, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            Text(title).font(Theme.font(17, weight: .semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            if let commit {
                Button(action: onCommit) {
                    Text(commit).font(Theme.font(16, weight: .semibold)).foregroundStyle(Color.white)
                        .padding(.horizontal, 18).frame(minHeight: 44)
                        .background(Theme.brand, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .modifier(OptionalIdentifier(identifier: commitIdentifier))
            } else {
                // Keeps the title centred when there is no commit up here (Paper 27B).
                Text("Cancel").font(Theme.font(16, weight: .medium)).padding(.horizontal, 16).hidden()
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 2)
    }
}

/// A 13pt label over a multi-line note (Paper 27A / 27B's note card).
private struct TimeClockNoteCard: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.font(13)).foregroundStyle(Theme.muted).accessibilityHidden(true)
            TextField("", text: $text, prompt: .placeholder(placeholder), axis: .vertical)
                .font(Theme.font(16)).foregroundStyle(Theme.foreground)
                .lineLimit(1...6)
                .accessibilityLabel(label)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

/// Paper 27B "Fix a missed clock-out", and the same sheet for editing an entry or adding a punch
/// that was missed. Every change carries a reason. Nothing is sent for approval: there is no
/// office behind this, so the commit is a plain Save and the footer says where it is kept.
struct TimeClockEntryEditor: View {
    enum Mode {
        case add
        case edit(TimeClockEntry)
        case fix(TimeClockEntry)
    }

    let mode: Mode
    @ObservedObject var model: TimeClockModel
    @Environment(\.dismiss) private var dismiss
    @State private var clockIn: Date
    @State private var clockOut: Date
    @State private var breakMinutes: Int
    @State private var reason: TimeClockEntry.Reason?
    @State private var note: String
    @State private var problem: String?
    @State private var reasonMissing = false
    @State private var confirmDelete = false
    @State private var picking: PlaceDatePick?
    /// The break length the entry opened with, so untouched breaks keep their real times.
    private let originalBreakMinutes: Int
    private let openedAt: Date

    init(mode: Mode, model: TimeClockModel, now: Date = Date(), calendar: Calendar = .current) {
        self.mode = mode
        self.model = model
        openedAt = now
        switch mode {
        case .add:
            // Yesterday's working day unless today's has already ended.
            let eight = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? now
            let start = eight.addingTimeInterval(TimeClockMath.assumedShift) <= now
                ? eight : (calendar.date(byAdding: .day, value: -1, to: eight) ?? eight)
            _clockIn = State(initialValue: start)
            _clockOut = State(initialValue: start.addingTimeInterval(TimeClockMath.assumedShift))
            _breakMinutes = State(initialValue: 0)
            originalBreakMinutes = 0
            _reason = State(initialValue: nil)
            _note = State(initialValue: "")
        case .edit(let entry):
            let minutes = Int((TimeClockMath.breakSeconds(entry, now: now) / 60).rounded())
            _clockIn = State(initialValue: entry.clockIn)
            _clockOut = State(initialValue: entry.clockOut ?? now)
            _breakMinutes = State(initialValue: minutes)
            originalBreakMinutes = minutes
            _reason = State(initialValue: entry.change?.reason)
            _note = State(initialValue: entry.change?.note ?? "")
        case .fix(let entry):
            let out = TimeClockMath.suggestedClockOut(entry, now: now)
            var closed = entry
            closed.clockOut = out
            closed.breaks = TimeClockMath.closingBreaks(entry.breaks, at: out)
            let minutes = Int((TimeClockMath.breakSeconds(closed, now: now) / 60).rounded())
            _clockIn = State(initialValue: entry.clockIn)
            _clockOut = State(initialValue: out)
            _breakMinutes = State(initialValue: minutes)
            originalBreakMinutes = minutes
            _reason = State(initialValue: nil)
            _note = State(initialValue: "")
        }
    }

    private var isFix: Bool { if case .fix = mode { true } else { false } }
    private var existing: TimeClockEntry? {
        switch mode {
        case .add: nil
        case .edit(let entry), .fix(let entry): entry
        }
    }

    private var title: String {
        switch mode {
        case .add: "Add missed punch"
        case .edit: "Edit entry"
        case .fix: "Fix clock-out"
        }
    }

    private var subtitle: String {
        switch mode {
        case .add: "Hours you worked but didn\u{2019}t clock"
        case .edit: "Change the times, then say why"
        case .fix: "You didn\u{2019}t clock out"
        }
    }

    private var breakOptions: [(value: Int, label: String)] {
        Array(Set([0, 15, 30, 45, 60, 90, breakMinutes])).sorted()
            .map { (value: $0, label: TimeClockMath.minutesLabel($0)) }
    }

    private var total: TimeInterval {
        max(0, clockOut.timeIntervalSince(clockIn) - TimeInterval(breakMinutes * 60))
    }

    var body: some View {
        VStack(spacing: 0) {
            TimeClockSheetHeader(title: title, onCancel: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TimeClockWords.longDay(clockIn)).font(Theme.font(22, weight: .bold)).tracking(-0.33)
                        Text(subtitle).font(Theme.font(15)).foregroundStyle(Theme.muted)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    punches.padding(.top, 16)
                    if isFix {
                        // Paper 27B suggests a time from the last job; the phone has no such record,
                        // so this says plainly where the time came from.
                        HStack(alignment: .top, spacing: 10) {
                            PaperIcon(.placeSpark, size: 18, color: Theme.ai).padding(.top, 1).accessibilityHidden(true)
                            Text(existing?.openBreak != nil
                                 ? "Suggested from when your last break began. Change it to when you stopped."
                                 : "Suggested as 8 hours after you clocked in. Change it to when you stopped.")
                                .font(Theme.font(14)).foregroundStyle(Theme.foreground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.aiSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.aiBorder, lineWidth: 1) }
                        .padding(.top, 12)
                        .accessibilityElement(children: .combine)
                    }
                    reasons.padding(.top, 20)
                    TimeClockNoteCard(label: "Note (optional)", placeholder: "Add a note", text: $note)
                        .padding(.top, 8)
                    if case .edit = mode {
                        Button { confirmDelete = true } label: {
                            Text("Delete entry").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.destructive)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("timeclock-entry-delete")
                        .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            VStack(spacing: 12) {
                if let problem {
                    FieldProblem(message: problem).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Kept on this phone. Nobody approves it and it isn\u{2019}t sent to payroll.")
                        .font(Theme.font(13)).foregroundStyle(Theme.subtleForeground)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
                Button { save() } label: { TimeClockPill(title: "Save", primary: true, height: 52) }
                    .buttonStyle(PressStyle())
                    .accessibilityIdentifier("timeclock-entry-save")
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 12)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background.ignoresSafeArea())
        .placeDatePicker($picking)
        .thorbisConfirm("Delete this entry?", message: "Its hours come off the week. This can\u{2019}t be undone.",
                        isPresented: $confirmDelete,
                        actions: [ThorbisConfirmAction("Delete entry", role: .destructive) { delete() }])
    }

    /// Paper 27B's card: Clock in, Clock out (with "Missing" while fixing), the break, the day total.
    private var punches: some View {
        TimeClockCard {
            if isFix {
                PlaceSheetValueRow(label: "Clock in", value: clockIn.tradeTime)
            } else {
                timeRow("Clock in", text: clockIn.tradeTime, identifier: "timeclock-entry-clock-in") {
                    picking = PlaceDatePick(id: "in", title: "Clock in", date: clockIn, includesTime: true, upper: openedAt) { clockIn = $0 }
                }
            }
            WellDivider(leading: 0)
            timeRow("Clock out", text: TimeClockWords.punch(clockOut, on: clockIn), missing: isFix, identifier: "timeclock-entry-clock-out") {
                picking = PlaceDatePick(id: "out", title: "Clock out", date: clockOut, includesTime: true,
                                        lower: clockIn, upper: max(openedAt, clockIn)) { clockOut = $0 }
            }
            WellDivider(leading: 0)
            ThorbisSelect(options: breakOptions, selection: $breakMinutes, label: "Break", menuTitle: "Unpaid break")
                .padding(.horizontal, 16).frame(minHeight: 56)
            WellDivider(leading: 0)
            PlaceSheetValueRow(label: "Day total", value: TimeClockMath.durationLabel(total), strong: true)
        }
        .font(Theme.font(16)).tint(Theme.brand)
        .onChange(of: clockIn) { _, start in
            if clockOut < start { clockOut = min(start.addingTimeInterval(TimeClockMath.assumedShift), max(openedAt, start)) }
        }
    }

    /// Paper 27B's Clock out row: the label, "Missing" while fixing, then the time in its brand box.
    private func timeRow(_ label: String, text: String, missing: Bool = false, identifier: String,
                         action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(label).font(Theme.font(16)).foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if missing {
                Text("Missing").font(Theme.font(12, weight: .semibold)).foregroundStyle(Theme.destructive)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Theme.destructiveSurface, in: Capsule())
            }
            PlaceTimeBox(text: text, label: label, identifier: identifier, action: action)
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    }

    /// Paper 27B: Forgot, Phone died, Other; the chosen one on the brand surface with a brand rim.
    private var reasons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reason").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                .padding(.horizontal, 4).accessibilityAddTraits(.isHeader)
            FlowRow(spacing: 8, lineSpacing: 8) {
                ForEach(TimeClockEntry.Reason.allCases, id: \.self) { choice in
                    let chosen = reason == choice
                    Button { reason = choice; reasonMissing = false } label: {
                        Text(choice.label).font(Theme.font(15, weight: chosen ? .semibold : .medium))
                            .foregroundStyle(chosen ? Theme.brandText : Theme.foreground)
                            .padding(.horizontal, 14).frame(minHeight: 40)
                            .background(chosen ? Theme.brandSurface : Theme.card, in: Capsule())
                            .overlay { if chosen { Capsule().strokeBorder(Theme.brand, lineWidth: 1.5) } }
                            .contentShape(Rectangle().inset(by: -2))
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
                    .accessibilityIdentifier("timeclock-reason-\(choice.rawValue)")
                }
            }
            if reasonMissing { FieldProblem(message: "Choose a reason to save.").padding(.horizontal, 4) }
        }
    }

    private func save() {
        // Never pre-disabled: pressed without a reason, it says so under the chips.
        guard let reason else { reasonMissing = true; return }
        let now = Date()
        let typed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            var entry: TimeClockEntry
            if case .fix(let open) = mode {
                entry = try TimeClockMath.fixingClockOut(open, at: clockOut, reason: reason, note: typed, now: now)
            } else {
                entry = existing ?? TimeClockEntry(clockIn: clockIn)
                entry.clockIn = clockIn
                entry.clockOut = clockOut
                entry.breaks = TimeClockMath.closingBreaks(entry.breaks, at: clockOut)
                entry.change = TimeClockEntry.Change(reason: reason, note: typed.isEmpty ? nil : typed, changedAt: now)
            }
            if breakMinutes != originalBreakMinutes {
                entry = try TimeClockMath.settingBreak(minutes: breakMinutes, on: entry, now: now)
            }
            try model.attempt { try $0.save(entry, now: now) }
            dismiss()
        } catch {
            problem = error.localizedDescription
        }
    }

    private func delete() {
        guard let existing else { return }
        do {
            try model.attempt { try $0.removeEntry(existing.id) }
            dismiss()
        } catch {
            problem = error.localizedDescription
        }
    }
}

/// Paper 27A "Ask for time off": the days, all day or not, the kind, a note. The request is kept
/// on this phone and reads "Not sent": Paper's Send request, the jobs that need covering and the
/// paid-time-off balance all need the office, which this phone can't reach.
struct TimeClockTimeOffEditor: View {
    let request: TimeClockTimeOff?
    @ObservedObject var model: TimeClockModel
    @Environment(\.dismiss) private var dismiss
    @State private var from: Date
    @State private var to: Date
    @State private var allDay: Bool
    @State private var kind: TimeClockTimeOff.Kind
    @State private var note: String
    @State private var problem: String?
    @State private var confirmDelete = false
    @State private var picking: PlaceDatePick?

    init(request: TimeClockTimeOff?, model: TimeClockModel, now: Date = Date(), calendar: Calendar = .current) {
        self.request = request
        self.model = model
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let morning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        _from = State(initialValue: request?.from ?? morning)
        _to = State(initialValue: request?.to ?? morning)
        _allDay = State(initialValue: request?.allDay ?? true)
        _kind = State(initialValue: request?.kind ?? .vacation)
        _note = State(initialValue: request?.note ?? "")
    }

    private var draft: TimeClockTimeOff {
        let typed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return TimeClockTimeOff(id: request?.id ?? UUID().uuidString, from: from, to: to, allDay: allDay, kind: kind,
                                note: typed.isEmpty ? nil : typed, createdAt: request?.createdAt ?? Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            TimeClockSheetHeader(title: "Time off", commit: "Save", commitIdentifier: "timeclock-timeoff-save",
                                 onCancel: { dismiss() }, onCommit: { save() })
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let problem { FieldProblem(message: problem).padding(.horizontal, 4) }
                    TimeClockCard {
                        HStack(alignment: .top, spacing: 0) {
                            dayCell("From", date: from, identifier: "timeclock-timeoff-from") {
                                picking = PlaceDatePick(id: "from", title: "From", date: from, includesTime: !allDay) { from = $0 }
                            }
                            Rectangle().fill(Theme.border).frame(width: 1).accessibilityHidden(true)
                            dayCell("To", date: to, identifier: "timeclock-timeoff-to") {
                                picking = PlaceDatePick(id: "to", title: "To", date: to, includesTime: !allDay, lower: from) { to = $0 }
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        WellDivider(leading: 0)
                        ThorbisSheetToggleRow(label: "All day", isOn: $allDay).frame(minHeight: 56)
                    }
                    PlaceSegments(options: TimeClockTimeOff.Kind.allCases.map { (value: $0, label: $0.label) }, selection: $kind)
                    TimeClockNoteCard(label: "Note (optional)", placeholder: "Anything the office should know", text: $note)
                    // Where Paper shows the paid-time-off balance: what this request covers, and
                    // that it has not gone anywhere. The phone has no balance to draw.
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("This request").font(Theme.font(16)).frame(maxWidth: .infinity, alignment: .leading)
                            Text(TimeClockWords.timeOffLength(draft)).font(Theme.font(16, weight: .semibold))
                        }
                        Text(TimeClockTimeOff.statusLabel)
                            .font(Theme.font(14)).foregroundStyle(Theme.muted)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .padding(.top, 4)
                    TimeClockPhoneNote(text: "It can\u{2019}t be sent or approved here yet, so tell the office yourself. Your time-off balance and the jobs that need covering aren\u{2019}t shown because the phone doesn\u{2019}t have them.")
                    if request != nil {
                        Button { confirmDelete = true } label: {
                            Text("Delete request").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.destructive)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("timeclock-timeoff-delete")
                    }
                }
                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background.ignoresSafeArea())
        .onChange(of: from) { _, start in if to < start { to = start } }
        #if DEBUG
        .task {
            // Design preview: Paper P1's picker, opened over the request it answers.
            guard PaperPreview.enabled, PaperPreview.screen == "time-clock-date" else { return }
            try? await Task.sleep(for: .milliseconds(700))
            picking = PlaceDatePick(id: "from", title: "From", date: from, includesTime: true) { from = $0 }
        }
        #endif
        .placeDatePicker($picking)
        .thorbisConfirm("Delete this request?", message: "It was never sent, so nobody else is told.",
                        isPresented: $confirmDelete,
                        actions: [ThorbisConfirmAction("Delete request", role: .destructive) { delete() }])
    }

    /// Paper 27A: "From" over "Mon, Aug 10" (13 muted over 17 Medium), half the card wide.
    private func dayCell(_ label: String, date: Date, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(Theme.font(13)).foregroundStyle(Theme.muted)
                Text(allDay ? TimeClockWords.longDay(date) : "\(TimeClockWords.longDay(date)), \(date.tradeTime)")
                    .font(Theme.font(17, weight: .medium)).foregroundStyle(Theme.foreground)
                    .multilineTextAlignment(.leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityHint("Changes the day")
        .accessibilityIdentifier(identifier)
    }

    private func save() {
        do {
            let saved = draft
            try model.attempt { try $0.save(saved) }
            dismiss()
        } catch {
            problem = error.localizedDescription
        }
    }

    private func delete() {
        guard let request else { return }
        do {
            try model.attempt { try $0.removeTimeOff(request.id) }
            dismiss()
        } catch {
            problem = error.localizedDescription
        }
    }
}
