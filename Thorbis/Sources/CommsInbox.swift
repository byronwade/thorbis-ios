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
                    PaperCircleButton(symbol: "checkmark.circle", label: model.readCursor == nil ? "Mark all notices read" : "Continue marking read",
                                      fill: Theme.card, bordered: true) { Task { await model.markNoticesRead(api: api) } }
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                ThorbisMenu(items: access.sections.map { item in
                    ThorbisMenuItem(item.menuTitle, icon: item.symbol, isSelected: item == section) { section = item }
                }, accessibilityLabel: "\(section.title), switch what the Inbox shows") {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(section.title).font(Theme.font(34, weight: .medium)).tracking(-0.8)
                            .foregroundStyle(Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "chevron.down").font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("inbox-section-menu")
                .accessibilityAddTraits(.isHeader)
                // The Inbox is a beta on the web too: a quiet word, not a badge.
                Text("Beta").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                    .accessibilityLabel("Beta")
                Spacer(minLength: 0)
            }
            let folders = CommsInboxScope.folders(section)
            if folders.count > 1 {
                ThorbisMenu(items: folders.map { item in
                    ThorbisMenuItem(item.title, icon: item.symbol, isSelected: item == folder) { folder = item }
                }, accessibilityLabel: "Folder, \(folder.title)") {
                    // The folder's icon keeps "Inbox" here from reading as a second title.
                    HStack(spacing: 6) {
                        Image(systemName: folder.symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                            .accessibilityHidden(true)
                        Text(folder.title).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.subtle)
                        Image(systemName: "chevron.down").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("inbox-folder-menu")
            } else {
                Text(subtitle).font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 32, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.gutter).padding(.bottom, 8)
    }

    private var subtitle: String {
        section == .notices ? "Booked, changed and assigned jobs" : section.title
    }

    @ViewBuilder private var composeButton: some View {
        let label = PaperCircleLabel(symbol: "square.and.pencil", size: 36, fill: Theme.card, bordered: true)
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
        ListViewBar(options: CommsInboxScope.filters(section).map(\.rawValue), selection: $filter)
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

    @ViewBuilder private func rows(_ list: [CommsInboxItem]) -> some View {
        let displayCalendar = calendarWithTimeZone
        ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
            let raw = item.at(in: section)
            let heading = InboxNoticeDay.header(raw, after: index > 0 ? list[index - 1].at(in: section) : nil,
                                                hasPrevious: index > 0, calendar: displayCalendar, locale: locale)
            if let heading {
                ListGroupLabel(title: dayLabel(heading, raw: raw, calendar: displayCalendar, item: item), first: index == 0)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("inbox-day-heading")
            }
            switch item {
            case .calls(let thread): callRow(thread)
            case .local(let thread): localRow(thread)
            case .notice(let notice): noticeRow(notice)
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
            Button { open = .local(thread.id) } label: { CommsLocalRow(thread: thread) }
                .buttonStyle(RowPressStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel([thread.contactName, thread.channel == .email ? "Email" : "Text", thread.line,
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
                InboxRoomRow(title: notice.title, detail: notice.meta, time: timeLabel(notice.at), unread: !notice.read)
            }
            .buttonStyle(RowPressStyle())
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
        let name = section == .all ? "the Inbox" : section.title
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
                    ListRoomEmpty(title: "No texts.", message: "Start a text from a customer or with the pencil above. Drafts stay on this device.",
                                  actionTitle: "New text") { composing = .text }
                case .email:
                    ListRoomEmpty(title: "No email waiting.", message: "New mail lands here when an email account is connected.",
                                  actionTitle: "New email") { composing = .email }
                case .notices:
                    ListRoomEmpty(title: "No notices yet.", message: "New assignments and job changes land here.")
                case .all:
                    ListRoomEmpty(title: "Nothing waiting.", message: "Calls, texts, email and job notices land here as they come in.")
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



/// A caller's row (web rows.tsx CallRow): the avatar with its channel badge, the name (Medium
/// while unread), how many calls, the compact age and the unread dot; then what happened and
/// what was said. A missed call or voicemail nobody opened carries its word and dot.
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
        HStack(alignment: .top, spacing: 12) {
            if !stacked { CommsAvatar(initials: thread.initials, symbol: lead.kind == .voicemail ? "recordingtape" : "phone.fill") }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(thread.name).font(Theme.font(15, weight: unread ? .medium : .regular))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(stacked ? nil : 1)
                    if thread.calls.count > 1 {
                        Text("\(thread.calls.count)").font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
                    }
                    if starred {
                        Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(Theme.warning)
                    }
                    Spacer(minLength: 8)
                    Text(CommsAge.compact(lead.startedAt)).font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
                        .fixedSize()
                    Circle().fill(unread ? Theme.brand : .clear).frame(width: 7, height: 7)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                }
                let lineLayout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                         : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
                lineLayout {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: lead.kind.symbol).font(.system(size: 12, weight: .medium))
                            .foregroundStyle(lead.kind == .missed || lead.kind == .dropped ? Theme.destructive : Theme.muted)
                        Text(thread.line(in: section, alerted: alert != nil)).font(Theme.font(14))
                            .foregroundStyle(unread ? Theme.foreground : Theme.muted)
                            // The thread holds the rest; a long summary shouldn't fill the screen.
                            .lineLimit(stacked ? 4 : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: stacked ? nil : .infinity, alignment: .leading)
                    if let alert {
                        StatusLabel(tone: lead.kind == .voicemail ? .dispatched : .attention, word: alert, emphasis: .quiet)
                            .fixedSize()
                    }
                }
            }
        }
        .padding(.horizontal, ListRoom.gutter).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A caller's initials (or a person) on the fill, with the channel's glyph on a small badge.
struct CommsAvatar: View {
    let initials: String?
    let symbol: String
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle().fill(Theme.fill)
            if let initials {
                // The circle is a fixed size, so its letters can't follow Dynamic Type past it
                // or the channel badge covers them.
                Text(initials).font(Theme.font(size * 0.36, weight: .medium)).foregroundStyle(Theme.subtle)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .dynamicTypeSize(...DynamicTypeSize.large)
                    .offset(x: -1, y: -1)
            } else {
                Image(systemName: "person.fill").font(.system(size: size * 0.42)).foregroundStyle(Theme.muted)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: symbol).font(.system(size: size * 0.22, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .frame(width: size * 0.42, height: size * 0.42)
                .background(Theme.card, in: Circle())
                .overlay(Circle().stroke(Theme.background, lineWidth: 1.5))
                .offset(x: 5, y: 5)
        }
        .accessibilityHidden(true)
    }
}

/// A text or email conversation's row (web TextRow / EmailRow): the avatar with its channel
/// badge, the name (Medium while unread), the compact age and the dot; then the newest line, or
/// an email's subject. Ours and unsent says so ("Draft:", "Queued:").
struct CommsLocalRow: View {
    let thread: CommsLocalThread
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        HStack(alignment: .top, spacing: 12) {
            if !stacked { CommsAvatar(initials: thread.initials, symbol: thread.channel == .email ? "envelope.fill" : "bubble.left.fill") }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(thread.contactName).font(Theme.font(15, weight: thread.unread ? .medium : .regular))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(stacked ? nil : 1)
                    if thread.channel == .email && thread.messages.count > 1 {
                        Text("\(thread.messages.count)").font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
                    }
                    if thread.flags.starredAt != nil {
                        Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(Theme.warning)
                    }
                    Spacer(minLength: 8)
                    Text(CommsAge.compact(thread.latestAt)).font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
                        .fixedSize()
                    Circle().fill(thread.unread ? Theme.brand : .clear).frame(width: 7, height: 7)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                }
                Text(thread.line).font(Theme.font(14))
                    .foregroundStyle(thread.unread ? Theme.foreground : Theme.muted)
                    .lineLimit(stacked ? 4 : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, ListRoom.gutter).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .contentShape(Rectangle())
    }
}
