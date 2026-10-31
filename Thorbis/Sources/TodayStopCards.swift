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

    func load(_ jobs: [Job], api: APIClient, organizationID: String?, canView: Bool, identity: String) async {
        if identity != self.identity { self.identity = identity; places = [:]; access = [:]; loaded = [] }
        guard canView, let organizationID else { return }
        for job in jobs where !loaded.contains(job.id) {
            guard !Task.isCancelled else { return }
            await load(job, api: api, organizationID: organizationID, identity: identity)
        }
    }

    private func load(_ job: Job, api: APIClient, organizationID: String, identity: String) async {
        guard let customerID = job.customerId else { loaded.insert(job.id); return }
        let cached = JobDetailCache.stop(job.id).flatMap {
            $0.organizationID == organizationID && $0.customerID == customerID && $0.locationID == job.locationId ? $0 : nil
        }
        if places[job.id] == nil, let cached { places[job.id] = cached }
        var next = cached ?? NextStopPlace(jobID: job.id, organizationID: organizationID, customerID: customerID, locationID: job.locationId)
        var reached = false
        var accessLine: String?
        if let locationID = job.locationId, let records = try? await api.fieldLocations(customerID) {
            reached = true
            // The job's own service location only, for its own customer (JobLocationPolicy).
            let record = records.first { $0.id == locationID && $0.customerId == customerID && $0.organizationId == organizationID }
            next.address = record?.address
            next.coordinates = record?.coordinates
            accessLine = record.flatMap(TodayStopAccess.line)
        } else if job.locationId == nil {
            next.address = nil
            next.coordinates = nil
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
    var onSiteSince: (Job) -> Date?
    var locationNotice: (Job) -> (() -> Void)?
    var canOpenCustomerView: Bool
    @ViewBuilder var commit: (Job) -> Commit
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var spoken: String?

    /// The pager's page gutter (Today's own), the gap between cards and the next card's sliver.
    static var leading: CGFloat { Theme.gutter }
    static var spacing: CGFloat { 8 }
    static var sliver: CGFloat { 16 }

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
        }
    }

    /// "Fade the edge" (design.thorbis.com D-019): the slivers outside the card fade toward the screen.
    private var edgeFade: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            LinearGradient(stops: [
                .init(color: .black.opacity(0.35), location: 0),
                .init(color: .black, location: min(1, Self.leading / width)),
                .init(color: .black, location: max(0, 1 - Self.sliver / width)),
                .init(color: .black.opacity(0.35), location: 1)
            ], startPoint: .leading, endPoint: .trailing)
        }
    }

    /// "2 of 6" in tabular figures, with dots while there are eight stops or fewer. VoiceOver reads the
    /// position on the card itself, so the indicator is hidden from it.
    @ViewBuilder private var indicator: some View {
        if stops.count > 1 {
            HStack(spacing: 10) {
                Text("\(index + 1) of \(stops.count)")
                    .font(Theme.font(13, weight: .medium)).monospacedDigit()
                    .foregroundStyle(Theme.muted)
                if TodayStopOrder.showsDots(total: stops.count) {
                    HStack(spacing: 6) {
                        ForEach(stops.indices, id: \.self) { dot in
                            Circle()
                                .fill(dot == index ? Theme.foreground : Theme.muted.opacity(0.45))
                                .frame(width: 6, height: 6)
                        }
                    }
                }
            }
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

    private func card(_ job: Job, index: Int) -> some View {
        TodayStopCard(job: job, index: index, total: stops.count, customer: customer(job), street: street(job),
                      place: place(job), access: access(job), pendingStatus: pendingStatus(job),
                      etaMinutes: etaMinutes(job), onSiteSince: onSiteSince(job), locationNotice: locationNotice(job),
                      canOpenCustomerView: canOpenCustomerView, spoken: $spoken, move: move) { commit(job) }
    }
}

/// One stop: "Stop 2 of 6 · 10:30", the street, the problem and who, the status word with its mark,
/// the access facts, then the one ink commit and quiet circles (Directions, Call, Customer view).
/// Tapping the card's body opens the job. At accessibility sizes the card grows and the circles go
/// under the commit; the street never truncates.
private struct TodayStopCard<Commit: View>: View {
    let job: Job
    let index: Int
    let total: Int
    let customer: String
    let street: String?
    let place: NextStopPlace?
    let access: String?
    let pendingStatus: String?
    let etaMinutes: Int?
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
    private var status: String { pendingStatus ?? job.status }
    private var tone: StatusTone { StatusTone(jobStatus: status, hasTime: job.scheduledFor != nil) }
    private var time: String? { JobFiltering.date(job.scheduledFor)?.clockTime }

    private func statusWord(now: Date) -> String {
        if pendingStatus != nil { return "\(status.statusLabel) · waiting to sync" }
        if let onSiteSince, status != "completed" { return JobOnSiteClock.line(arrived: onSiteSince, now: now) }
        return status.statusLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: job) { summary }
                .buttonStyle(.plain)
                .jobContextMenu(job, customer: customer)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(TodayStopOrder.spoken(index: index, total: total, place: headline,
                                                          status: statusWord(now: .now), time: time))
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
            let actions = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                                       : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
            actions {
                commit()
                if hasCircles { HStack(spacing: 8) { circles } }
            }
            // The row keeps its height while a commit loads, so nothing jumps on a swipe.
            .frame(minHeight: 44, alignment: .leading)
            .padding(.top, 16)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // A panel at rest: tone does the work. No shadow, no rim, no side rail.
        .panelBackground(cornerRadius: Theme.cardRadius)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(TodayStopOrder.position(index: index, total: total, time: time))
                .font(Theme.font(13, weight: .medium)).monospacedDigit()
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text(headline).font(Theme.font(22, weight: .medium)).tracking(-0.2)
                .foregroundStyle(Theme.foreground)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            Text(supporting).font(Theme.font(15)).foregroundStyle(Theme.subtle)
                .multilineTextAlignment(.leading)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                                                      : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            layout {
                TimelineView(.everyMinute) { context in
                    StatusLabel(tone: tone, word: statusWord(now: context.date), pending: pendingStatus != nil)
                }
                if let etaMinutes {
                    Text("\(etaMinutes) min drive").font(Theme.font(13, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.top, 6)
            if let access {
                Text(access).font(Theme.font(14)).foregroundStyle(Theme.subtle)
                    .multilineTextAlignment(.leading)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .accessibilityIdentifier("today-stop-access")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var hasCircles: Bool { place?.directions != nil || place?.call != nil || canOpenCustomerView }

    @ViewBuilder private var circles: some View {
        if let directions = place?.directions {
            PaperCircleButton(symbol: "arrow.triangle.turn.up.right.diamond", label: "Directions to \(headline)",
                              size: 44, fill: Theme.fill) { openURL(directions) }
                .accessibilityHint("Opens driving directions in Maps")
                .accessibilityIdentifier("today-stop-directions")
        }
        if let call = place?.call {
            PaperCircleButton(symbol: "phone", label: "Call \(customer)", size: 44, fill: Theme.fill) { openURL(call) }
                .accessibilityIdentifier("today-stop-call")
        }
        if canOpenCustomerView {
            // The job's own Customer view (its protected handoff), opened from the job as a tech would.
            NavigationLink { JobDetailView(jobId: job.id, opensCustomerView: true).thorbisBackButton() } label: {
                PaperCircleLabel(symbol: "person.crop.rectangle", size: 44, fill: Theme.fill)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Customer view for \(customer)")
            .accessibilityHint("Opens the job and hands the phone to the customer")
            .accessibilityRemoveTraits(.isSelected)
            .accessibilityIdentifier("today-stop-customer-view")
        }
    }
}

/// The view bar's Cards / List circle: shows what a tap switches to.
struct TodayLayoutToggle: View {
    let mode: TodayLayoutMode
    let action: () -> Void

    var body: some View {
        PaperCircleButton(symbol: mode == .cards ? "list.bullet" : "rectangle.stack", label: mode == .cards ? "Show as list" : "Show as cards",
                          size: 36, fill: Theme.fill, action: action)
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
