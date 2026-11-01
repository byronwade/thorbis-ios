import SwiftUI

// How the business runs, the web onboarding's hours, time zone, tax and terms. They are
// organization facts (POST /v1/organization/facts) the server normalizes or refuses:
// - timezone:              an IANA name
// - business_hours:        JSON, mon..sun each ["HH:MM", "HH:MM"] or null
// - sales_tax_rate:        a percent, 0 to 30
// - default_payment_terms: due_on_receipt, net_15, net_30, net_45, net_60

enum OperatingFacts {
    static let keys = ["timezone", "business_hours", "sales_tax_rate", "default_payment_terms"]

    /// The server offers these once it knows them; an older server hides the step.
    static func offered(_ profile: OrganizationProfile?) -> Bool {
        guard let profile else { return false }
        let known = Set(profile.catalog.map(\.factKey))
        return keys.allSatisfy(known.contains)
    }
}

/// A week of opening hours, edited a day at a time.
struct SetupWeek: Equatable {
    struct Day: Equatable {
        var open: Bool
        var from: Int  // minutes after midnight
        var to: Int
    }

    static let days = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
    static let names = ["mon": "Mon", "tue": "Tue", "wed": "Wed", "thu": "Thu", "fri": "Fri", "sat": "Sat", "sun": "Sun"]

    var days: [String: Day]

    /// Monday to Friday, 8 to 5: what most shops type first.
    static let standard = SetupWeek(days: Dictionary(uniqueKeysWithValues: days.map {
        ($0, Day(open: !["sat", "sun"].contains($0), from: 8 * 60, to: 17 * 60))
    }))

    static func parse(_ raw: String?) -> SetupWeek? {
        guard let data = raw?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var week = SetupWeek.standard
        for day in days {
            if let span = object[day] as? [String], span.count == 2,
               let from = minutes(span[0]), let to = minutes(span[1]) {
                week.days[day] = Day(open: true, from: from, to: to)
            } else {
                week.days[day]?.open = false
            }
        }
        return week
    }

    /// The server's canonical form: all seven days in order, closed days null.
    var json: String {
        let parts = Self.days.map { day -> String in
            guard let span = days[day], span.open else { return "\"\(day)\":null" }
            return "\"\(day)\":[\"\(Self.clock(span.from))\",\"\(Self.clock(span.to))\"]"
        }
        return "{" + parts.joined(separator: ",") + "}"
    }

    /// What the server would refuse, said the way the owner sees it.
    var problem: String? {
        let open = Self.days.compactMap { day in days[day].flatMap { $0.open ? (day, $0) : nil } }
        if open.isEmpty { return "Open at least one day, or skip this for now." }
        if let bad = open.first(where: { $0.1.from >= $0.1.to }) {
            return "\(Self.names[bad.0] ?? bad.0) closes before it opens."
        }
        return nil
    }

    static func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    static func minutes(_ clock: String) -> Int? {
        let parts = clock.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return hour * 60 + minute
    }
}

enum SetupTimeZones {
    /// The phone's zone first, then the US zones; a saved zone elsewhere stays on the list.
    static func choices(current: String, device: String = TimeZone.current.identifier) -> [String] {
        let us = ["America/New_York", "America/Chicago", "America/Denver", "America/Phoenix",
                  "America/Los_Angeles", "America/Anchorage", "Pacific/Honolulu"]
        var list: [String] = []
        for zone in [device] + us + [current] where !zone.isEmpty && !list.contains(zone) { list.append(zone) }
        return list
    }

    static func label(_ identifier: String) -> String {
        TimeZone(identifier: identifier)?.localizedName(for: .generic, locale: .current) ?? identifier
    }
}

enum PaymentTermsChoice {
    static let all = ["due_on_receipt", "net_15", "net_30", "net_45", "net_60"]

    static func label(_ value: String) -> String {
        switch value {
        case "due_on_receipt": "Due on receipt"
        case "net_15": "Net 15 days"
        case "net_30": "Net 30 days"
        case "net_45": "Net 45 days"
        case "net_60": "Net 60 days"
        default: value
        }
    }
}

/// The four controls, shared by guided setup and Settings › Company › Hours, tax and terms.
struct OperatingFactsFields: View {
    @ObservedObject var model: CompanyDetailsModel
    @Binding var week: SetupWeek

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            choice("Time zone", key: "timezone",
                   options: SetupTimeZones.choices(current: model.drafts["timezone"] ?? ""),
                   label: SetupTimeZones.label)
            hours
            taxRate
            choice("Payment terms", key: "default_payment_terms", options: PaymentTermsChoice.all,
                   label: PaymentTermsChoice.label)
        }
    }

    private func title(_ text: String) -> some View {
        Text(text).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
    }

    private func choice(_ name: String, key: String, options: [String], label: @escaping (String) -> String) -> some View {
        let current = model.drafts[key] ?? ""
        return VStack(alignment: .leading, spacing: 6) {
            title(name)
            ThorbisMenu(items: options.map { option in
                ThorbisMenuItem(label(option), isSelected: option == current) {
                    model.drafts[key] = option
                    model.fieldErrors[key] = nil
                }
            }, title: name, accessibilityLabel: name) {
                HStack {
                    Text(current.isEmpty ? "Choose" : label(current)).font(Theme.font(16))
                        .foregroundStyle(current.isEmpty ? Theme.muted : Theme.foreground)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
            }
            if let error = model.fieldErrors[key] { InlineProblem(message: error).font(Theme.font(13)) }
        }
    }

    private var hours: some View {
        VStack(alignment: .leading, spacing: 6) {
            title("Business hours")
            VStack(spacing: 0) {
                ForEach(SetupWeek.days, id: \.self) { day in
                    dayRow(day)
                    if day != SetupWeek.days.last { Divider().overlay(Theme.border) }
                }
            }
            .padding(.horizontal, 14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border))
            if let error = model.fieldErrors["business_hours"] ?? week.problem {
                InlineProblem(message: error).font(Theme.font(13))
            }
        }
    }

    private func dayRow(_ day: String) -> some View {
        let name = SetupWeek.names[day] ?? day
        let open = Binding(get: { week.days[day]?.open ?? false },
                           set: { week.days[day]?.open = $0; model.fieldErrors["business_hours"] = nil })
        return HStack(spacing: 8) {
            Text(name).font(Theme.font(15, weight: .medium)).frame(width: 40, alignment: .leading)
            if open.wrappedValue {
                time(day, \.from, label: "\(name) opens")
                Text("–").foregroundStyle(Theme.muted).accessibilityHidden(true)
                time(day, \.to, label: "\(name) closes")
            } else {
                Text("Closed").font(Theme.font(15)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 4)
            Toggle("\(name) open", isOn: open).labelsHidden().tint(Theme.success)
        }
        .frame(minHeight: 48)
    }

    private func time(_ day: String, _ part: WritableKeyPath<SetupWeek.Day, Int>, label: String) -> some View {
        let binding = Binding<Date>(
            get: {
                let minutes = week.days[day]?[keyPath: part] ?? 0
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                week.days[day]?[keyPath: part] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                model.fieldErrors["business_hours"] = nil
            })
        return DatePicker(label, selection: binding, displayedComponents: .hourAndMinute)
            .labelsHidden().datePickerStyle(.compact)
            .accessibilityLabel(label)
    }

    private var taxRate: some View {
        VStack(alignment: .leading, spacing: 6) {
            title("Sales tax rate")
            HStack(spacing: 6) {
                TextField("8.25", text: Binding(get: { model.drafts["sales_tax_rate"] ?? "" },
                                                set: { model.drafts["sales_tax_rate"] = $0; model.fieldErrors["sales_tax_rate"] = nil }))
                    .keyboardType(.decimalPad)
                    .font(Theme.font(16))
                    .accessibilityLabel("Sales tax rate, percent")
                Text("%").font(Theme.font(16)).foregroundStyle(Theme.muted).accessibilityHidden(true)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(minHeight: 46)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius)
                .stroke(model.fieldErrors["sales_tax_rate"] == nil ? Theme.border : Theme.destructive, lineWidth: 1))
            if let error = model.fieldErrors["sales_tax_rate"] {
                InlineProblem(message: error).font(Theme.font(13))
            } else {
                Text("Leave it empty if you don't charge sales tax.").font(Theme.font(13)).foregroundStyle(Theme.muted)
            }
        }
    }
}

/// Settings › Company › Hours, tax and terms.
struct OperatingDetailsView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var outbox: FieldOutbox
    @StateObject private var model = CompanyDetailsModel()
    @State private var week = SetupWeek.standard
    @State private var savedWeek: SetupWeek?
    @State private var saved = 0
    @State private var error: String?

    private var canEdit: Bool { session.can("organization.settings.edit") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.profile != nil {
                    OperatingFactsFields(model: model, week: $week).disabled(!canEdit)
                    if !model.queued.isEmpty {
                        Label("Saved on this phone. It syncs when you're back online.", systemImage: "icloud.and.arrow.up")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    }
                    if let error { InlineProblem(message: error) }
                } else if let loadError = model.loadError {
                    InlineProblem(message: loadError)
                    Button("Try again") { Task { await load() } }
                        .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.brandText).frame(minHeight: 44)
                } else {
                    SkeletonRows(count: 5, leading: false, inset: 0)
                }
            }
            .padding(Theme.gutter)
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .navigationTitle("Hours, tax and terms")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit, model.profile != nil {
                ThorbisToolbarItem(placement: .confirmationAction, prominent: true) {
                    if model.saving { ProgressView() } else { Button("Save") { Task { await save() } } }
                }
            }
        }
        .sensoryFeedback(.success, trigger: saved)
        .task { await load() }
    }

    private func load() async {
        await model.load(api: api)
        if let parsed = SetupWeek.parse(model.profile?.value("business_hours")) { week = parsed; savedWeek = parsed }
        if (model.drafts["timezone"] ?? "").isEmpty { model.drafts["timezone"] = TimeZone.current.identifier }
    }

    private func save() async {
        error = nil
        if week != savedWeek {
            if let problem = week.problem { error = problem; return }
            model.drafts["business_hours"] = week.json
        }
        if await model.save(api: api, session: session, only: Set(OperatingFacts.keys), outbox: outbox) {
            savedWeek = week
            saved += 1
        } else {
            error = model.loadError ?? "Some details were not saved. Check the fields marked above."
        }
    }
}
