import SwiftUI

/// The Inbox's data: the call log and the job notices, each loaded on its own so one failing
/// never hides the other. Shared with an open thread, so a link made there shows in the list.
@MainActor
final class CommsInboxModel: ObservableObject {
    @Published private(set) var calls: [BookingCallRecord] = []
    @Published private(set) var callsCursor: String?
    @Published private(set) var callsLoading = false
    @Published private(set) var callsLoaded = false
    /// 403/404: the role or the workspace has no call log. Calls sections say so.
    @Published private(set) var callsDenied = false
    @Published private(set) var callsError: String?

    @Published private(set) var notices: [StaffNotice] = []
    @Published private(set) var noticesCursor: String?
    @Published private(set) var readCursor: String?
    @Published private(set) var unreadState: StaffUnreadState = .unknown
    @Published private(set) var noticesLoading = false
    @Published private(set) var noticesLoaded = false
    @Published private(set) var noticesError: String?

    /// Calls re-read with their transcript, by id.
    @Published private(set) var details: [String: BookingCallRecord] = [:]

    /// Missed calls and voicemails opened on this phone.
    @Published private(set) var seenIDs: Set<String>
    private let seen: CommsCallSeen

    init(seen: CommsCallSeen) {
        self.seen = seen
        seenIDs = seen.ids
    }

    func markSeen(_ thread: CommsCallThread) {
        seen.markSeen(thread.calls)
        if seen.ids != seenIDs { seenIDs = seen.ids }
    }

    var threads: [CommsCallThread] { CommsCallGrouping.threads(calls) }

    func thread(_ id: String) -> CommsCallThread? { threads.first { $0.id == id } }

    func refresh(api: APIClient, access: CommsInboxAccess) async {
        async let calls: Void = access.calls ? refreshCalls(api: api) : ()
        async let notices: Void = access.notices ? refreshNotices(api: api) : ()
        _ = await (calls, notices)
    }

    func refreshCalls(api: APIClient) async {
        guard !callsLoading else { return }
        callsLoading = true
        defer { callsLoading = false; callsLoaded = true }
        do {
            let page = try await api.inboxCallLog()
            calls = page.items
            callsCursor = page.nextCursor
            callsError = nil
            callsDenied = false
        } catch is CancellationError {
        } catch let problem as Problem where problem.status == 403 || problem.status == 404 {
            callsDenied = true
        } catch {
            callsError = error.isConnectivityFailure ? "Calls need a connection." : error.localizedDescription
        }
    }

    func loadOlderCalls(api: APIClient) async {
        guard !callsLoading, let cursor = callsCursor else { return }
        callsLoading = true
        defer { callsLoading = false }
        do {
            let page = try await api.inboxCallLog(cursor: cursor)
            guard page.nextCursor != cursor else {
                throw Problem(title: "Call pagination stopped", status: nil, detail: "The server repeated its cursor.")
            }
            let known = Set(calls.map(\.id))
            calls.append(contentsOf: page.items.filter { !known.contains($0.id) })
            callsCursor = page.nextCursor
            callsError = nil
        } catch is CancellationError {
        } catch { callsError = error.localizedDescription }
    }

    func refreshNotices(api: APIClient) async {
        guard !noticesLoading else { return }
        noticesLoading = true
        defer { noticesLoading = false; noticesLoaded = true }
        do {
            let page = try await api.staffNotices()
            notices = page.items
            noticesCursor = page.nextCursor
            unreadState = page.unreadState
            noticesError = nil
        } catch is CancellationError {
        } catch { noticesError = error.localizedDescription }
    }

    func loadOlderNotices(api: APIClient) async {
        guard !noticesLoading, let cursor = noticesCursor else { return }
        noticesLoading = true
        defer { noticesLoading = false }
        do {
            let page = try await api.staffNotices(cursor: cursor)
            guard page.nextCursor != cursor else {
                throw Problem(title: "Notice pagination stopped", status: nil, detail: "The server repeated its cursor.")
            }
            notices.append(contentsOf: page.items)
            noticesCursor = page.nextCursor
            unreadState = page.unreadState
            noticesError = nil
        } catch is CancellationError {
        } catch { noticesError = error.localizedDescription }
    }

    /// The notices API marks the whole feed read in batches (POST /v1/staff/notices/read).
    func markNoticesRead(api: APIClient) async {
        guard !noticesLoading else { return }
        noticesLoading = true
        defer { noticesLoading = false }
        do {
            let result = try await api.markStaffNoticesRead(cursor: readCursor)
            guard result.nextCursor != readCursor || result.nextCursor == nil else {
                throw Problem(title: "Notice acknowledgement stopped", status: nil, detail: "The server repeated its cursor.")
            }
            readCursor = result.nextCursor
            let page = try await api.staffNotices()
            notices = page.items
            noticesCursor = page.nextCursor
            unreadState = page.unreadState
            noticesError = nil
        } catch is CancellationError {
        } catch { noticesError = error.localizedDescription }
    }

    /// The call with its transcript (GET /v1/calls/{id}), read once per call.
    func detail(_ id: String, api: APIClient) async throws -> BookingCallRecord {
        if let known = details[id] { return known }
        let call = try await api.call(id)
        details[id] = call
        return call
    }

    func replace(_ call: BookingCallRecord) {
        details[call.id] = call
        if let index = calls.firstIndex(where: { $0.id == call.id }) { calls[index] = call }
    }

    var canMarkNoticesRead: Bool { unreadState == .present || readCursor != nil }
}

/// The Inbox (web apps/web features/inbox, phone layout; a beta there too): one list at a time.
/// Its title is a menu of sections (All, Calls, Voicemail, Texts, Email, Job notices), the line
/// under it a menu of folders, and the view bar the quick filters. A conversation opens on its
/// own screen.
struct CommsInboxView: View {
    let access: CommsInboxAccess
    @EnvironmentObject private var api: APIClient
    @StateObject private var model: CommsInboxModel
    @ObservedObject private var local: CommsLocalStore

    @State private var section: CommsInboxSection
    @State private var folder: CommsFolder = .inbox
    @State private var filter = CommsQuickFilter.all.rawValue
    /// The folder glyph grows with its 15pt label, capped so it never outweighs the word.
    @ScaledMetric(relativeTo: .subheadline) private var folderGlyph: CGFloat = 13
    @State private var open: CommsOpen?
    @State private var openingJob: String?
    @State private var composing: CommsComposeKind?
    @StateObject private var swipes = RowSwipeState()
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    init(access: CommsInboxAccess, actorID: String?, organizationID: String?) {
        self.access = access
        _model = StateObject(wrappedValue: CommsInboxModel(seen: CommsCallSeen(defaults: Self.persistsSeen ? .standard : nil,
                                                                                actorID: actorID, organizationID: organizationID)))
        _local = ObservedObject(wrappedValue: CommsLocalStore.shared(actorID: actorID, organizationID: organizationID))
        _section = State(initialValue: Self.previewSection(access) ?? access.defaultSection)
        _folder = State(initialValue: Self.previewFolder ?? .inbox)
    }

    private var quickFilter: CommsQuickFilter { CommsQuickFilter(rawValue: filter) ?? .all }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                content
            }
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if access.notices && section.showsNotices && folder == .inbox && model.canMarkNoticesRead {
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    // Paper v2: the 44pt card circle with a check.
                    Button { Task { await model.markNoticesRead(api: api) } } label: { CreamCircleLabel(symbol: "checkmark") }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel(model.readCursor == nil ? "Mark all notices read" : "Continue marking read")
                        .disabled(model.noticesLoading)
                }
            }
            if access.workspace {
                ThorbisToolbarItem(placement: .topBarTrailing) { composeButton }
            }
        }
        .refreshable { await model.refresh(api: api, access: access) }
        .onScrollPhaseChange { _, phase in if phase != .idle { swipes.close() } }
        .onChange(of: section) { _, next in
            filter = CommsQuickFilter.all.rawValue
            if !CommsInboxScope.folders(next).contains(folder) { folder = .inbox }
            swipes.close()
        }
        .thorbisDestination(item: $openingJob) { JobDetailView(jobId: $0).tabletReadable() }
        .thorbisDestination(item: $open) { target in
            switch target {
            case .calls(let id): CommsCallThreadView(threadID: id, model: model, local: local).tabletReadable()
            case .local(let id): CommsLocalThreadView(threadID: id, store: local).tabletReadable()
            }
        }
        .sheet(item: $composing) { kind in
            CommsComposeSheet(kind: kind, store: local) { id in
                composing = nil
                open = .local(id)
            }
        }
        .task {
            await model.refresh(api: api, access: access)
            if let target = Self.previewOpen(model.threads) { open = target }
        }
    }

    // MARK: Header

    /// Paper 49N: the 34 Bold title (a menu of sections), then one 15 muted line: the folder menu
    /// and how many conversations wait unread.
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            ThorbisMenu(items: access.sections.map { item in
                ThorbisMenuItem(item.menuTitle, icon: item.symbol, isSelected: item == section) { section = item }
            }, accessibilityLabel: "\(section.title), switch what Messages shows") {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(section.title).font(Theme.font(34, weight: .bold)).tracking(-0.85)
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Image(systemName: "chevron.down").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("inbox-section-menu")
            .accessibilityAddTraits(.isHeader)
            let folders = CommsInboxScope.folders(section)
            if folders.count > 1 {
                HStack(alignment: .center, spacing: 6) {
                    ThorbisMenu(items: folders.map { item in
                        ThorbisMenuItem(item.title, icon: item.symbol, isSelected: item == folder) { folder = item }
                    }, accessibilityLabel: "Folder, \(folder.title)") {
                        // The folder's icon keeps "Inbox" here from reading as a second title.
                        HStack(spacing: 5) {
                            Image(systemName: folder.symbol).font(.system(size: min(folderGlyph, 28), weight: .medium)).foregroundStyle(Theme.muted)
                                .accessibilityHidden(true)
                            Text(folder.title).font(Theme.font(15)).foregroundStyle(Theme.muted)
                            Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("inbox-folder-menu")
                    if let unread = unreadSummary {
                        Text("\u{00B7} \(unread)").font(Theme.font(15)).foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                Text(unreadSummary ?? subtitle).font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 32, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.gutter).padding(.bottom, 4)
    }

    private var subtitle: String {
        section == .notices ? "Booked, changed and assigned jobs" : section.title
    }

    /// "3 unread" across what this section and folder hold. While older pages are still on the
    /// server the count can only be a floor ("3+ unread"), and nothing unread is never claimed.
    private var unreadSummary: String? {
        guard !loading else { return nil }
        let all = CommsInboxScope.items(section: section, folder: folder, filter: .all,
                                        calls: access.calls && !model.callsDenied ? model.threads : [],
                                        local: access.workspace ? local.threads : [],
                                        notices: access.notices ? model.notices : [],
                                        callFlags: local.callFlags, seen: model.seenIDs)
        let count = all.filter { item in
            switch item {
            case .calls(let thread):
                CommsInboxScope.callUnread(thread, flags: local.callFlags[thread.id] ?? CommsThreadFlags(), seen: model.seenIDs)
            case .local(let thread): thread.unread
            case .notice(let notice): !notice.read
            }
        }.count
        let more = folder == .inbox && ((section.showsCalls && access.calls && model.callsCursor != nil)
            || (section.showsNotices && access.notices && model.noticesCursor != nil))
        if count > 0 { return more ? "\(count)+ unread" : "\(count) unread" }
        return more || all.isEmpty ? nil : "All caught up"
    }

    @ViewBuilder private var composeButton: some View {
        // Paper v2: the brand + circle starts a conversation.
        let label = CreamCircleLabel(symbol: "plus", ink: true)
        switch section {
        case .texts:
            Button { composing = .text } label: { label }.buttonStyle(PressStyle()).accessibilityLabel("New text")
        case .email:
            Button { composing = .email } label: { label }.buttonStyle(PressStyle()).accessibilityLabel("New email")
        default:
            ThorbisMenu(items: [ThorbisMenuItem("New text", icon: "bubble.left") { composing = .text },
                                ThorbisMenuItem("New email", icon: "envelope") { composing = .email }],
                        accessibilityLabel: "New message") { label }
                .accessibilityIdentifier("inbox-compose")
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        // Paper 49N's segmented tabs, here the quick filters this section has.
        PaperTabs(options: CommsInboxScope.filters(section).map(\.rawValue), selection: $filter)
            .padding(.top, 12)
        if section.showsCalls, let error = model.callsError {
            ErrorBanner(message: error) { await model.refreshCalls(api: api) }
        }
        if section.showsNotices, access.notices, let error = model.noticesError {
            ErrorBanner(message: error) { await model.refreshNotices(api: api) }
        }
        let list = items
        if loading && list.isEmpty { ListRoomSkeleton(count: 6, threeLines: false) }
        rows(list)
        more
        if !loading && list.isEmpty { empty }
        if section.showsLocal && access.workspace {
            Text(section == .email ? "No email provider is connected, so Send queues an email instead of sending it."
                                   : "Texts and email are kept on this device. Nothing sends until a provider is connected.")
                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.gutter).padding(.top, 20)
        }
    }

    private var loading: Bool {
        (section.showsCalls && access.calls && !model.callsLoaded) || (section.showsNotices && access.notices && !model.noticesLoaded)
    }

    private var items: [CommsInboxItem] {
        CommsInboxScope.items(section: section, folder: folder, filter: quickFilter,
                              calls: access.calls && !model.callsDenied ? model.threads : [],
                              local: access.workspace ? local.threads : [],
                              notices: access.notices ? model.notices : [],
                              callFlags: local.callFlags, seen: model.seenIDs)
    }

    /// Paper 49N: each day is a 13 Semibold label over one card of rows, a hairline between them.
    @ViewBuilder private func rows(_ list: [CommsInboxItem]) -> some View {
        let displayCalendar = calendarWithTimeZone
        let groups = CommsDayGrouping.groups(list, id: { $0.id }, at: { $0.at(in: section) }, calendar: displayCalendar, locale: locale) { heading, raw, item in
            dayLabel(heading, raw: raw, calendar: displayCalendar, item: item)
        }
        ForEach(groups) { group in
            CommsDayCard(title: group.title) {
                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { WellDivider(leading: 0) }
                    switch item {
                    case .calls(let thread): callRow(thread)
                    case .local(let thread): localRow(thread)
                    case .notice(let notice): noticeRow(notice)
                    }
                }
            }
        }
    }

    /// Archive (or back to the inbox) on the leading side, star on the trailing side; the thread's
    /// own menu has the same moves for VoiceOver and for anyone who doesn't swipe.
    private func swipeActions(_ id: String, name: String) -> (leading: [RowSwipeAction], trailing: [RowSwipeAction]) {
        let flags = local.flags(id)
        let move = flags.place == .inbox
            ? RowSwipeAction(id: "row-swipe-archive-\(id)", title: "Archive", symbol: "archivebox", tone: .ink, spokenName: "Archive \(name)") { local.archive(id) }
            : RowSwipeAction(id: "row-swipe-inbox-\(id)", title: "Move to Inbox", symbol: "tray", tone: .ink, spokenName: "Move \(name) to Inbox") { local.moveToInbox(id) }
        let star = RowSwipeAction(id: "row-swipe-star-\(id)", title: flags.starredAt == nil ? "Star" : "Unstar",
                                  symbol: flags.starredAt == nil ? "star" : "star.slash", spokenName: flags.starredAt == nil ? "Star \(name)" : "Unstar \(name)") {
            local.toggleStar(id)
        }
        return ([move], [star])
    }

    private func callRow(_ thread: CommsCallThread) -> some View {
        let flags = local.callFlags[thread.id] ?? CommsThreadFlags()
        let unread = CommsInboxScope.callUnread(thread, flags: flags, seen: model.seenIDs)
        let alert = thread.alert(seen: model.seenIDs, in: section)
        let lead = thread.lead(in: section)
        let swipe = swipeActions(thread.id, name: thread.name)
        return RowSwipeContainer(id: thread.id, leading: swipe.leading, trailing: swipe.trailing, state: swipes) {
            Button { open = .calls(thread.id) } label: {
                CommsThreadRow(thread: thread, section: section, unread: unread, alert: alert, starred: flags.starredAt != nil)
            }
            .buttonStyle(RowPressStyle())
            .background(Theme.card)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([thread.name, thread.calls.count > 1 ? "\(thread.calls.count) calls" : nil,
                                 alert, thread.line(in: section),
                                 lead.startedDate?.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)),
                                 flags.starredAt != nil ? "Starred" : nil,
                                 unread ? "Unread" : nil].compactMap { $0 }.joined(separator: ", "))
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the calls from this number")
            .accessibilityIdentifier("inbox-call-\(thread.id)")
            .rowSwipeAccessibility(swipe.leading + swipe.trailing)
        }
    }

    private func localRow(_ thread: CommsLocalThread) -> some View {
        let swipe = swipeActions(thread.id, name: thread.contactName)
        return RowSwipeContainer(id: thread.id, leading: swipe.leading, trailing: swipe.trailing, state: swipes) {
            Button { open = .local(thread.id) } label: { CommsLocalRow(thread: thread, folder: folder) }
                .buttonStyle(RowPressStyle())
                .background(Theme.card)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel([thread.contactName, thread.channel == .email ? "Email" : "Text", thread.line(in: folder),
                                     JobFiltering.date(thread.latestAt)?.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)),
                                     thread.flags.starredAt != nil ? "Starred" : nil,
                                     thread.unread ? "Unread" : nil].compactMap { $0 }.joined(separator: ", "))
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens the conversation")
                .accessibilityIdentifier("inbox-local-\(thread.id)")
                .rowSwipeAccessibility(swipe.leading + swipe.trailing)
        }
    }

    /// A notice opens the job it is about; swipe right offers the same. As in the notice feed,
    /// there is no Read/Unread swipe: the notices API only marks the whole feed read.
    private func noticeRow(_ notice: StaffNotice) -> some View {
        let open = RowSwipeAction(id: "row-swipe-open-\(notice.id)", title: "Open job",
                                  symbol: "arrow.up.right", tone: .ink, spokenName: "Open job") {
            openingJob = notice.jobId
        }
        return RowSwipeContainer(id: notice.id, leading: [open], state: swipes) {
            NavigationLink(value: PaperRoute.job(notice.jobId)) {
                CommsNoticeRow(notice: notice)
            }
            .buttonStyle(RowPressStyle())
            .background(Theme.card)
            .accessibilityElement(children: .combine)
            .accessibilityLabel([notice.title, notice.meta, spokenTime(notice.at), notice.read ? "Read" : "Unread"]
                .filter { !$0.isEmpty }.joined(separator: ", "))
            .accessibilityHint("Opens the job")
            .accessibilityIdentifier("inbox-row-\(notice.id)")
            .rowSwipeAccessibility([open])
        }
    }

    @ViewBuilder private var more: some View {
        if section.showsCalls && access.calls && model.callsCursor != nil && !model.callsDenied && folder == .inbox {
            loadMore("Load older calls", busy: model.callsLoading) { await model.loadOlderCalls(api: api) }
        }
        if section.showsNotices && access.notices && model.noticesCursor != nil && folder == .inbox {
            loadMore("Load older notices", busy: model.noticesLoading) { await model.loadOlderNotices(api: api) }
        }
    }

    private func loadMore(_ title: String, busy: Bool, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Text(busy ? "Loading\u{2026}" : title).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(busy)
        .padding(.top, 12)
    }

    /// Each empty view says why it is empty (web inbox ListEmpty, one reason each).
    @ViewBuilder private var empty: some View {
        let name = section == .all ? "Messages" : section.title
        if section == .calls || section == .voicemail, model.callsDenied {
            ListRoomEmpty(title: "Calls are for the office.",
                          message: "The call log needs access to every customer. A call linked to your job shows on the job.")
        } else if (section == .calls || section == .voicemail), model.callsError != nil {
            EmptyView()
        } else if quickFilter != .all {
            switch quickFilter {
            case .unread: ListRoomEmpty(title: "Nothing unread.", message: "All shows everything in \(folder.title).")
            case .needsReply: ListRoomEmpty(title: "Nothing needs a reply.", message: "You answered last everywhere in \(folder.title).")
            default: ListRoomEmpty(title: "Nothing starred.", message: "Star a conversation from its menu or by swiping left on it.")
            }
        } else {
            switch folder {
            case .drafts:
                ListRoomEmpty(title: "No drafts.", message: "A text or email you save without sending waits here, on this device.")
            case .sent:
                ListRoomEmpty(title: "Nothing sent yet.",
                              message: "What you send collects here. Until a text or email provider is connected, a message waits instead of going out, and says so.")
            case .archive:
                ListRoomEmpty(title: "Nothing archived.", message: "Archived conversations in \(name) wait here until you move them back.")
            case .bin:
                ListRoomEmpty(title: "The bin is empty.", message: "Binned conversations wait here. Nothing empties on its own.")
            case .inbox:
                switch section {
                case .calls:
                    ListRoomEmpty(title: "No calls yet.", message: "Calls to your business number land here with a recording and a summary.")
                case .voicemail:
                    ListRoomEmpty(title: "No voicemail.",
                                  message: "Thorbis records calls from when they\u{2019}re answered, so it doesn\u{2019}t take voicemail yet. Calls nobody answered show as missed calls.")
                case .texts:
                    ListRoomEmpty(title: "No texts.", message: "Start a text from a customer or with the + above. Drafts stay on this device.",
                                  actionTitle: "New text") { composing = .text }
                case .email:
                    ListRoomEmpty(title: "No email waiting.", message: "New mail lands here when an email account is connected.",
                                  actionTitle: "New email") { composing = .email }
                case .notices:
                    ListRoomEmpty(title: "No notices yet.", message: "New assignments and job changes land here.")
                case .all:
                    // A first visit is usually empty: point at the way in rather than only explain.
                    if access.workspace {
                        ListRoomEmpty(title: "Nothing waiting.",
                                      message: "Calls, texts, email and job notices land here. Text on a customer or job opens their conversation here too.",
                                      actionTitle: "New text") { composing = .text }
                    } else {
                        ListRoomEmpty(title: "Nothing waiting.", message: "Calls, texts, email and job notices land here as they come in.")
                    }
                }
            }
        }
    }

    // MARK: Time words

    private var calendarWithTimeZone: Calendar {
        var result = calendar
        result.timeZone = timeZone
        return result
    }

    private func timeLabel(_ raw: String?) -> String {
        guard let raw, let date = JobFiltering.date(raw) else { return "" }
        return date.tradeTime
    }

    private func spokenTime(_ raw: String?) -> String {
        guard let raw, let date = JobFiltering.date(raw) else { return "" }
        return date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }

    private func dayLabel(_ heading: String, raw: String?, calendar: Calendar, item: CommsInboxItem) -> String {
        if case .local = item, raw == nil { return "New" }
        guard let date = JobFiltering.date(raw) else { return heading }
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return heading
    }

    // MARK: Screenshot flags

    /// Screenshots keep nothing between runs; people keep their opened calls.
    private static var persistsSeen: Bool {
        #if DEBUG
        return !PaperPreview.enabled
        #else
        return true
        #endif
    }

    private static func previewArgument(_ name: String) -> String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard PaperPreview.enabled, let index = args.firstIndex(of: name), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
        #else
        return nil
        #endif
    }

    /// `--paper-preview-inbox-section calls|voicemail|texts|email|notices`.
    private static func previewSection(_ access: CommsInboxAccess) -> CommsInboxSection? {
        guard let raw = previewArgument("--paper-preview-inbox-section"), let section = CommsInboxSection(rawValue: raw),
              access.sections.contains(section) else { return nil }
        return section
    }

    /// `--paper-preview-inbox-folder drafts|sent|archive|bin`.
    private static var previewFolder: CommsFolder? { previewArgument("--paper-preview-inbox-folder").flatMap(CommsFolder.init(rawValue:)) }

    /// `--paper-preview-inbox-thread calls|text|email`: opens that sample conversation.
    private static func previewOpen(_ threads: [CommsCallThread]) -> CommsOpen? {
        switch previewArgument("--paper-preview-inbox-thread") {
        case "calls": threads.max { $0.calls.count < $1.calls.count }.map { .calls($0.id) }
        case "text": .local("t-preview-text")
        case "email": .local("t-preview-email")
        default: nil
        }
    }
}

/// What the list opened.
enum CommsOpen: Hashable {
    case calls(String)
    case local(String)
}



// MARK: - Day cards

/// One day's rows: its label and the rows it holds, in list order.
struct CommsDayGroup<Item>: Identifiable {
    let id: String
    let title: String
    var items: [Item]
}

/// Splits an already-ordered list into days (presentation only), naming each with `label`.
enum CommsDayGrouping {
    static func groups<Item>(_ list: [Item], id: (Item) -> String, at: (Item) -> String?, calendar: Calendar, locale: Locale,
                             label: (_ heading: String, _ raw: String?, _ item: Item) -> String) -> [CommsDayGroup<Item>] {
        var groups: [CommsDayGroup<Item>] = []
        for (index, item) in list.enumerated() {
            let raw = at(item)
            let heading = InboxNoticeDay.header(raw, after: index > 0 ? at(list[index - 1]) : nil,
                                                hasPrevious: index > 0, calendar: calendar, locale: locale)
            if let heading {
                groups.append(CommsDayGroup(id: "day-\(id(item))", title: label(heading, raw, item), items: [item]))
            } else if groups.isEmpty {
                groups.append(CommsDayGroup(id: "day-\(id(item))", title: "", items: [item]))
            } else {
                groups[groups.count - 1].items.append(item)
            }
        }
        return groups
    }
}

/// Paper v2 section: a 13 Semibold muted label 8 above one card (radius 20), 16 from the screen's
/// edges and 20 below the section before it.
struct CommsDayCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            if !title.isEmpty {
                Text(title).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("inbox-day-heading")
                    .padding(.horizontal, 4).padding(.bottom, 8)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: shape)
                .clipShape(shape)
        }
        .padding(.horizontal, 16).padding(.top, 20)
    }
}

// MARK: - Rows

/// How a row's 40pt circle reads (Paper 49N): unread in brand, a missed call nobody opened in
/// the warning hue, the rest quiet.
enum CommsAvatarTone {
    case quiet, unread, alert

    var fill: Color {
        switch self {
        case .quiet: Theme.fill
        case .unread: Theme.brandSurface
        case .alert: Theme.warningSurface
        }
    }

    var ink: Color {
        switch self {
        case .quiet: Theme.subtle
        case .unread: Theme.brandText
        case .alert: Theme.warning
        }
    }
}

/// Paper 49N's row frame: an 8pt lane for the unread dot, the 40pt circle, then the words; 14
/// above and below, on the card. At accessibility sizes the circle steps aside for the words.
struct CommsRowShell<Avatar: View, Content: View>: View {
    let unread: Bool
    @ViewBuilder var avatar: Avatar
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(unread ? Theme.brand : .clear).frame(width: 8, height: 8)
                .padding(.top, 16)
                .frame(width: 8)
                .accessibilityHidden(true)
            if !typeSize.isAccessibilitySize { avatar }
            VStack(alignment: .leading, spacing: 2) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 8).padding(.trailing, 14).padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        // No fill here: the row's button sits on `Theme.card` so its press tint shows over it.
        .contentShape(Rectangle())
    }
}

/// A row's first line: the name (Semibold while unread), how many, the star, and the time, in
/// brand while unread.
struct CommsRowTitle: View {
    let name: String
    let time: String
    let unread: Bool
    var count: Int? = nil
    var starred = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name).font(Theme.font(16, weight: unread ? .semibold : .medium))
                .foregroundStyle(Theme.foreground)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            if let count, count > 1 {
                Text("\(count)").font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
            }
            if starred {
                Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(Theme.warning)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            Text(time).font(Theme.font(13, weight: unread ? .semibold : .regular)).monospacedDigit()
                .foregroundStyle(unread ? Theme.brandText : Theme.muted)
                .fixedSize()
        }
    }
}

/// The time of day a row shows; the day is its card's label.
private func commsRowTime(_ raw: String?) -> String {
    JobFiltering.date(raw)?.tradeTime ?? ""
}

/// A caller's row (web rows.tsx CallRow, Paper 49N): the dot, the caller's circle, the name and
/// time; then what happened with its glyph (a missed call in red) and what was said. A missed call
/// or voicemail nobody opened carries its word under it.
struct CommsThreadRow: View {
    let thread: CommsCallThread
    let section: CommsInboxSection
    let unread: Bool
    let alert: String?
    var starred = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let lead = thread.lead(in: section)
        let missed = lead.kind == .missed || lead.kind == .dropped
        let tone: CommsAvatarTone = unread ? (alert != nil && lead.kind == .missed ? .alert : .unread) : .quiet
        CommsRowShell(unread: unread) {
            CommsAvatar(initials: thread.initials, symbol: lead.kind == .voicemail ? "recordingtape" : "phone.fill",
                        tone: tone, badge: false)
        } content: {
            CommsRowTitle(name: thread.name, time: commsRowTime(lead.startedAt), unread: unread,
                          count: thread.calls.count, starred: starred)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: lead.kind.symbol).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(missed ? Theme.destructive : Theme.muted)
                    .accessibilityHidden(true)
                Text(thread.line(in: section, alerted: alert != nil)).font(Theme.font(15))
                    .foregroundStyle(unread ? Theme.foreground : Theme.muted)
                    // The thread holds the rest; a long summary shouldn't fill the screen.
                    .lineLimit(stacked ? 4 : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let alert {
                StatusLabel(tone: lead.kind == .voicemail ? .dispatched : .attention, word: alert, emphasis: .quiet)
                    .fixedSize()
                    .padding(.top, 2)
            }
        }
    }
}

/// A job notice (Paper 77, and in Messages beside the conversations): the dot, a bell on brand
/// while unread, what happened with its time, then the job it is about.
struct CommsNoticeRow: View {
    let notice: StaffNotice
    /// Paper 77: how long ago ("12m", "1h", "yesterday") in place of the time of day, for a list
    /// with no day labels. Messages keeps the time of day under its day labels.
    var relativeTime = false
    @Environment(\.dynamicTypeSize) private var typeSize

    /// "now", "12m", "3h", "yesterday", "4d", then the date ("Jun 15"). Empty when there is no time.
    static func relative(_ raw: String?, now: Date = .now, calendar: Calendar = .current) -> String {
        guard let date = JobFiltering.date(raw) else { return "" }
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        if days <= 0 { return "\(Int(seconds / 3600))h" }
        if days == 1 { return "yesterday" }
        if days < 7 { return "\(days)d" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let unread = !notice.read
        let time = relativeTime ? Self.relative(notice.at) : commsRowTime(notice.at)
        CommsRowShell(unread: unread) {
            Image(systemName: "bell").font(.system(size: 15, weight: .medium))
                .foregroundStyle(unread ? Theme.brand : Theme.muted)
                .frame(width: 40, height: 40)
                .background(unread ? Theme.brandSurface : Theme.fill, in: Circle())
                .accessibilityHidden(true)
        } content: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(notice.title).font(Theme.font(16, weight: unread ? .semibold : .regular))
                    .foregroundStyle(unread ? Theme.foreground : Theme.muted)
                    .lineLimit(stacked ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(time).font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted).fixedSize()
            }
            if !notice.meta.isEmpty {
                Text(notice.meta).font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .lineLimit(stacked ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A person's initials (or a person glyph) in a circle. On a row it is 40pt and toned (Paper
/// 49N); a conversation's header keeps the channel's glyph on a small badge.
struct CommsAvatar: View {
    let initials: String?
    let symbol: String
    var size: CGFloat = 40
    var tone: CommsAvatarTone = .quiet
    var badge = true

    var body: some View {
        ZStack {
            Circle().fill(tone.fill)
            if let initials {
                // The circle is a fixed size, so its letters can't follow Dynamic Type past it
                // or the channel badge covers them.
                Text(initials).font(Theme.font(size > 44 ? 17 : 14, weight: .semibold)).foregroundStyle(tone.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .dynamicTypeSize(...DynamicTypeSize.large)
                    .offset(x: badge ? -1 : 0, y: badge ? -1 : 0)
            } else {
                Image(systemName: "person.fill").font(.system(size: size * 0.4)).foregroundStyle(tone.ink)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if badge {
                Image(systemName: symbol).font(.system(size: size * 0.22, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: size * 0.42, height: size * 0.42)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().stroke(Theme.background, lineWidth: 1.5))
                    .offset(x: 5, y: 5)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A text or email conversation's row (web TextRow / EmailRow, Paper 49N): the dot, the circle,
/// the name and time; then the channel's glyph and the newest line, or an email's subject. Ours
/// and unsent says so ("Draft:", "Queued:").
struct CommsLocalRow: View {
    let thread: CommsLocalThread
    var folder: CommsFolder = .inbox
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let email = thread.channel == .email
        CommsRowShell(unread: thread.unread) {
            CommsAvatar(initials: thread.initials, symbol: email ? "envelope.fill" : "bubble.left.fill",
                        tone: thread.unread ? .unread : .quiet, badge: false)
        } content: {
            CommsRowTitle(name: thread.contactName, time: commsRowTime(thread.latestAt), unread: thread.unread,
                          count: email ? thread.messages.count : nil, starred: thread.flags.starredAt != nil)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: email ? "envelope" : "bubble.left").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .accessibilityHidden(true)
                Text(thread.line(in: folder)).font(Theme.font(15))
                    .foregroundStyle(thread.unread ? Theme.foreground : Theme.muted)
                    .lineLimit(stacked ? 4 : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
