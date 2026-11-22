import SwiftUI

// Today as stop cards (owner request, 31 October 2026: "left and right swipable cards"). At the top
// of Today the day's stops are a horizontal pager of full-width cards: swipe left for the next stop,
// right for the one before. It opens on the stop under way, else the next booked one; finished stops
// sit to the left. The list of the day (Up next / Later today / Done) stays under it. A small circle
// on Today's view bar switches between Cards and List; technicians start on Cards, office and owners
// on List. design.thorbis.com: a panel at rest (radius 14, no shadow), a sliver of the next card with
// the edge faded, status as a word, one ink commit, system scroll physics only.

/// How Today shows its stops. Stored as a raw string on the phone; empty means "the role decides".
enum TodayLayoutMode: String, CaseIterable {
    case cards, list

    static let storageKey = "thorbis.today.layout"

    /// The stored choice, else the role default: technicians start on Cards, office and owners on List.
    static func resolve(stored: String, schedulesOwnDay: Bool) -> TodayLayoutMode {
        TodayLayoutMode(rawValue: stored) ?? (schedulesOwnDay ? .cards : .list)
    }

    var toggled: TodayLayoutMode { self == .cards ? .list : .cards }
}

/// The pager's order and where it opens. Pure, so it is unit-tested without the view.
enum TodayStopOrder {
    /// Finished stops first (by time), then the rest of the day by time; untimed stops last.
    /// Canceled visits are not stops. `status` is the status the person sees (a queued step wins).
    static func ordered(_ jobs: [Job], status: (Job) -> String) -> [Job] {
        let stops = jobs.filter { status($0) != "canceled" }
        func byTime(_ list: [Job]) -> [Job] {
            list.enumerated().sorted { lhs, rhs in
                let left = JobFiltering.date(lhs.element.scheduledFor) ?? .distantFuture
                let right = JobFiltering.date(rhs.element.scheduledFor) ?? .distantFuture
                return left == right ? lhs.offset < rhs.offset : left < right
            }.map(\.element)
        }
        return byTime(stops.filter { status($0) == "completed" }) + byTime(stops.filter { status($0) != "completed" })
    }

    /// The stop under way (en route, on site, working, paused), else the first booked one, else the
    /// first other open stop, else the last one (every stop is done). Nil when there are no stops.
    static func startIndex(_ stops: [Job], status: (Job) -> String) -> Int? {
        guard !stops.isEmpty else { return nil }
        if let active = stops.firstIndex(where: { ScheduleLead.activeStatuses.contains(status($0)) }) { return active }
        if let booked = stops.firstIndex(where: { ["scheduled", "dispatched"].contains(status($0)) }) { return booked }
        if let open = stops.firstIndex(where: { status($0) != "completed" }) { return open }
        return stops.count - 1
    }

    /// "Stop 2 of 6 · 10:30": the card's first line.
    static func position(index: Int, total: Int, time: String?) -> String {
        ["Stop \(index + 1) of \(total)", time].compactMap { $0 }.joined(separator: " · ")
    }

    /// The card's first line as drawn. Paper F1 names the stop the tech drives to next
    /// "Next stop · 10:30 a.m."; every other card in the pager keeps its place in the day.
    static func firstLine(index: Int, total: Int, time: String?, isNext: Bool) -> String {
        isNext ? ["Next stop", time].compactMap { $0 }.joined(separator: " · ") : position(index: index, total: total, time: time)
    }

    /// What VoiceOver reads for a card: "Stop 2 of 6, 412 Birchwood Ln, Dispatched, 10:30".
    static func spoken(index: Int, total: Int, place: String, status: String, time: String?) -> String {
        ["Stop \(index + 1) of \(total)", place, status, time].compactMap { $0 }.joined(separator: ", ")
    }

    /// Dots under the pager only while they can still be counted at a glance.
    static func showsDots(total: Int) -> Bool { total > 1 && total <= 8 }
}

/// The access facts that matter on arrival, in one line: "Gate 4821# · Dog: Rusty · Parking: Driveway".
/// The same facts and words as the job screen's "Before you go in" banner, minus the alarm code
/// (that one is for inside) and the site notes (they stay on the job). Nil when none is recorded.
enum TodayStopAccess {
    static func line(_ place: ServiceLocationRecord) -> String? {
        let facts = JobPropertyHistory.facts(place)
        // In the order they matter at the curb: the gate, the dog, where to park.
        let parts = ["Gate code", "Dog", "Parking"].compactMap { label -> String? in
            guard let fact = facts.first(where: { $0.label == label }) else { return nil }
            return switch label {
            case "Gate code": "Gate \(fact.value)"
            case "Dog": "Dog: \(fact.value)"
            default: "Parking: \(fact.value)"
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Each card's place (street, directions, a number to call) and access line, read for the card
/// showing and its neighbours and kept per job so the circles never pop in and out on a swipe.
/// A failed read keeps the job's last saved copy, so a card still shows the address offline.
@MainActor
final class StopCardPlaces: ObservableObject {
    @Published private(set) var places: [String: NextStopPlace] = [:]
    @Published private(set) var access: [String: String] = [:]
    private var loaded: Set<String> = []
    private var identity = ""

    func place(_ job: Job) -> NextStopPlace? { places[job.id] }

    /// - Parameter customerAddresses: each customer's own address (`Store.customerAddresses`), for a
    ///   job that records no site of its own (JobFallbackAddress).
    func load(_ jobs: [Job], api: APIClient, organizationID: String?, canView: Bool, identity: String,
              customerAddresses: [String: String] = [:]) async {
        if identity != self.identity { self.identity = identity; places = [:]; access = [:]; loaded = [] }
        guard canView, let organizationID else { return }
        for job in jobs where !loaded.contains(job.id) {
            guard !Task.isCancelled else { return }
            await load(job, api: api, organizationID: organizationID, identity: identity,
                       customerAddress: job.customerId.flatMap { customerAddresses[$0] })
        }
    }

    private func load(_ job: Job, api: APIClient, organizationID: String, identity: String, customerAddress: String?) async {
        guard let customerID = job.customerId else { loaded.insert(job.id); return }
        let cached = JobDetailCache.stop(job.id).flatMap {
            $0.organizationID == organizationID && $0.customerID == customerID && $0.locationID == job.locationId ? $0 : nil
        }
        if places[job.id] == nil, let cached { places[job.id] = cached }
        var next = cached ?? NextStopPlace(jobID: job.id, organizationID: organizationID, customerID: customerID, locationID: job.locationId)
        var reached = false
        var accessLine: String?
        if let records = try? await api.fieldLocations(customerID) {
            reached = true
            // The job's own service location, or with none recorded the customer's only address on file.
            next.setPlace(from: records, customerAddress: customerAddress)
            // Access facts only for the job's own site; the job screen's banner says the rest with its caveat.
            let record = job.locationId.flatMap { locationID in
                records.first { $0.id == locationID && $0.customerId == customerID && $0.organizationId == organizationID }
            }
            accessLine = record.flatMap(TodayStopAccess.line)
        }
        if let contacts = try? await api.fieldContacts(customerID) {
            reached = true
            let verified = contacts.filter { $0.organizationId == organizationID && $0.customerId == customerID }
            var account: CustomerRecord?
            if NextStopPlace.phone(contacts: verified, account: nil) == nil,
               let record = try? await api.fieldCustomer(customerID), record.organizationId == organizationID, record.id == customerID {
                account = record
            }
            next.phone = NextStopPlace.phone(contacts: verified, account: account)
        }
        guard identity == self.identity, !Task.isCancelled else { return }
        places[job.id] = next
        if let accessLine { access[job.id] = accessLine }
        if reached {
            loaded.insert(job.id)
            JobDetailCache.save(stop: next)
        }
    }
}

/// The pager: one card per stop, the current one at the page gutter, a 16pt sliver of the next at
/// the trailing edge (faded), paging by the system's view-aligned scroll. The pager starts 20pt in
/// from the screen edge, so the drawer's edge swipe (an 18pt strip) keeps working on Today.
struct TodayStopCards<Commit: View>: View {
    let stops: [Job]
    /// The card showing, by job id. Owned by Today, which loads that job's next step for the commit.
    @Binding var focus: String?
    var customer: (Job) -> String
    var street: (Job) -> String?
    var place: (Job) -> NextStopPlace?
    var access: (Job) -> String?
    var pendingStatus: (Job) -> String?
    var etaMinutes: (Job) -> Int?
    var etaMiles: (Job) -> Double? = { _ in nil }
    var onSiteSince: (Job) -> Date?
    var locationNotice: (Job) -> (() -> Void)?
    var canOpenCustomerView: Bool
    @ViewBuilder var commit: (Job) -> Commit
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var spoken: String?

    /// The pager's page gutter, the gap between cards and the next card's sliver (C-Today: a 24pt
    /// sliver of the next stop at the trailing edge, design.thorbis.com's 16-32).
    static var leading: CGFloat { 16 }
    static var spacing: CGFloat { 12 }
    static var sliver: CGFloat { 24 }

    private var index: Int { stops.firstIndex { $0.id == focus } ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: Self.spacing) {
                        ForEach(Array(stops.enumerated()), id: \.element.id) { offset, job in
                            card(job, index: offset)
                                .containerRelativeFrame(.horizontal)
                                .frame(maxHeight: .infinity, alignment: .top)
                                .id(job.id)
                                // Only the card showing is read; the adjustable card moves between stops.
                                .accessibilityHidden(job.id != stops[index].id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $focus)
                // The next card's sliver: the card is the pager's width less the gap and the sliver.
                .contentMargins(.trailing, Self.spacing + Self.sliver, for: .scrollContent)
                // Cards outside the pager's frame still draw (the sliver, the previous card's edge), but
                // touches start only inside it, clear of the drawer's edge strip.
                .scrollClipDisabled()
                .padding(.leading, Self.leading)
                // Paper F1: the card is flat on the canvas (no rim, no shadow), so the dots sit close.
                .mask(edgeFade)
                .accessibilityIdentifier("today-stop-cards")
                // The scroll view keeps its offset when the stops reorder (a refresh finishes one), so the
                // page showing could drift from `focus` (the card the commit and the dots are for). Line
                // the page up with `focus` on first show and whenever the order changes.
                .onAppear { align(proxy) }
                .onChange(of: stops.map(\.id)) { _, _ in align(proxy) }
            }
            indicator
                .padding(.horizontal, Self.leading)
                .padding(.top, -2)
        }
    }

    /// The pager shows its own cards and the next card's sliver; the previous card's edge, out in the
    /// gutter, stays hidden so the page starts clean.
    private var edgeFade: some View { Rectangle() }

    /// Page dots under the pager (the stop showing is a short ink pill) while there are eight stops or
    /// fewer, else "2 of 6" in tabular figures. VoiceOver reads the position on the card itself.
    @ViewBuilder private var indicator: some View {
        if stops.count > 1 {
            HStack(spacing: 6) {
                if TodayStopOrder.showsDots(total: stops.count) {
                    ForEach(stops.indices, id: \.self) { dot in
                        Capsule()
                            .fill(dot == index ? Theme.foreground : Theme.muted.opacity(0.4))
                            .frame(width: dot == index ? 18 : 6, height: 6)
                    }
                } else {
                    Text("\(index + 1) of \(stops.count)")
                        .font(Theme.font(13, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.easeOut(duration: 0.12), value: index)
            .accessibilityHidden(true)
            .accessibilityIdentifier("today-stop-cards-position")
        }
    }

    /// After this layout pass, so the scroll view already holds the new order.
    private func align(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            guard let focus, stops.contains(where: { $0.id == focus }) else { return }
            proxy.scrollTo(focus, anchor: .leading)
        }
    }

    private func move(by step: Int) {
        let next = min(max(index + step, 0), stops.count - 1)
        guard next != index else { return }
        let id = stops[next].id
        if reduceMotion { focus = id } else { withAnimation(.easeOut(duration: 0.12)) { focus = id } }
        spoken = id
    }

    /// The stop the tech drives to next: where the pager opens, while that visit is still only booked.
    private var nextStopID: String? {
        let status = { (job: Job) in pendingStatus(job) ?? job.status }
        guard let start = TodayStopOrder.startIndex(stops, status: status),
              ["scheduled", "dispatched"].contains(status(stops[start])) else { return nil }
        return stops[start].id
    }

    private func card(_ job: Job, index: Int) -> some View {
        TodayStopCard(job: job, index: index, total: stops.count, isNext: job.id == nextStopID, customer: customer(job), street: street(job),
                      place: place(job), access: access(job), pendingStatus: pendingStatus(job),
                      etaMinutes: etaMinutes(job), etaMiles: etaMiles(job), onSiteSince: onSiteSince(job), locationNotice: locationNotice(job),
                      canOpenCustomerView: canOpenCustomerView, spoken: $spoken, move: move) { commit(job) }
    }
}

/// One stop (Paper F1 "Today (field)", the Next stop card): "Stop 3 of 6 · 10:30 a.m." in brand
/// text (a status word beside it once the visit is under way), the street in bold, the problem and
/// who, then under a hairline the drive ("18 min drive · arrive 10:25 a.m.") and the access facts.
/// Call and Directions are two pills, the one commit sits under them. Tapping the card's body opens
/// the job (Customer view lives there). At accessibility sizes the pills stack and the street never
/// truncates.
private struct TodayStopCard<Commit: View>: View {
    let job: Job
    let index: Int
    let total: Int
    /// The stop the tech drives to next: its first line reads "Next stop · 10:30 a.m." (Paper F1).
    let isNext: Bool
    let customer: String
    let street: String?
    let place: NextStopPlace?
    let access: String?
    let pendingStatus: String?
    let etaMinutes: Int?
    var etaMiles: Double? = nil
    let onSiteSince: Date?
    let locationNotice: (() -> Void)?
    let canOpenCustomerView: Bool
    var spoken: AccessibilityFocusState<String?>.Binding
    let move: (Int) -> Void
    @ViewBuilder var commit: () -> Commit
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openURL) private var openURL

    private var headline: String { place?.firstLine ?? street ?? job.title }
    private var hasStreet: Bool { place?.firstLine != nil || street != nil }
    private var supporting: String { hasStreet ? "\(job.title) · \(customer)" : customer }
    /// Said under the street when it is the customer's only address on file, not the job's own site.
    private var caveat: String? { place?.caveat }
    private var status: String { pendingStatus ?? job.status }
    private var tone: StatusTone { StatusTone(jobStatus: status, hasTime: job.scheduledFor != nil) }
    private var time: String? { JobFiltering.date(job.scheduledFor)?.clockTime }
    /// "18 min · 6.2 mi" for VoiceOver (the Directions pill's value and the card's own label).
    private var drive: String? { MapStrip.drive(minutes: etaMinutes, miles: etaMiles) }
    /// A plain booked visit needs no status word (its time is in the first line); anything under way,
    /// done, waiting to sync or on site says where it stands.
    private var showsStatus: Bool { pendingStatus != nil || onSiteSince != nil || !["scheduled", "dispatched"].contains(status) }

    private func statusWord(now: Date) -> String {
        if pendingStatus != nil { return "\(status.statusLabel) · waiting to sync" }
        if let onSiteSince, status != "completed" { return JobOnSiteClock.line(arrived: onSiteSince, now: now) }
        return status.statusLabel
    }

    /// Paper F1: "18 min drive · arrive 10:25 a.m.", from the drive time and the clock.
    private func driveLine(minutes: Int, now: Date) -> String {
        let arrive = now.addingTimeInterval(TimeInterval(minutes * 60))
        return "\(minutes) min drive · arrive \(arrive.clockTime)"
    }

    private var spokenSummary: String {
        var text = TodayStopOrder.spoken(index: index, total: total, place: headline, status: statusWord(now: .now), time: time)
        if let caveat { text += ", \(caveat)" }
        if let drive { text += ", \(drive)" }
        if let access { text += ", \(access)" }
        return text
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: job) { summary }
                .buttonStyle(.plain)
                .jobContextMenu(job, customer: customer)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenSummary)
                .accessibilityHint("Opens the job. Swipe up or down for another stop.")
                // VoiceOver: the card is adjustable; swipe up for the next stop, down for the one before.
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: move(1)
                    case .decrement: move(-1)
                    @unknown default: break
                    }
                }
                .accessibilityFocused(spoken, equals: job.id)
                .accessibilityIdentifier("today-stop-card-\(job.id)")
            if let locationNotice {
                NextStopLocationNotice(dismiss: locationNotice).padding(.top, 12)
            }
            Spacer(minLength: 0)
            // Paper F1: Call and Directions side by side, the one commit under them.
            VStack(alignment: .leading, spacing: 10) {
                reach
                commit()
                    // The row keeps its height while a commit loads, so nothing jumps on a swipe.
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Paper v2: a flat card on the canvas, radius 20, no rim and no shadow.
        .background(Theme.card, in: shape)
        .clipShape(shape)
    }

    /// Call and Directions: two pills on the field fill, each shown only when there is a number or
    /// an address on file. Directions opens driving directions in Maps.
    @ViewBuilder private var reach: some View {
        let call = place?.call
        let directions = place?.directions
        if call != nil || directions != nil {
            let row = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                                   : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
            row {
                if let call {
                    Button { openURL(call) } label: { RimmedButtonLabel(title: "Call", symbol: "phone", height: 52, size: 17) }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Call \(customer)")
                        .accessibilityIdentifier("today-stop-call")
                }
                if let directions {
                    Button { openURL(directions) } label: { RimmedButtonLabel(title: "Directions", symbol: "mappin.and.ellipse", height: 52, size: 17) }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Directions to \(headline)")
                        .accessibilityValue(drive ?? "")
                        .accessibilityHint("Opens driving directions in Maps")
                        .accessibilityIdentifier("today-stop-directions")
                }
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                let meta = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
                meta {
                    Text(TodayStopOrder.firstLine(index: index, total: total, time: time, isNext: isNext))
                        .font(Theme.font(14, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(Theme.brandText)
                        .fixedSize(horizontal: false, vertical: true)
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
                    if showsStatus {
                        TimelineView(.everyMinute) { context in
                            StatusLabel(tone: tone, word: statusWord(now: context.date), pending: pendingStatus != nil, size: 13, dot: true)
                        }
                    }
                }
                // Paper F1: the street at 28 Bold, tracked -0.02em.
                Text(headline).font(Theme.heading()).tracking(-0.56)
                    .foregroundStyle(Theme.foreground)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let caveat {
                    Text(caveat).font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(supporting).font(Theme.font(16)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.leading)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if etaMinutes != nil || access != nil {
                VStack(alignment: .leading, spacing: 10) {
                    Rectangle().fill(Theme.hairline).frame(height: 1).padding(.bottom, 4)
                    if let etaMinutes {
                        TimelineView(.everyMinute) { context in
                            fact("clock", driveLine(minutes: etaMinutes, now: context.date), weight: .semibold, id: "today-stop-drive")
                        }
                    }
                    if let access {
                        fact("key", access, weight: .medium, id: "today-stop-access")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// One fact under the hairline: a 24pt glyph slot in the marker grey, then the words at 17.
    private func fact(_ symbol: String, _ text: String, weight: Font.Weight, id: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.muted)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text).font(Theme.font(17, weight: weight)).monospacedDigit()
                .foregroundStyle(Theme.foreground)
                .multilineTextAlignment(.leading)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(id)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Paper 18C: Cards / List as a small two-part segment at the trailing edge of the day's first group
/// label (the card track, the chosen part raised). One button: a tap switches to the other layout.
struct TodayLayoutSegment: View {
    let mode: TodayLayoutMode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                part("Cards", on: mode == .cards)
                part("List", on: mode == .list)
            }
            .padding(2)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(mode == .cards ? "Show as list" : "Show as cards")
        .accessibilityValue(mode == .cards ? "Cards" : "List")
        .accessibilityIdentifier("today-layout-toggle")
    }

    private func part(_ title: String, on: Bool) -> some View {
        Text(title).font(Theme.font(13, weight: on ? .semibold : .medium))
            .foregroundStyle(on ? Theme.foreground : Theme.subtle)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(minHeight: 36)
            .background {
                if on { RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.selectedSegment) }
            }
    }
}

/// The view bar's Cards / List circle: shows what a tap switches to. Shown only when the day has
/// no group label to carry `TodayLayoutSegment`.
struct TodayLayoutToggle: View {
    let mode: TodayLayoutMode
    let action: () -> Void

    var body: some View {
        Button(action: action) { CreamCircleLabel(symbol: mode == .cards ? "list.bullet" : "rectangle.stack", size: 44) }
            .buttonStyle(PressStyle())
            .accessibilityLabel(mode == .cards ? "Show as list" : "Show as cards")
            .accessibilityValue(mode == .cards ? "Cards" : "List")
            .accessibilityIdentifier("today-layout-toggle")
    }
}

#if DEBUG
/// `--paper-preview-today-cards` / `--paper-preview-today-list` force Today's layout for a capture
/// (until the toggle is tapped); `--paper-preview-today-card N` opens the pager on stop N (1-based).
enum TodayStopCardsPreview {
    @MainActor static var resetThisLaunch = false
    static var forced: TodayLayoutMode? {
        guard PaperPreview.enabled else { return nil }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--paper-preview-today-cards") { return .cards }
        if args.contains("--paper-preview-today-list") { return .list }
        return nil
    }
    static var startIndex: Int? {
        let args = ProcessInfo.processInfo.arguments
        guard PaperPreview.enabled, let at = args.firstIndex(of: "--paper-preview-today-card"), args.indices.contains(at + 1),
              let number = Int(args[at + 1]), number > 0 else { return nil }
        return number - 1
    }
}
#endif
