import XCTest
@testable import Thorbis

@MainActor
final class CustomerCommsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        return calendar
    }
    private let locale = Locale(identifier: "en_US")
    private let now = ISO8601DateFormatter().date(from: "2026-11-17T20:00:00Z") ?? Date()

    private func call(_ id: String, status: String = "completed", number: String? = "+19165550148", customerID: String? = nil,
                      at: String = "2026-11-17T17:39:00Z", duration: Int? = 192, summary: String? = nil) throws -> BookingCallRecord {
        var object: [String: Any] = ["id": id, "direction": "inbound", "status": status, "lineId": "line-1", "startedAt": at,
                                     "recording": ["status": "none"], "transcriptStatus": "none"]
        if let number { object["callerNumber"] = number }
        if let customerID { object["customerId"] = customerID }
        if let duration { object["durationSeconds"] = duration }
        if let summary { object["summary"] = ["text": summary, "source": "model"] }
        return try JSONDecoder().decode(BookingCallRecord.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func thread(_ id: String, phone: String = "", email: String? = nil, channel: CommsLocalMessage.Channel = .sms,
                        messages: [CommsLocalMessage] = [], composing: String? = nil, binned: Bool = false) -> CommsLocalThread {
        var flags = CommsThreadFlags()
        if binned { flags.binnedAt = "2026-11-17T00:00:00Z" }
        return CommsLocalThread(id: id, contactName: "Danielle Marlowe", phone: phone, email: email, channel: channel,
                                subject: nil, unread: false, flags: flags, messages: messages, composing: composing)
    }

    private func message(_ id: String, _ body: String, status: CommsLocalMessage.Status = .draft, at: String,
                         channel: CommsLocalMessage.Channel = .sms, subject: String? = nil, to: [String]? = nil) -> CommsLocalMessage {
        CommsLocalMessage(id: id, channel: channel, direction: status == .received ? .inbound : .outbound, at: at, body: body,
                          status: status, subject: subject, to: to)
    }

    // MARK: Phone numbers

    func testFormatsOfOneNumberMatch() {
        let written = ["(916) 555-0148", "916-555-0148", "916.555.0148", "916 555 0148", "9165550148", "tel:9165550148"]
        for a in written {
            for b in written { XCTAssertTrue(CustomerPhoneMatch.same(a, b), "\(a) should match \(b)") }
        }
    }

    func testCountryCodeIsTheSameLine() {
        XCTAssertTrue(CustomerPhoneMatch.same("+1 (916) 555-0148", "916-555-0148"))
        XCTAssertTrue(CustomerPhoneMatch.same("1-916-555-0148", "(916) 555-0148"))
        XCTAssertTrue(CustomerPhoneMatch.same("+19165550148", "19165550148"))
        XCTAssertEqual(CustomerPhoneMatch.key("+1 916 555 0148"), "9165550148")
        // Outside the US: the home form leads with a trunk 0 the international form leaves out.
        XCTAssertTrue(CustomerPhoneMatch.same("+44 20 7946 0958", "020 7946 0958"))
        XCTAssertTrue(CustomerPhoneMatch.same("0044 20 7946 0958", "+44 20 7946 0958"))
        XCTAssertTrue(CustomerPhoneMatch.same("011 44 20 7946 0958", "+442079460958"))
    }

    func testExtensionsAreDropped() {
        for written in ["916-555-0148 x12", "916-555-0148 ext. 204", "916-555-0148 Ext 204", "(916) 555-0148 extension 9",
                        "+19165550148;ext=12", "9165550148,,12", "916-555-0148 #3"] {
            XCTAssertEqual(CustomerPhoneMatch.key(written), "9165550148", written)
            XCTAssertTrue(CustomerPhoneMatch.same(written, "(916) 555-0148"), written)
        }
        // An extension is not part of the number: a different line with the same extension differs.
        XCTAssertFalse(CustomerPhoneMatch.same("916-555-0148 x12", "916-555-0199 x12"))
    }

    func testDifferentOrIncompleteNumbersDoNotMatch() {
        XCTAssertFalse(CustomerPhoneMatch.same("916-555-0148", "916-555-0149"))
        XCTAssertFalse(CustomerPhoneMatch.same("916-555-0148", "415-555-0148"))
        // A seven-digit local number never borrows an area code.
        XCTAssertFalse(CustomerPhoneMatch.same("555-0148", "916-555-0148"))
        XCTAssertTrue(CustomerPhoneMatch.same("555-0148", "5550148"))
        XCTAssertFalse(CustomerPhoneMatch.same(nil, "916-555-0148"))
        XCTAssertFalse(CustomerPhoneMatch.same("", ""))
        XCTAssertFalse(CustomerPhoneMatch.same("call the office", "916-555-0148"))
        XCTAssertNil(CustomerPhoneMatch.key("12345"))
        XCTAssertNil(CustomerPhoneMatch.key("ext 12"))
    }

    func testKeysAreDistinct() {
        XCTAssertEqual(CustomerPhoneMatch.keys(["(916) 555-0148", "+1 916 555 0148", nil, "", "415-555-0100"]),
                       ["9165550148", "4155550100"])
        XCTAssertTrue(CustomerPhoneMatch.matches("916.555.0148 x4", anyOf: ["4155550100", "9165550148"]))
        XCTAssertFalse(CustomerPhoneMatch.matches("916.555.0148", anyOf: []))
    }

    // MARK: Calls for a customer

    func testCallsAreNarrowedToTheCustomersNumbersNewestFirst() throws {
        let log = [try call("a", number: "+19165550148", at: "2026-11-15T10:00:00Z"),
                   try call("b", number: "+14155550100", at: "2026-11-16T10:00:00Z"),
                   try call("c", number: "(916) 555-0148", at: "2026-11-17T10:00:00Z"),
                   try call("d", number: nil, at: "2026-11-17T11:00:00Z")]
        let mine = CustomerComms.calls(log, customerID: "cus-1", numbers: ["916-555-0148 x2", nil])
        XCTAssertEqual(mine.map(\.id), ["c", "a"])
        XCTAssertTrue(CustomerComms.calls(log, customerID: "cus-1", numbers: []).isEmpty)
    }

    func testALinkedCallFollowsItsLinkNotItsNumber() throws {
        let log = [try call("linked-here", number: "+14155550100", customerID: "CUS-1"),
                   try call("linked-elsewhere", number: "+19165550148", customerID: "cus-2"),
                   try call("unlinked", number: "+19165550148"),
                   try call("unlinked", number: "+19165550148")]
        let mine = CustomerComms.calls(log, customerID: "cus-1", numbers: ["(916) 555-0148"])
        XCTAssertEqual(Set(mine.map(\.id)), ["linked-here", "unlinked"])
        XCTAssertEqual(mine.count, 2, "a call read twice counts once")
    }

    // MARK: This phone's drafts

    func testThreadsMatchByNumberOrAddressAndSkipTheBin() {
        let threads = [thread("text", phone: "+1 916 555 0148"),
                       thread("other", phone: "415-555-0100"),
                       thread("mail", email: " Danielle@Example.com ", channel: .email),
                       thread("mail-to", channel: .email,
                              messages: [message("m", "Hi", at: "2026-11-17T10:00:00Z", channel: .email, to: ["danielle@example.com"])]),
                       thread("binned", phone: "916-555-0148", binned: true)]
        let mine = CustomerComms.threads(threads, numbers: ["(916) 555-0148"], emails: ["danielle@example.com"])
        XCTAssertEqual(mine.map(\.id), ["text", "mail", "mail-to"])
        XCTAssertTrue(CustomerComms.threads(threads, numbers: [], emails: []).isEmpty)
    }

    func testEntriesAreNewestFirstAndSayWhatIsUnsent() throws {
        let calls = [try call("c1", status: "missed", at: "2026-11-17T17:00:00Z", duration: nil),
                     try call("c2", at: "2026-11-10T17:00:00Z", duration: 192, summary: "Booked a visit")]
        let threads = [thread("t", phone: "916-555-0148",
                              messages: [message("m1", "Running 10 min late?", status: .queued, at: "2026-11-17T17:39:00Z"),
                                         message("m2", "See you at 9", status: .draft, at: "2026-11-12T09:00:00Z")],
                              composing: "  On my way ")]
        let entries = CustomerComms.entries(calls: calls, threads: threads)
        XCTAssertEqual(entries.map(\.id), ["typing-t", "message-t-m1", "call-c1", "message-t-m2", "call-c2"])
        XCTAssertEqual(entries.map(\.title), ["Text draft", "Text queued on this phone", "Missed call", "Text draft", "Incoming · 3:12"])
        XCTAssertEqual(entries[0].detail, "On my way")
        XCTAssertEqual(entries[2].attention, true)
        XCTAssertEqual(entries[4].detail, "Booked a visit")
        XCTAssertEqual(entries[2].threadID, "call-thread-9165550148")
        XCTAssertEqual(entries[1].threadID, "t")
    }

    func testSummaryIsTheLatestItem() throws {
        XCTAssertNil(CustomerComms.summary([]))
        let missed = CustomerComms.entries(calls: [try call("c1", status: "missed", at: "2026-11-17T17:39:00Z", duration: nil)], threads: [])
        XCTAssertEqual(CustomerComms.summary(missed, now: now, calendar: calendar, locale: locale)?
                        .replacingOccurrences(of: "\u{202F}", with: " "), "Missed call · 9:39 AM")
        let old = CustomerComms.entries(calls: [try call("c2", at: "2025-03-12T17:39:00Z")], threads: [])
        XCTAssertEqual(CustomerComms.summary(old, now: now, calendar: calendar, locale: locale), "Incoming · 3:12 · Mar 12, 2025")
        let draft = CustomerComms.entries(calls: missed.isEmpty ? [] : [try call("c1", status: "missed", at: "2026-11-16T17:39:00Z")],
                                          threads: [thread("t", phone: "916-555-0148",
                                                           messages: [message("m", "Running 10 min late?\nSorry", at: "2026-11-17T17:00:00Z")])])
        XCTAssertEqual(CustomerComms.summary(draft, now: now, calendar: calendar, locale: locale), "\u{201C}Running 10 min late?\u{201D} · draft")
        let received = CustomerComms.entries(calls: [], threads: [thread("t", phone: "916-555-0148",
            messages: [message("m", "Can you use the card on file?", status: .received, at: "2026-11-17T17:40:00Z")])])
        XCTAssertEqual(CustomerComms.summary(received, now: now, calendar: calendar, locale: locale)?
                        .replacingOccurrences(of: "\u{202F}", with: " "), "\u{201C}Can you use the card on file?\u{201D} · 9:40 AM")
    }
}
