import Foundation
import SwiftUI

// The Inbox's texts and email, as the web beta has them today (apps/web features/inbox/store.ts):
// conversations, drafts and canned replies live on this device, per person and workspace. No text
// or email provider is connected, so nothing is ever sent: a text is saved as a Draft (or Queued
// when given a time), an email is Queued. The copy says so wherever a message is written.

/// Where a conversation lives (web CommsFolder; Spam is not offered on the phone).
enum CommsFolder: String, CaseIterable, Identifiable {
    case inbox, drafts, sent, archive, bin
    var id: String { rawValue }
    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .drafts: "Drafts"
        case .sent: "Sent"
        case .archive: "Archive"
        case .bin: "Bin"
        }
    }
    var symbol: String {
        switch self {
        case .inbox: "tray"
        case .drafts: "square.and.pencil"
        case .sent: "paperplane"
        case .archive: "archivebox"
        case .bin: "trash"
        }
    }
}

/// web CommsQuickFilter, the ones the phone offers.
enum CommsQuickFilter: String, CaseIterable {
    case all = "All", unread = "Unread", needsReply = "Needs reply", starred = "Starred"
}

/// Per-conversation marks the person sets on this device (web's `${flag}At` fields).
struct CommsThreadFlags: Codable, Equatable {
    var starredAt: String?
    var archivedAt: String?
    var binnedAt: String?
    /// Set by Mark unread / Mark read on a call thread; nil follows whether its calls were opened.
    var unread: Bool?

    /// Bin beats archive; the rest is the inbox (web threadFolder).
    var place: CommsFolder { binnedAt != nil ? .bin : archivedAt != nil ? .archive : .inbox }
}

struct CommsLocalMessage: Codable, Identifiable, Equatable {
    enum Channel: String, Codable { case sms, email }
    enum Direction: String, Codable { case inbound, outbound }
    /// received: from the contact (screenshots only). draft / queued: ours, never sent.
    enum Status: String, Codable { case received, draft, queued }

    var id: String
    var channel: Channel
    var direction: Direction
    var at: String
    var body: String
    var status: Status
    var scheduledAt: String? = nil
    var subject: String? = nil
    var to: [String]? = nil
    var cc: [String]? = nil
    var bcc: [String]? = nil
}

struct CommsLocalThread: Codable, Identifiable, Equatable {
    var id: String
    var contactName: String
    var phone: String
    var email: String?
    var channel: CommsLocalMessage.Channel
    var subject: String?
    var unread: Bool
    var flags: CommsThreadFlags
    var messages: [CommsLocalMessage]
    /// The text being written and not yet saved as a message (web draftsStore).
    var composing: String?

    var latest: CommsLocalMessage? { messages.last }
    var latestAt: String? { latest?.at }
    var needsReply: Bool { latest?.direction == .inbound }
    var hasDraft: Bool {
        messages.contains { $0.status == .draft } || !(composing ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var hasSent: Bool { messages.contains { $0.direction == .outbound && $0.status == .queued } }

    /// web inFolder: Drafts and Sent are lenses over where a thread lives, not places.
    func inFolder(_ folder: CommsFolder) -> Bool {
        let place = flags.place
        switch folder {
        case .inbox, .archive, .bin: return place == folder
        case .drafts: return place != .bin && hasDraft
        case .sent: return place != .bin && hasSent
        }
    }

    var initials: String? {
        let letters = contactName.split(separator: " ").prefix(2).compactMap(\.first).filter(\.isLetter)
        return letters.isEmpty ? nil : String(letters).uppercased()
    }

    /// Line two of a row: an email's subject; a text's newest line, saying when it is ours and unsent.
    var line: String {
        if channel == .email { return subject ?? latest?.subject ?? "(no subject)" }
        guard let latest else {
            return (composing ?? "").isEmpty ? "No messages yet." : "Draft: \(composing ?? "")"
        }
        switch latest.status {
        case .received: return latest.body
        case .draft: return "Draft: \(latest.body)"
        case .queued: return "Queued: \(latest.body)"
        }
    }
}

/// A saved reply (web CannedReply), kept on this device.
struct CommsCannedReply: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var body: String

    /// web's three built-ins.
    static let builtIns: [CommsCannedReply] = [
        .init(id: "on-the-way", name: "On the way", body: "We're on the way \u{2014} about 20 minutes out."),
        .init(id: "running-late", name: "Running late", body: "Running a little behind on the job before yours. New window is "),
        .init(id: "invoice-sent", name: "Invoice sent", body: "All finished \u{2014} the invoice is on its way. Thanks for having us out!"),
    ]
}

/// web smsSegments: 160 characters a segment.
enum CommsSMS {
    static let segment = 160
    static func segments(_ body: String) -> Int { body.isEmpty ? 0 : (body.count + segment - 1) / segment }
    static func counter(_ body: String) -> String? {
        guard !body.isEmpty else { return nil }
        return "\(body.count) character\(body.count == 1 ? "" : "s") · \(segments(body)) SMS"
    }
}

// MARK: - Store

/// This device's conversations for one person in one workspace, kept as a file in Application
/// Support. Screenshots use an in-memory store with sample conversations.
@MainActor
final class CommsLocalStore: ObservableObject {
    @Published private(set) var threads: [CommsLocalThread] = []
    /// Marks on call threads (star, archive, bin, read), by thread id.
    @Published private(set) var callFlags: [String: CommsThreadFlags] = [:]
    @Published private(set) var cannedReplies: [CommsCannedReply] = CommsCannedReply.builtIns

    private let file: URL?
    private let now: () -> Date

    private struct Snapshot: Codable {
        var threads: [CommsLocalThread]
        var callFlags: [String: CommsThreadFlags]
        var cannedReplies: [CommsCannedReply]?
    }

    init(file: URL?, now: @escaping () -> Date = Date.init) {
        self.file = file
        self.now = now
        if let file, let data = try? Data(contentsOf: file), let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            threads = snapshot.threads
            callFlags = snapshot.callFlags
            cannedReplies = snapshot.cannedReplies ?? CommsCannedReply.builtIns
        }
    }

    private static var stores: [String: CommsLocalStore] = [:]

    /// One store per person and workspace on this device.
    static func shared(actorID: String?, organizationID: String?) -> CommsLocalStore {
        let key = "\(organizationID?.lowercased() ?? "-")_\(actorID?.lowercased() ?? "-")"
        if let store = stores[key] { return store }
        let store: CommsLocalStore
        #if DEBUG
        if PaperPreview.enabled {
            store = CommsLocalStore(file: nil)
            store.seedPreview()
            stores[key] = store
            return store
        }
        #endif
        let safe = key.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("inbox", isDirectory: true)
        if let folder { try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        store = CommsLocalStore(file: folder?.appendingPathComponent("\(safe).json"))
        stores[key] = store
        return store
    }

    private var stamp: String { ISO8601DateFormatter().string(from: now()) }

    private func save() {
        guard let file else { return }
        let snapshot = Snapshot(threads: threads, callFlags: callFlags, cannedReplies: cannedReplies)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: file, options: [.atomic, .completeFileProtection])
        }
    }

    func thread(_ id: String) -> CommsLocalThread? { threads.first { $0.id == id } }

    private func patch(_ id: String, _ change: (inout CommsLocalThread) -> Void) {
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        change(&threads[index])
        save()
    }

    // MARK: Opening conversations

    /// web threadForPhone: the text conversation with this number (by digits), brought back to the
    /// inbox if it was archived or binned, or a new empty one. Returns its id.
    @discardableResult
    func threadForPhone(_ phone: String, contactName: String? = nil) -> String {
        let wanted = CommsCallGrouping.key(phone)
        if let wanted, let existing = threads.first(where: { $0.channel == .sms && CommsCallGrouping.key($0.phone) == wanted }) {
            if existing.flags.place != .inbox {
                patch(existing.id) { $0.flags.archivedAt = nil; $0.flags.binnedAt = nil }
            }
            return existing.id
        }
        let name = contactName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let thread = CommsLocalThread(id: "t-\(UUID().uuidString.lowercased())", contactName: (name?.isEmpty == false ? name! : phone),
                                      phone: phone, email: nil, channel: .sms, subject: nil, unread: false,
                                      flags: CommsThreadFlags(), messages: [], composing: nil)
        // Empty on purpose: a new conversation has no history to invent.
        threads.insert(thread, at: 0)
        save()
        return thread.id
    }

    // MARK: Texts

    func setComposing(_ id: String, _ body: String) {
        guard let index = threads.firstIndex(where: { $0.id == id }), threads[index].composing != body else { return }
        threads[index].composing = body
        save()
    }

    /// web commitDraft: the text lands as a Draft, or Queued with the time it was scheduled for.
    @discardableResult
    func commitText(_ id: String, body: String, scheduledAt: Date? = nil) -> Bool {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, thread(id) != nil else { return false }
        let message = CommsLocalMessage(id: UUID().uuidString.lowercased(), channel: .sms, direction: .outbound, at: stamp, body: text,
                                        status: scheduledAt == nil ? .draft : .queued,
                                        scheduledAt: scheduledAt.map { ISO8601DateFormatter().string(from: $0) })
        patch(id) { $0.messages.append(message); $0.composing = nil }
        return true
    }

    /// A scheduled text goes back to being a draft (web cancelScheduled).
    func cancelScheduled(_ threadID: String, messageID: String) {
        patch(threadID) { thread in
            guard let index = thread.messages.firstIndex(where: { $0.id == messageID && $0.status == .queued }) else { return }
            thread.messages[index].status = .draft
            thread.messages[index].scheduledAt = nil
        }
    }

    /// Discards a draft message. A conversation that was only ever that draft goes with it.
    func discardDraft(_ threadID: String, messageID: String) {
        guard let thread = thread(threadID), thread.messages.contains(where: { $0.id == messageID && $0.status == .draft }) else { return }
        if thread.messages.count == 1 && thread.channel == .email {
            threads.removeAll { $0.id == threadID }
            save()
        } else {
            patch(threadID) { $0.messages.removeAll { $0.id == messageID } }
        }
    }

    // MARK: Email

    struct Mail: Equatable {
        var to: [String]
        var cc: [String] = []
        var bcc: [String] = []
        var subject: String
        var body: String
    }

    /// web commitMail: saving makes a Draft; Send makes it Queued, never sent. Replies into
    /// `threadID` when given. Returns the conversation's id.
    @discardableResult
    func commitMail(_ mail: Mail, send: Bool, threadID: String? = nil, editing messageID: String? = nil) -> String? {
        let to = mail.to.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !to.isEmpty else { return nil }
        let subject = mail.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = CommsLocalMessage(id: messageID ?? UUID().uuidString.lowercased(), channel: .email, direction: .outbound, at: stamp,
                                        body: mail.body, status: send ? .queued : .draft,
                                        subject: subject.isEmpty ? "(no subject)" : subject, to: to,
                                        cc: mail.cc.isEmpty ? nil : mail.cc, bcc: mail.bcc.isEmpty ? nil : mail.bcc)
        if let threadID, thread(threadID) != nil {
            patch(threadID) { thread in
                if let messageID, let index = thread.messages.firstIndex(where: { $0.id == messageID && $0.status == .draft }) {
                    thread.messages[index] = message
                } else {
                    thread.messages.append(message)
                }
                if thread.subject == nil, !subject.isEmpty { thread.subject = subject }
            }
            return threadID
        }
        let thread = CommsLocalThread(id: "t-\(UUID().uuidString.lowercased())", contactName: to[0], phone: "", email: to[0],
                                      channel: .email, subject: subject.isEmpty ? "(no subject)" : subject, unread: false,
                                      flags: CommsThreadFlags(), messages: [message], composing: nil)
        threads.insert(thread, at: 0)
        save()
        return thread.id
    }

    // MARK: Canned replies

    func saveCannedReply(name: String, body: String) {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        cannedReplies.append(.init(id: UUID().uuidString.lowercased(), name: title.isEmpty ? String(text.prefix(28)) : title, body: text))
        save()
    }

    func deleteCannedReply(_ id: String) {
        cannedReplies.removeAll { $0.id == id }
        save()
    }

    // MARK: Marks (texts, email and call threads alike)

    func flags(_ id: String) -> CommsThreadFlags {
        thread(id)?.flags ?? callFlags[id] ?? CommsThreadFlags()
    }

    private func setFlags(_ id: String, _ change: (inout CommsThreadFlags) -> Void) {
        if thread(id) != nil {
            patch(id) { change(&$0.flags) }
        } else {
            var flags = callFlags[id] ?? CommsThreadFlags()
            change(&flags)
            callFlags[id] = flags
            save()
        }
    }

    func toggleStar(_ id: String) { let stamp = stamp; setFlags(id) { $0.starredAt = $0.starredAt == nil ? stamp : nil } }
    func archive(_ id: String) { let stamp = stamp; setFlags(id) { $0.archivedAt = stamp; $0.binnedAt = nil } }
    func bin(_ id: String) { let stamp = stamp; setFlags(id) { $0.binnedAt = stamp } }
    /// Back to the inbox from Archive or Bin.
    func moveToInbox(_ id: String) { setFlags(id) { $0.archivedAt = nil; $0.binnedAt = nil } }

    func setUnread(_ id: String, _ unread: Bool) {
        if thread(id) != nil { patch(id) { $0.unread = unread } } else { setFlags(id) { $0.unread = unread } }
    }

    /// Opening a call thread reads it; the calls' own seen marks take over again.
    func clearCallUnread(_ id: String) {
        guard callFlags[id]?.unread != nil else { return }
        callFlags[id]?.unread = nil
        save()
    }

    // MARK: Screenshots

    #if DEBUG
    /// Sample conversations for `--paper-preview` only; the real app starts empty.
    func seedPreview() {
        let base = now()
        func at(_ minutesAgo: Double) -> String { ISO8601DateFormatter().string(from: base.addingTimeInterval(-minutesAgo * 60)) }
        threads = [
            CommsLocalThread(id: "t-preview-text", contactName: "Danielle Marlowe", phone: "(555) 010-0144", email: nil, channel: .sms,
                             subject: nil, unread: true, flags: CommsThreadFlags(), messages: [
                                .init(id: "m-preview-1", channel: .sms, direction: .outbound, at: at(190), body: "Hi Danielle, this is Acme HVAC confirming tomorrow 9\u{2013}11 a.m.", status: .draft),
                                .init(id: "m-preview-2", channel: .sms, direction: .inbound, at: at(42), body: "Thanks! Can the tech text when they're 20 minutes out?", status: .received),
                             ], composing: nil),
            CommsLocalThread(id: "t-preview-email", contactName: "ops@harborviewhoa.com", phone: "", email: "ops@harborviewhoa.com", channel: .email,
                             subject: "Quarterly filter changes", unread: false, flags: CommsThreadFlags(), messages: [
                                .init(id: "m-preview-3", channel: .email, direction: .outbound, at: at(300),
                                      body: "Hello,\n\nWe can do all twelve units on the 14th. I've attached the visit plan.\n\nThanks,\nAcme HVAC",
                                      status: .queued, subject: "Quarterly filter changes", to: ["ops@harborviewhoa.com"]),
                             ], composing: nil),
        ]
    }
    #endif
}

// MARK: - What a section shows

/// A row in the list: a caller's calls, a text or email conversation, or a job notice.
enum CommsInboxItem: Identifiable {
    case calls(CommsCallThread)
    case local(CommsLocalThread)
    case notice(StaffNotice)

    var id: String {
        switch self {
        case .calls(let thread): thread.id
        case .local(let thread): thread.id
        case .notice(let notice): "notice-\(notice.id)"
        }
    }

    func at(in section: CommsInboxSection) -> String? {
        switch self {
        case .calls(let thread): thread.lead(in: section).startedAt
        case .local(let thread): thread.latestAt
        case .notice(let notice): notice.at
        }
    }
}

enum CommsInboxScope {
    /// Folders a section has (web foldersForView): calls are never drafted or sent; notices have none.
    static func folders(_ section: CommsInboxSection) -> [CommsFolder] {
        switch section {
        case .calls, .voicemail: [.inbox, .archive, .bin]
        case .notices: []
        default: CommsFolder.allCases
        }
    }

    static func filters(_ section: CommsInboxSection) -> [CommsQuickFilter] {
        section == .notices ? [.all, .unread] : CommsQuickFilter.allCases
    }

    /// A call thread is unread when Mark unread says so, else while a missed call or voicemail
    /// in it has not been opened on this phone.
    static func callUnread(_ thread: CommsCallThread, flags: CommsThreadFlags, seen: Set<String>) -> Bool {
        flags.unread ?? thread.unread(seen: seen)
    }

    /// Everything a section shows in a folder under a quick filter, newest first; rows with no
    /// readable date go last in their own order (web matchesScope + sortThreads).
    static func items(section: CommsInboxSection, folder: CommsFolder, filter: CommsQuickFilter,
                      calls: [CommsCallThread], local: [CommsLocalThread], notices: [StaffNotice],
                      callFlags: [String: CommsThreadFlags], seen: Set<String>) -> [CommsInboxItem] {
        var items: [CommsInboxItem] = []
        if [.all, .calls, .voicemail].contains(section), [.inbox, .archive, .bin].contains(folder) {
            for thread in calls where section != .voicemail || thread.hasVoicemail {
                let flags = callFlags[thread.id] ?? CommsThreadFlags()
                guard flags.place == folder else { continue }
                switch filter {
                case .all: break
                case .unread: guard callUnread(thread, flags: flags, seen: seen) else { continue }
                case .needsReply: break  // a call is from the caller: it waits on a reply (web threadNeedsReply)
                case .starred: guard flags.starredAt != nil else { continue }
                }
                items.append(.calls(thread))
            }
        }
        if [.all, .texts, .email].contains(section) {
            for thread in local where thread.inFolder(folder) {
                if section == .texts && thread.channel != .sms { continue }
                if section == .email && thread.channel != .email { continue }
                switch filter {
                case .all: break
                case .unread: guard thread.unread else { continue }
                case .needsReply: guard thread.needsReply else { continue }
                case .starred: guard thread.flags.starredAt != nil else { continue }
                }
                items.append(.local(thread))
            }
        }
        if section == .notices || (section == .all && folder == .inbox) {
            switch filter {
            case .all: items += notices.map(CommsInboxItem.notice)
            case .unread: items += notices.filter { !$0.read }.map(CommsInboxItem.notice)
            default: break
            }
        }
        if section == .notices { return items }
        let dated = items.enumerated().map { (offset: $0.offset, item: $0.element, date: JobFiltering.date($0.element.at(in: section))) }
        return dated.sorted { a, b in
            switch (a.date, b.date) {
            case let (x?, y?): x == y ? a.offset < b.offset : x > y
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): a.offset < b.offset
            }
        }.map(\.item)
    }
}
