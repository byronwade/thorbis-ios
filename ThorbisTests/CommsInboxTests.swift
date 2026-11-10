import XCTest
@testable import Thorbis

@MainActor
final class CommsInboxTests: XCTestCase {
    private func call(_ id: String, status: String = "completed", number: String? = "+15550100100", name: String? = nil,
                      at: String = "2026-11-05T15:00:00Z", duration: Int? = 192, voicemail: Bool? = nil,
                      summary: String? = nil) throws -> BookingCallRecord {
        var object: [String: Any] = ["id": id, "direction": "inbound", "status": status, "lineId": "line-1", "startedAt": at,
                                     "recording": ["status": "none"], "transcriptStatus": "none"]
        if let number { object["callerNumber"] = number }
        if let name { object["callerName"] = name }
        if let duration { object["durationSeconds"] = duration }
        if let voicemail { object["voicemail"] = voicemail }
        if let summary { object["summary"] = ["text": summary, "source": "model"] }
        return try JSONDecoder().decode(BookingCallRecord.self, from: JSONSerialization.data(withJSONObject: object))
    }

    // MARK: Decoding

    func testTheLogDecodesEveryCallViewFieldAtTheServersLargestPage() async throws {
        let json = #"{"items":[{"id":"00000000-0000-4000-8000-000000009702","direction":"inbound","status":"completed","lineId":"line-1","callerNumber":"+15550100100","callerName":"Dana Ruiz","customerId":"c-1","jobId":"j-1","linkedAt":"2026-11-05T15:20:00Z","startedAt":"2026-11-05T15:12:00Z","endedAt":"2026-11-05T15:15:12Z","durationSeconds":192,"recording":{"status":"available","durationSeconds":190,"contentPath":"/v1/calls/00000000-0000-4000-8000-000000009702/recording"},"disclosure":"This call may be recorded.","summary":{"text":"Leak at the base.","reason":"Water heater leak","source":"model"},"transcriptStatus":"complete","futureField":1}],"nextCursor":"next"}"#
        let client = APIClient(session: URLProtocolFixture.session([.init(200, json)]), baseURL: "https://app.thorbis.com")
        let page = try await client.inboxCallLog()
        let request = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(request.url?.path, "/v1/calls")
        XCTAssertTrue(request.url?.query?.contains("limit=200") ?? false)
        XCTAssertEqual(page.nextCursor, "next")
        let call = try XCTUnwrap(page.items.first)
        XCTAssertEqual(call.direction, "inbound")
        XCTAssertEqual(call.lineId, "line-1")
        XCTAssertEqual(call.customerId, "c-1")
        XCTAssertEqual(call.jobId, "j-1")
        XCTAssertEqual(call.linkedAt, "2026-11-05T15:20:00Z")
        XCTAssertEqual(call.transcriptStatus, "complete")
        XCTAssertEqual(call.summary?.reason, "Water heater leak")
        XCTAssertEqual(call.summary?.source, "model")
        XCTAssertEqual(call.length, 190, "The recording's own length wins")
        XCTAssertNotNil(call.playablePath)
        XCTAssertNil(call.voicemail)
        XCTAssertTrue(call.transcript.isEmpty, "List items carry no transcript")
    }

    func testAnUnknownStatusStillDecodesAndReadsAsAnswered() throws {
        let odd = try call("x", status: "ringing")
        XCTAssertEqual(odd.kind, .answered)
    }

    // MARK: Classification

    func testMissedVoicemailAndOtherOutcomesAreNamed() throws {
        let missed = try call("1", status: "missed", duration: 0)
        XCTAssertEqual(missed.kind, .missed)
        XCTAssertEqual(missed.outcome, "Missed call")
        XCTAssertTrue(missed.kind.needsAttention)

        let voicemail = try call("2", status: "missed", duration: 42, voicemail: true)
        XCTAssertEqual(voicemail.kind, .voicemail, "Voicemail needs the explicit signal")
        XCTAssertEqual(voicemail.outcome, "Voicemail · 0:42")
        XCTAssertTrue(voicemail.kind.needsAttention)

        let answered = try call("3")
        XCTAssertEqual(answered.kind, .answered)
        XCTAssertEqual(answered.outcome, "Incoming · 3:12")
        XCTAssertFalse(answered.kind.needsAttention)

        XCTAssertEqual(try call("4", status: "in_progress", duration: nil).kind, .ongoing, "A call still going is not missed")
        XCTAssertEqual(try call("5", status: "failed").kind, .dropped)
        XCTAssertEqual(try call("6", status: "missed", voicemail: false).kind, .missed)
    }

    func testAnUnopenedMissedCallCarriesItsWordAndTheLineDoesNotRepeatIt() throws {
        let thread = CommsCallGrouping.threads([try call("a", status: "missed", name: "Marcus Bell", duration: 0)])[0]
        XCTAssertEqual(thread.alert(seen: [], in: .all), "Missed call")
        XCTAssertTrue(thread.unread(seen: []))
        XCTAssertEqual(thread.line(in: .all), "Missed call")
        XCTAssertEqual(thread.line(in: .all, alerted: true), "(555) 010-0100", "The number, formatted, stands in for what was said")
        XCTAssertEqual(CommsCallGrouping.display("+44 20 7946 0958"), "+44 20 7946 0958")
        XCTAssertNil(thread.alert(seen: ["a"], in: .all))
        XCTAssertFalse(thread.unread(seen: ["a"]))

        let voicemail = CommsCallGrouping.threads([try call("v", status: "missed", duration: 42, voicemail: true, summary: "Call me back")])[0]
        XCTAssertEqual(voicemail.alert(seen: [], in: .voicemail), "New voicemail")
        XCTAssertEqual(voicemail.line(in: .voicemail), "Voicemail · 0:42 · \u{201C}Call me back\u{201D}")
        XCTAssertEqual(voicemail.line(in: .voicemail, alerted: true), "0:42 · \u{201C}Call me back\u{201D}")
    }

    // MARK: Grouping

    func testCallsGroupByCallerDigitsNewestFirst() throws {
        let calls = [
            try call("old", number: "(555) 010-0100", name: "Dana Ruiz", at: "2026-11-02T10:00:00Z"),
            try call("new", number: "+15550100100", at: "2026-11-05T09:00:00Z"),
            try call("other", number: "+15550100142", at: "2026-11-04T09:00:00Z"),
            try call("anon1", number: nil, at: "2026-11-03T09:00:00Z"),
            try call("anon2", number: nil, at: "2026-11-01T09:00:00Z"),
            try call("new", number: "+15550100100", at: "2026-11-05T09:00:00Z"),
        ]
        let threads = CommsCallGrouping.threads(calls)
        XCTAssertEqual(threads.map(\.id), ["call-thread-5550100100", "call-thread-5550100142", "call-thread-anon1", "call-thread-anon2"])
        XCTAssertEqual(threads[0].calls.map(\.id), ["new", "old"], "One caller, newest call first, a repeated call counted once")
        XCTAssertEqual(threads[0].name, "Dana Ruiz", "A name from any call names the thread")
        XCTAssertEqual(threads[0].initials, "DR")
        XCTAssertEqual(threads[2].name, "Unknown caller")
        XCTAssertNil(threads[2].initials)
    }

    func testCompactAgeMatchesTheWeb() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func at(_ seconds: Double) -> String { ISO8601DateFormatter().string(from: now.addingTimeInterval(-seconds)) }
        XCTAssertEqual(CommsAge.compact(at(20), now: now), "now")
        XCTAssertEqual(CommsAge.compact(at(12 * 60), now: now), "12m")
        XCTAssertEqual(CommsAge.compact(at(3 * 3600), now: now), "3h")
        XCTAssertEqual(CommsAge.compact(at(4 * 86_400), now: now), "4d")
        XCTAssertEqual(CommsAge.compact(at(90 * 86_400), now: now), "3mo")
        XCTAssertEqual(CommsAge.compact(nil, now: now), "")
    }

    // MARK: Gating

    func testWhoSeesWhichSections() {
        let everything = CommsInboxAccess(notices: true, calls: true)
        XCTAssertTrue(everything.visible)
        XCTAssertEqual(everything.sections, [.all, .calls, .voicemail, .texts, .email, .notices])

        let noCalls = CommsInboxAccess(notices: true, calls: false)
        XCTAssertEqual(noCalls.sections, [.all, .texts, .email, .notices], "Without the call log there are no call sections")

        let callsOnly = CommsInboxAccess(notices: false, calls: true)
        XCTAssertEqual(callsOnly.sections, [.all, .calls, .voicemail, .texts, .email])

        let signedOut = CommsInboxAccess(workspace: false, notices: false, calls: false)
        XCTAssertFalse(signedOut.visible)
        XCTAssertEqual(signedOut.sections, [.all])
        XCTAssertTrue(CommsInboxAccess(workspace: false, notices: true, calls: false).visible)
    }

    // MARK: Folders and filters

    private func notice(_ id: String, read: Bool, at: String = "2026-11-05T12:00:00Z") -> StaffNotice {
        try! JSONDecoder().decode(StaffNotice.self, from: Data(#"{"id":"\#(id)","jobId":"j","title":"T","meta":"M","at":"\#(at)","read":\#(read)}"#.utf8))
    }

    func testSectionsFoldersAndFiltersPickTheirRows() throws {
        let threads = CommsCallGrouping.threads([try call("m", status: "missed", number: "+15550100142", at: "2026-11-05T14:00:00Z", duration: 0),
                                                 try call("c", at: "2026-11-05T13:00:00Z")])
        let store = CommsLocalStore(file: nil)
        let text = store.threadForPhone("(555) 010-0144", contactName: "Danielle")
        store.commitText(text, body: "On our way")
        let mail = try XCTUnwrap(store.commitMail(.init(to: ["a@example.com"], subject: "Hi", body: "Hello"), send: true))
        let notices = [notice("n1", read: false), notice("n2", read: true)]
        func ids(_ section: CommsInboxSection, _ folder: CommsFolder = .inbox, _ filter: CommsQuickFilter = .all) -> [String] {
            CommsInboxScope.items(section: section, folder: folder, filter: filter, calls: threads, local: store.threads,
                                  notices: notices, callFlags: store.callFlags, seen: []).map(\.id)
        }
        XCTAssertEqual(Set(ids(.all)), Set(["call-thread-5550100142", "call-thread-5550100100", text, mail, "notice-n1", "notice-n2"]))
        XCTAssertEqual(ids(.calls), ["call-thread-5550100142", "call-thread-5550100100"])
        XCTAssertEqual(ids(.texts), [text])
        XCTAssertEqual(ids(.email), [mail])
        XCTAssertEqual(ids(.notices), ["notice-n1", "notice-n2"])
        XCTAssertEqual(ids(.notices, .inbox, .unread), ["notice-n1"])
        XCTAssertEqual(Set(ids(.all, .inbox, .unread)), Set(["call-thread-5550100142", "notice-n1"]))
        XCTAssertEqual(ids(.all, .drafts), [text], "A draft text is in Drafts")
        XCTAssertEqual(ids(.all, .sent), [mail], "A queued email is in Sent")
        XCTAssertTrue(ids(.voicemail).isEmpty)

        store.archive("call-thread-5550100100")
        store.toggleStar(text)
        XCTAssertFalse(ids(.calls).contains("call-thread-5550100100"))
        XCTAssertEqual(ids(.calls, .archive), ["call-thread-5550100100"])
        XCTAssertEqual(ids(.all, .inbox, .starred), [text])
        XCTAssertTrue(ids(.all, .archive).allSatisfy { !$0.hasPrefix("notice-") }, "Notices live in the Inbox folder only")

        store.setUnread("call-thread-5550100142", false)
        XCTAssertFalse(ids(.calls, .inbox, .unread).contains("call-thread-5550100142"), "Mark read wins over an unopened missed call")
        XCTAssertEqual(CommsInboxScope.folders(.calls), [.inbox, .archive, .bin])
        XCTAssertEqual(CommsInboxScope.folders(.texts), [.inbox, .drafts, .sent, .archive, .bin])
        XCTAssertEqual(CommsInboxScope.filters(.notices), [.all, .unread])
    }

    // MARK: Texts and email on this device

    func testTextsNeverSendAndFindTheirThreadByDigits() {
        let store = CommsLocalStore(file: nil)
        let id = store.threadForPhone("+1 (555) 010-0144", contactName: "Danielle")
        XCTAssertEqual(store.thread(id)?.messages, [], "A new conversation starts empty")
        store.archive(id)
        XCTAssertEqual(store.threadForPhone("555-010-0144"), id, "The same number by digits")
        XCTAssertEqual(store.flags(id).place, .inbox, "Reaching it again brings it back to the Inbox")

        XCTAssertFalse(store.commitText(id, body: "   "))
        XCTAssertTrue(store.commitText(id, body: "On the way"))
        XCTAssertEqual(store.thread(id)?.messages.last?.status, .draft)
        XCTAssertTrue(store.commitText(id, body: "Tomorrow at 9", scheduledAt: Date().addingTimeInterval(3600)))
        let queued = store.thread(id)!.messages.last!
        XCTAssertEqual(queued.status, .queued)
        XCTAssertNotNil(queued.scheduledAt)
        store.cancelScheduled(id, messageID: queued.id)
        XCTAssertEqual(store.thread(id)?.messages.last?.status, .draft)
        XCTAssertNil(store.thread(id)?.messages.last?.scheduledAt)
        XCTAssertFalse(store.thread(id)!.messages.contains { $0.status == .received }, "Nothing reads as delivered")
    }

    func testEmailQueuesOrDraftsAndAnOnlyDraftDiscardsItsThread() throws {
        let store = CommsLocalStore(file: nil)
        XCTAssertNil(store.commitMail(.init(to: [" "], subject: "", body: "x"), send: true), "An email needs someone to go to")
        let id = try XCTUnwrap(store.commitMail(.init(to: ["a@example.com"], cc: ["b@example.com"], subject: "", body: "Hi"), send: false))
        let draft = try XCTUnwrap(store.thread(id)?.messages.first)
        XCTAssertEqual(draft.status, .draft)
        XCTAssertEqual(draft.subject, "(no subject)")
        XCTAssertEqual(draft.cc, ["b@example.com"])
        store.commitMail(.init(to: ["a@example.com"], subject: "Visit", body: "Hello"), send: true, threadID: id, editing: draft.id)
        XCTAssertEqual(store.thread(id)?.messages.count, 1, "Editing replaces the draft")
        XCTAssertEqual(store.thread(id)?.messages.first?.status, .queued)

        let other = try XCTUnwrap(store.commitMail(.init(to: ["c@example.com"], subject: "S", body: "B"), send: false))
        store.discardDraft(other, messageID: store.thread(other)!.messages[0].id)
        XCTAssertNil(store.thread(other))
    }

    func testCannedRepliesAndSegments() {
        let store = CommsLocalStore(file: nil)
        XCTAssertEqual(store.cannedReplies.map(\.name), ["On the way", "Running late", "Invoice sent"])
        store.saveCannedReply(name: "", body: "Gate code please")
        XCTAssertEqual(store.cannedReplies.last?.name, "Gate code please")
        store.deleteCannedReply("on-the-way")
        XCTAssertFalse(store.cannedReplies.contains { $0.id == "on-the-way" })
        XCTAssertEqual(CommsSMS.segments(""), 0)
        XCTAssertEqual(CommsSMS.segments(String(repeating: "a", count: 160)), 1)
        XCTAssertEqual(CommsSMS.segments(String(repeating: "a", count: 161)), 2)
        XCTAssertEqual(CommsSMS.counter("hi"), "2 characters · 1 SMS")
        XCTAssertNil(CommsSMS.counter(""))
    }

    func testTheStoreKeepsConversationsInItsFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("inbox-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = CommsLocalStore(file: file)
        let id = store.threadForPhone("5550100144")
        store.setComposing(id, "half written")
        store.toggleStar("call-thread-5550100100")
        store.saveCannedReply(name: "Mine", body: "Body")
        let reopened = CommsLocalStore(file: file)
        XCTAssertEqual(reopened.thread(id)?.composing, "half written")
        XCTAssertNotNil(reopened.callFlags["call-thread-5550100100"]?.starredAt)
        XCTAssertEqual(reopened.cannedReplies.last?.name, "Mine")
        XCTAssertTrue(reopened.thread(id)?.hasDraft ?? false)
    }

    func testCallSeenIsPerPersonAndWorkspace() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "comms-seen-\(UUID().uuidString)"))
        let seen = CommsCallSeen(defaults: defaults, actorID: "a", organizationID: "o")
        seen.markSeen([try call("x", status: "missed")])
        XCTAssertEqual(CommsCallSeen(defaults: defaults, actorID: "a", organizationID: "o").ids, ["x"])
        XCTAssertTrue(CommsCallSeen(defaults: defaults, actorID: "b", organizationID: "o").ids.isEmpty)
    }

    func testDraftsRowLeadsWithTheDraft() {
        let received = CommsLocalMessage(id: "1", channel: .sms, direction: .outbound, at: "2026-11-05T07:04:00Z",
                                         body: "Confirming tomorrow 9-11.", status: .draft)
        let reply = CommsLocalMessage(id: "2", channel: .sms, direction: .inbound, at: "2026-11-05T09:32:00Z",
                                      body: "Thanks!", status: .received)
        var thread = CommsLocalThread(id: "t", contactName: "Dana", phone: "5550100", channel: .sms, unread: false,
                                      flags: CommsThreadFlags(), messages: [received, reply], composing: nil)
        XCTAssertEqual(thread.line, "Thanks!")
        XCTAssertEqual(thread.line(in: .inbox), "Thanks!")
        XCTAssertEqual(thread.line(in: .drafts), "Draft: Confirming tomorrow 9-11.")
        thread.composing = "On my way"
        XCTAssertEqual(thread.line(in: .drafts), "Draft: On my way")
    }
}
