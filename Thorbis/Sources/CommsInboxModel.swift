import Foundation
import SwiftUI

// The communications Inbox (web apps/web features/inbox): calls from the server's call log,
// grouped into one thread per caller like web's mergeServerCalls, beside the job notices the
// Inbox has always carried. Texts and email have no server yet, so their sections say so.

/// What the Inbox can show, chosen from its title menu (web's "Inbox ▾").
enum CommsInboxSection: String, CaseIterable, Identifiable {
    case all, calls, voicemail, texts, email, notices

    var id: String { rawValue }

    /// The word in the title menu and on the screen's title.
    var title: String {
        switch self {
        case .all: "Messages"
        case .calls: "Calls"
        case .voicemail: "Voicemail"
        case .texts: "Texts"
        case .email: "Email"
        case .notices: "Job notices"
        }
    }

    /// The menu's row word: "All" reads better there than the place's own name.
    var menuTitle: String { self == .all ? "All" : title }

    var symbol: String {
        switch self {
        case .all: "tray"
        case .calls: "phone"
        case .voicemail: "recordingtape"
        case .texts: "bubble.left"
        case .email: "envelope"
        case .notices: "bell"
        }
    }

    /// Sections whose rows are call threads.
    var showsCalls: Bool { [.all, .calls, .voicemail].contains(self) }
    var showsNotices: Bool { [.all, .notices].contains(self) }
    var showsLocal: Bool { [.all, .texts, .email].contains(self) }
}

/// Messages' one short filter (Paper 49N keeps the list itself one list): a row of chips under
/// the search field, one on at a time, All first. Each is a lens over the same scope the list has
/// always used: which section, which folder, which quick filter.
enum CommsInboxFilter: String, CaseIterable, Identifiable {
    case all, unread, calls, texts, email, drafts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .unread: "Unread"
        case .calls: "Calls"
        case .texts: "Texts"
        case .email: "Email"
        case .drafts: "Drafts"
        }
    }

    var section: CommsInboxSection {
        switch self {
        case .calls: .calls
        case .texts: .texts
        case .email: .email
        default: .all
        }
    }

    var folder: CommsFolder { self == .drafts ? .drafts : .inbox }
    var quick: CommsQuickFilter { self == .unread ? .unread : .all }

    /// The chips this person has: Calls needs the call log; texts, email and drafts live on this
    /// phone for anyone signed in to a workspace.
    static func available(_ access: CommsInboxAccess) -> [CommsInboxFilter] {
        var chips: [CommsInboxFilter] = [.all, .unread]
        if access.calls { chips.append(.calls) }
        if access.workspace { chips += [.texts, .email, .drafts] }
        return chips
    }
}

/// The rarer lenses the old filter menu offered, kept one tap behind the header's "…": two quick
/// filters and the folders a conversation is moved to. While one is on, no chip is lit and the
/// search field carries it as a removable chip.
enum CommsInboxMoreFilter: String, CaseIterable, Identifiable {
    case needsReply, starred, sent, archive, bin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .needsReply: "Needs reply"
        case .starred: "Starred"
        case .sent: "Sent"
        case .archive: "Archive"
        case .bin: "Bin"
        }
    }

    var symbol: String {
        switch self {
        case .needsReply: "arrowshape.turn.up.left"
        case .starred: "star"
        case .sent: CommsFolder.sent.symbol
        case .archive: CommsFolder.archive.symbol
        case .bin: CommsFolder.bin.symbol
        }
    }

    var folder: CommsFolder {
        switch self {
        case .sent: .sent
        case .archive: .archive
        case .bin: .bin
        default: .inbox
        }
    }

    var quick: CommsQuickFilter {
        switch self {
        case .needsReply: .needsReply
        case .starred: .starred
        default: .all
        }
    }

    var isFolder: Bool { folder != .inbox }

    /// Stars, archive and bin are kept on this phone for calls too; Sent is texts and email only.
    static func available(_ access: CommsInboxAccess) -> [CommsInboxMoreFilter] {
        guard access.workspace else { return [] }
        return allCases
    }
}

/// Who sees which part of the Inbox. Like the web beta, the Inbox itself is personal: anyone
/// signed in to a workspace has it, with texts and email kept on this device. Calls need
/// customer.view with call_recording (the server answers 403 otherwise); job notices need
/// job.view with job_booking_notices.
/// Texts and email in the Inbox are kept on this phone and do not send, so they stay out of the
/// app until the server can deliver them. The server switches them on with this feature key.
enum InboxMessaging {
    static let feature = "inbox_messaging"
    @MainActor static func on(_ session: SessionController) -> Bool {
        #if DEBUG
        // Design previews show the full Inbox; this flag shows what ships.
        if PaperPreview.enabled { return !ProcessInfo.processInfo.arguments.contains("--paper-preview-no-messaging") }
        #endif
        return session.isFeatureOn(feature)
    }
}

struct CommsInboxAccess: Equatable {
    let workspace: Bool
    let notices: Bool
    let calls: Bool

    @MainActor init(_ session: SessionController) {
        self.init(workspace: session.user?.id != nil && session.activeOrganization?.id != nil && InboxMessaging.on(session),
                  notices: session.can("job.view", feature: "job_booking_notices"), calls: CallLogRules.available(session))
    }

    init(workspace: Bool = true, notices: Bool, calls: Bool) {
        self.workspace = workspace
        self.notices = notices
        self.calls = calls
    }

    var visible: Bool { workspace || notices || calls }

    var sections: [CommsInboxSection] {
        var sections: [CommsInboxSection] = [.all]
        if calls { sections += [.calls, .voicemail] }
        if workspace { sections += [.texts, .email] }
        if notices { sections.append(.notices) }
        return sections
    }

    var defaultSection: CommsInboxSection { .all }
}

// MARK: - Calls

/// What happened on a call, in the words a row and a card use. The server has four statuses;
/// voicemail is a separate signal it does not send yet (it records from answer).
enum CommsCallKind: Equatable {
    case missed, voicemail, answered, ongoing, dropped

    init(_ call: BookingCallRecord) {
        if call.voicemail == true { self = .voicemail; return }
        switch call.status {
        case "missed": self = .missed
        case "in_progress": self = .ongoing
        case "failed": self = .dropped
        default: self = .answered
        }
    }

    /// A card's heading.
    var heading: String {
        switch self {
        case .missed: "Missed call"
        case .voicemail: "Voicemail"
        case .answered: "Incoming call"
        case .ongoing: "Call in progress"
        case .dropped: "Dropped call"
        }
    }

    /// The status word and its dot.
    var status: (tone: StatusTone, word: String) {
        switch self {
        case .missed: (.attention, "Missed")
        case .voicemail: (.dispatched, "Voicemail")
        case .answered: (.done, "Answered")
        case .ongoing: (.inProgress, "On the call")
        case .dropped: (.attention, "Dropped")
        }
    }

    /// Waits on someone until it is opened on this phone.
    var needsAttention: Bool { self == .missed || self == .voicemail }

    var symbol: String {
        switch self {
        case .missed: "phone.arrow.down.left"
        case .voicemail: "recordingtape"
        case .answered, .ongoing: "phone.arrow.down.left"
        case .dropped: "phone.down"
        }
    }
}

extension BookingCallRecord {
    var kind: CommsCallKind { CommsCallKind(self) }

    /// "Incoming · 3:12", "Missed call", "Voicemail · 0:42" (web describeCall).
    var outcome: String {
        switch kind {
        case .missed: return "Missed call"
        case .voicemail: return length.map { "Voicemail · \(Self.clock($0))" } ?? "Voicemail"
        case .answered: return length.map { "Incoming · \(Self.clock($0))" } ?? "Incoming"
        case .ongoing: return "On the call now"
        case .dropped: return "Call dropped"
        }
    }

    var startedDate: Date? { JobFiltering.date(startedAt) }
}

/// Every call from one number, newest first. A call without a number is a thread of its own.
struct CommsCallThread: Identifiable, Hashable {
    let id: String
    let calls: [BookingCallRecord]

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && lhs.calls == rhs.calls }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var latest: BookingCallRecord { calls[0] }

    /// The newest name the server matched, else the number, else "Unknown caller".
    var name: String {
        if let named = calls.first(where: { !($0.callerName ?? "").isEmpty })?.callerName { return named }
        return displayNumber ?? "Unknown caller"
    }

    var number: String? { calls.first(where: { !($0.callerNumber ?? "").isEmpty })?.callerNumber }

    /// "(555) 010-0142" for a US number; anything else as the server sent it.
    var displayNumber: String? { number.map(CommsCallGrouping.display) }

    /// Initials for the avatar; nil shows a person glyph.
    var initials: String? {
        guard calls.contains(where: { !($0.callerName ?? "").isEmpty }) else { return nil }
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? nil : String(letters).uppercased()
    }

    var hasVoicemail: Bool { calls.contains { $0.kind == .voicemail } }

    func unread(seen: Set<String>) -> Bool {
        calls.contains { $0.kind.needsAttention && !seen.contains($0.id) }
    }

    /// The call a row speaks for: the newest voicemail in Voicemail, else the newest call.
    func lead(in section: CommsInboxSection) -> BookingCallRecord {
        section == .voicemail ? (calls.first { $0.kind == .voicemail } ?? latest) : latest
    }

    /// Web's thread alerts for calls: a missed call or a voicemail nobody has opened yet.
    func alert(seen: Set<String>, in section: CommsInboxSection) -> String? {
        let call = lead(in: section)
        guard !seen.contains(call.id) else { return nil }
        switch call.kind {
        case .missed: return "Missed call"
        case .voicemail: return "New voicemail"
        default: return nil
        }
    }

    /// Line two of a row: what happened, then what was said. A voicemail quotes its words.
    /// With `alerted` the row's status word already says "Missed call" or "New voicemail", so the
    /// line leaves that out and carries what was said (or the number).
    func line(in section: CommsInboxSection, alerted: Bool = false) -> String {
        let call = lead(in: section)
        let said = call.summary?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if alerted {
            switch call.kind {
            case .missed: return said.isEmpty ? (displayNumber ?? "No message left") : said
            case .voicemail:
                let length = call.length.map { BookingCallRecord.clock($0) }
                return [length, said.isEmpty ? nil : "\u{201C}\(said)\u{201D}"].compactMap { $0 }.joined(separator: " · ")
            default: break
            }
        }
        guard let said = call.summary?.text.trimmingCharacters(in: .whitespacesAndNewlines), !said.isEmpty else {
            return call.outcome
        }
        return call.kind == .voicemail ? "\(call.outcome) · \u{201C}\(said)\u{201D}" : "\(call.outcome) · \(said)"
    }
}

enum CommsCallGrouping {
    /// The digits that identify a caller; a US number with or without its leading 1 is one caller.
    static func display(_ number: String) -> String {
        guard let digits = key(number), digits.count == 10 else { return number }
        let d = Array(digits)
        return "(\(String(d[0..<3]))) \(String(d[3..<6]))-\(String(d[6..<10]))"
    }

    static func key(_ number: String?) -> String? {
        let digits = (number ?? "").filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        if digits.count == 11, digits.hasPrefix("1") { return String(digits.dropFirst()) }
        return digits
    }

    /// One thread per caller number (web mergeServerCalls), newest thread first. A repeated call id
    /// (a page read twice) counts once, the later copy winning.
    static func threads(_ calls: [BookingCallRecord]) -> [CommsCallThread] {
        var byID: [String: BookingCallRecord] = [:]
        var order: [String] = []
        for call in calls {
            if byID[call.id] == nil { order.append(call.id) }
            byID[call.id] = call
        }
        var buckets: [String: [BookingCallRecord]] = [:]
        var keys: [String] = []
        for id in order {
            guard let call = byID[id] else { continue }
            let key = "call-thread-" + (Self.key(call.callerNumber) ?? call.id.lowercased())
            if buckets[key] == nil { keys.append(key) }
            buckets[key, default: []].append(call)
        }
        let threads = keys.map { key in CommsCallThread(id: key, calls: buckets[key]!.sorted(by: newerFirst)) }
        return threads.sorted { newerFirst($0.latest, $1.latest) }
    }

    static func newerFirst(_ a: BookingCallRecord, _ b: BookingCallRecord) -> Bool {
        switch (a.startedDate, b.startedDate) {
        case let (x?, y?): x == y ? a.id > b.id : x > y
        case (_?, nil): true
        case (nil, _?): false
        case (nil, nil): a.startedAt > b.startedAt
        }
    }
}

// MARK: - Read state for calls

/// Which missed calls and voicemails were opened on this phone. The server keeps no read state for
/// calls, so this is per device, per person and company; it only decides the dot and the weight.
@MainActor
final class CommsCallSeen {
    private(set) var ids: Set<String>
    private let defaults: UserDefaults?
    private let key: String
    static let limit = 2_000

    /// `defaults` nil keeps it in memory (screenshots and tests).
    init(defaults: UserDefaults?, actorID: String?, organizationID: String?) {
        self.defaults = defaults
        key = "thorbis.inbox.seenCalls.\(organizationID ?? "-").\(actorID ?? "-")"
        ids = Set(defaults?.stringArray(forKey: key) ?? [])
    }

    func markSeen(_ calls: [BookingCallRecord]) {
        let new = calls.map(\.id).filter { !ids.contains($0) }
        guard !new.isEmpty else { return }
        ids.formUnion(new)
        guard let defaults else { return }
        var stored = defaults.stringArray(forKey: key) ?? []
        stored.append(contentsOf: new)
        defaults.set(Array(stored.suffix(Self.limit)), forKey: key)
    }
}

// MARK: - API

extension APIClient {
    /// One page of the office call log, at the server's largest page (web reads 200 at a time).
    func inboxCallLog(cursor: String? = nil) async throws -> CallLogPage {
        try await send("GET", "/v1/calls", queryItems: [URLQueryItem(name: "limit", value: "200")], cursor: cursor)
    }
}
