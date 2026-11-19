import Combine
import Foundation
import SwiftUI

// Paper 48N "Texts and calls": one row on the customer and the page behind it. The server keeps
// no conversation per customer, so the page is built from what this phone truly has: the
// business's call log (GET /v1/calls) narrowed to this customer's numbers, and the text and email
// drafts written on this phone for them. Nothing here says a text was sent: drafts say "draft".

/// Whether two phone numbers written different ways are the same line.
enum CustomerPhoneMatch {
    /// A number's identifying digits: the extension, punctuation and the international dialling
    /// prefix are dropped, and a US number loses its leading 1. Nil under seven digits.
    static func key(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var text = Substring(raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        if text.hasPrefix("tel:") || text.hasPrefix("sms:") { text = text.dropFirst(4) }
        var digits = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character.isASCII, character.isNumber {
                digits.append(character)
            } else if !digits.isEmpty,
                      character == "x" || character == ";" || character == "," || character == "#" || text[index...].hasPrefix("ext") {
                // "x12", "ext. 12", ";ext=12", ",,12" and "#12" all start an extension.
                break
            }
            index = text.index(after: index)
        }
        // 011 and 00 are how a country code is dialled from the US and from most other places.
        if digits.hasPrefix("011"), digits.count > 12 { digits.removeFirst(3) }
        else if digits.hasPrefix("00"), digits.count > 11 { digits.removeFirst(2) }
        if digits.count == 11, digits.hasPrefix("1") { digits.removeFirst() }
        return digits.count >= 7 ? digits : nil
    }

    /// The same line: the same digits, or one written with its country code and the other as it is
    /// dialled at home ("+44 20 7946 0958" and "020 7946 0958"). A seven-digit local number only
    /// matches itself, so an area code is never guessed.
    static func same(_ a: String?, _ b: String?) -> Bool {
        guard let a = key(a), let b = key(b) else { return false }
        return sameKeys(a, b)
    }

    static func sameKeys(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let (short, long) = a.count <= b.count ? (a, b) : (b, a)
        // The home form may lead with a trunk 0 that the international form leaves out.
        let national = short.hasPrefix("0") ? String(short.dropFirst()) : short
        return national.count >= 9 && long.count - national.count <= 3 && long.count > national.count && long.hasSuffix(national)
    }

    /// The distinct keys for a customer's numbers.
    static func keys(_ numbers: [String?]) -> [String] {
        var keys: [String] = []
        for number in numbers {
            guard let key = key(number), !keys.contains(key) else { continue }
            keys.append(key)
        }
        return keys
    }

    static func matches(_ number: String?, anyOf keys: [String]) -> Bool {
        guard let key = key(number) else { return false }
        return keys.contains { sameKeys($0, key) }
    }
}

/// One thing on the customer's Texts and calls page.
struct CustomerCommsEntry: Identifiable, Equatable {
    enum Kind: Equatable { case call, text, email }

    let id: String
    let kind: Kind
    /// When it happened, as the source wrote it; nil for text still being typed.
    let at: String?
    /// "Missed call", "Incoming · 3:12", "Text draft", "Email queued on this phone".
    let title: String
    /// What was said: a call's summary, a text's words, an email's subject.
    let detail: String?
    /// A missed or dropped call.
    let attention: Bool
    /// The call thread or the on-phone conversation that opens from the row.
    let threadID: String

    var symbol: String {
        switch kind {
        case .call: attention ? "phone.arrow.down.left" : "phone"
        case .text: "bubble.left"
        case .email: "envelope"
        }
    }
}

enum CustomerComms {
    /// The customer's calls in the log, newest first: calls the office linked to this customer,
    /// and calls from one of the customer's numbers that are not linked to someone else.
    static func calls(_ calls: [BookingCallRecord], customerID: String, numbers: [String?]) -> [BookingCallRecord] {
        let keys = CustomerPhoneMatch.keys(numbers)
        var seen = Set<String>()
        let mine = calls.filter { call in
            guard seen.insert(call.id).inserted else { return false }
            if let linked = call.customerId, !linked.isEmpty {
                return linked.caseInsensitiveCompare(customerID) == .orderedSame
            }
            return CustomerPhoneMatch.matches(call.callerNumber, anyOf: keys)
        }
        return mine.sorted(by: CommsCallGrouping.newerFirst)
    }

    static func emailKey(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.contains("@") ? trimmed : nil
    }

    /// The conversations kept on this phone with this customer: texts by number, email by address.
    /// What was moved to the Bin stays out.
    static func threads(_ threads: [CommsLocalThread], numbers: [String?], emails: [String?]) -> [CommsLocalThread] {
        let keys = CustomerPhoneMatch.keys(numbers)
        let addresses = Set(emails.compactMap(emailKey))
        return threads.filter { thread in
            guard thread.flags.place != .bin else { return false }
            switch thread.channel {
            case .sms:
                return CustomerPhoneMatch.matches(thread.phone, anyOf: keys)
            case .email:
                if let address = emailKey(thread.email), addresses.contains(address) { return true }
                return thread.messages.contains { ($0.to ?? []).contains { emailKey($0).map(addresses.contains) ?? false } }
            }
        }
    }

    /// Everything on the page, newest first. Text still being typed has no time and leads.
    static func entries(calls: [BookingCallRecord], threads: [CommsLocalThread]) -> [CustomerCommsEntry] {
        var entries: [CustomerCommsEntry] = calls.map { call -> CustomerCommsEntry in
            let said = call.summary?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return CustomerCommsEntry(id: "call-\(call.id)", kind: .call, at: call.startedAt, title: call.outcome,
                                      detail: said.isEmpty ? nil : said,
                                      attention: call.kind == .missed || call.kind == .dropped,
                                      threadID: "call-thread-" + (CommsCallGrouping.key(call.callerNumber) ?? call.id.lowercased()))
        }
        for thread in threads {
            let email = thread.channel == .email
            let typed = (thread.composing ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !typed.isEmpty {
                entries.append(CustomerCommsEntry(id: "typing-\(thread.id)", kind: email ? .email : .text, at: nil,
                                                  title: email ? "Email draft" : "Text draft", detail: typed,
                                                  attention: false, threadID: thread.id))
            }
            for message in thread.messages {
                let body = message.body.trimmingCharacters(in: .whitespacesAndNewlines)
                let subject = (message.subject ?? thread.subject ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                entries.append(CustomerCommsEntry(id: "message-\(thread.id)-\(message.id)", kind: email ? .email : .text,
                                                  at: message.at, title: title(message, email: email),
                                                  detail: email ? (subject.isEmpty ? (body.isEmpty ? nil : body) : subject) : (body.isEmpty ? nil : body),
                                                  attention: false, threadID: thread.id))
            }
        }
        return entries.sorted(by: newerFirst)
    }

    /// Ours and unsent says so: there is no text or email service behind this phone's inbox.
    private static func title(_ message: CommsLocalMessage, email: Bool) -> String {
        let word = email ? "Email" : "Text"
        switch message.status {
        case .draft: return "\(word) draft"
        case .queued: return "\(word) queued on this phone"
        case .received: return "\(word) from customer"
        }
    }

    static func newerFirst(_ a: CustomerCommsEntry, _ b: CustomerCommsEntry) -> Bool {
        switch (JobFiltering.date(a.at), JobFiltering.date(b.at)) {
        case let (x?, y?): x == y ? a.id > b.id : x > y
        case (nil, _?): true
        case (_?, nil): false
        case (nil, nil): a.id > b.id
        }
    }

    /// The row's time: the clock today, "Mar 12" this year, "Mar 12, 2025" before it.
    static func when(_ raw: String?, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard let date = JobFiltering.date(raw) else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.setLocalizedDateFormatFromTemplate("jmm")
        } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("MMMdyyyy")
        }
        return formatter.string(from: date)
    }

    /// The hub row's line (Paper: "Running 10 min late?" · 9:39 AM): the newest thing, and when.
    static func summary(_ entries: [CustomerCommsEntry], now: Date = .now, calendar: Calendar = .current,
                        locale: Locale = .current) -> String? {
        guard let latest = entries.first else { return nil }
        let time = when(latest.at, now: now, calendar: calendar, locale: locale)
        let lead: String
        switch latest.kind {
        case .call:
            lead = latest.title
        case .text, .email:
            // The words in quotes, as Paper shows them; a draft says so where the time would be.
            let words = (latest.detail ?? "").split(whereSeparator: \.isNewline).first.map { String($0) } ?? ""
            lead = words.isEmpty ? latest.title : "\u{201C}\(words)\u{201D}"
            if latest.title.hasSuffix("draft") { return [lead, "draft"].joined(separator: " · ") }
            if latest.title.contains("queued") { return [lead, "not sent"].joined(separator: " · ") }
        }
        return time.isEmpty ? lead : "\(lead) · \(time)"
    }
}

/// The call log for one customer page. It wraps the Inbox's own model, so a call opened here is
/// the same call thread Messages shows, and what was opened is remembered the same way.
@MainActor
final class CustomerCommsModel: ObservableObject {
    private(set) var inbox: CommsInboxModel?
    private(set) var local: CommsLocalStore?
    private var key: String?
    private var relays: [AnyCancellable] = []

    var calls: [BookingCallRecord] { inbox?.calls ?? [] }
    var loading: Bool { inbox?.callsLoading ?? false }
    var loaded: Bool { inbox?.callsLoaded ?? false }
    var denied: Bool { inbox?.callsDenied ?? false }
    var error: String? { inbox?.callsError }
    var hasOlder: Bool { inbox?.callsCursor != nil }
    /// Off until the server can deliver texts and email; drafts kept on this phone stay out of sight.
    var messagingOn = true
    var threads: [CommsLocalThread] { messagingOn ? (local?.threads ?? []) : [] }

    /// Opens this sign-in's call log and on-phone inbox; another sign-in starts clean.
    func bind(actorID: String?, organizationID: String?) {
        guard let actorID, let organizationID else {
            inbox = nil; local = nil; key = nil; relays = []
            objectWillChange.send()
            return
        }
        let next = "\(actorID.lowercased())|\(organizationID.lowercased())"
        guard key != next else { return }
        key = next
        var persists = true
        #if DEBUG
        persists = !PaperPreview.enabled
        #endif
        let inbox = CommsInboxModel(seen: CommsCallSeen(defaults: persists ? .standard : nil,
                                                         actorID: actorID, organizationID: organizationID))
        let local = CommsLocalStore.shared(actorID: actorID, organizationID: organizationID)
        relays = [inbox.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() },
                  local.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }]
        self.inbox = inbox
        self.local = local
        objectWillChange.send()
    }

    func refresh(api: APIClient) async { await inbox?.refreshCalls(api: api) }
    func loadOlder(api: APIClient) async { await inbox?.loadOlderCalls(api: api) }
}
