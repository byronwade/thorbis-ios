import XCTest
@testable import Thorbis

@MainActor
final class CommsInboxTests: XCTestCase {
    func testTextPresenterReportsUnavailableInboxInsteadOfFallingBackToMessages() {
        let actor = UUID().uuidString, organization = UUID().uuidString
        let store = CommsLocalStore.shared(actorID: actor, organizationID: organization)
        store.invalidate()
        let presenter = InboxTextPresenter()
        presenter.bind(actorID: actor, organizationID: organization)
        XCTAssertTrue(presenter.open(phone: "5550100100", name: nil), "The action is handled by the inbox, not handed off to Messages")
        XCTAssertTrue(presenter.storageUnavailable)
        XCTAssertNil(presenter.opening)
    }
    func testTextCommitDoesNotClaimSuccessWhenDiskWriteFails() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let active = root.appendingPathComponent("active", isDirectory: true)
        let retained = root.appendingPathComponent("retained", isDirectory: true)
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CommsLocalStore(file: active.appendingPathComponent("inbox.json"), requiresPersistence: true)
        let id = try XCTUnwrap(store.threadForPhone("5550100100"))
        store.setComposing(id, "Keep this draft")
        let saved = try Data(contentsOf: active.appendingPathComponent("inbox.json"))
        try FileManager.default.moveItem(at: active, to: retained)

        XCTAssertFalse(store.commitText(id, body: "Keep this draft"), "A failed write must never be reported as a saved draft")
        XCTAssertEqual(store.thread(id)?.composing, "Keep this draft", "The text must remain recoverable in the open composer")
        XCTAssertTrue(store.thread(id)?.messages.isEmpty == true, "A failed commit must not create a misleading saved message")
        XCTAssertEqual(try Data(contentsOf: retained.appendingPathComponent("inbox.json")), saved)
    }

    func testComposingWriteFailureKeepsTextInMemoryAndBlocksFurtherWrites() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let active = root.appendingPathComponent("active", isDirectory: true)
        let retained = root.appendingPathComponent("retained", isDirectory: true)
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CommsLocalStore(file: active.appendingPathComponent("inbox.json"), requiresPersistence: true)
        let id = try XCTUnwrap(store.threadForPhone("5550100100"))
        let saved = try Data(contentsOf: active.appendingPathComponent("inbox.json"))
        try FileManager.default.moveItem(at: active, to: retained)

        store.setComposing(id, "Unsaved text")
        XCTAssertEqual(store.thread(id)?.composing, "Unsaved text")
        XCTAssertTrue(store.storageBlocked, "An uncertain disk write must stop subsequent writes")
        XCTAssertFalse(store.commitText(id, body: "Unsaved text"))
        XCTAssertEqual(try Data(contentsOf: retained.appendingPathComponent("inbox.json")), saved)
    }

    func testCannedReplyWriteFailureDoesNotPublishAnUnsavedReply() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let active = root.appendingPathComponent("active", isDirectory: true)
        let retained = root.appendingPathComponent("retained", isDirectory: true)
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CommsLocalStore(file: active.appendingPathComponent("inbox.json"), requiresPersistence: true)
        _ = try XCTUnwrap(store.threadForPhone("5550100100"))
        let saved = try Data(contentsOf: active.appendingPathComponent("inbox.json"))
        try FileManager.default.moveItem(at: active, to: retained)
        store.saveCannedReply(name: "Visit", body: "Keep these words")
        XCTAssertTrue(store.storageBlocked)
        XCTAssertFalse(store.cannedReplies.contains { $0.body == "Keep these words" })
        XCTAssertEqual(try Data(contentsOf: retained.appendingPathComponent("inbox.json")), saved)
    }

    func testClearingComposerAfterCommitDoesNotWriteAgain() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let active = root.appendingPathComponent("active", isDirectory: true)
        let retained = root.appendingPathComponent("retained", isDirectory: true)
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CommsLocalStore(file: active.appendingPathComponent("inbox.json"), requiresPersistence: true)
        let id = try XCTUnwrap(store.threadForPhone("5550100100"))
        store.setComposing(id, "Saved once")
        XCTAssertTrue(store.commitText(id, body: "Saved once"))
        try FileManager.default.moveItem(at: active, to: retained)
        store.setComposing(id, "")
        XCTAssertFalse(store.storageBlocked, "Clearing the field after a successful commit is not another disk write")
        XCTAssertEqual(store.thread(id)?.messages.last?.body, "Saved once")
    }

    func testNewTextWithUnavailableStorageStaysInMemoryWithoutClaimingSave() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("missing/inbox.json")
        let store = CommsLocalStore(file: file, requiresPersistence: true)
        let id = try XCTUnwrap(store.threadForPhone("5550100100"))
        XCTAssertTrue(store.storageBlocked)
        store.setComposing(id, "Copy these words")
        XCTAssertEqual(store.thread(id)?.composing, "Copy these words")
        XCTAssertEqual(store.threadForPhone("5550100100"), id, "An existing unsaved conversation must remain available for recovery")
        XCTAssertFalse(store.commitText(id, body: "Copy these words"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testArchiveAndBinReportFailureWithoutChangingTheThread() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let active = root.appendingPathComponent("active", isDirectory: true)
        let retained = root.appendingPathComponent("retained", isDirectory: true)
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CommsLocalStore(file: active.appendingPathComponent("inbox.json"), requiresPersistence: true)
        let id = try XCTUnwrap(store.threadForPhone("5550100100"))
        let saved = try Data(contentsOf: active.appendingPathComponent("inbox.json"))
        try FileManager.default.moveItem(at: active, to: retained)
        XCTAssertFalse(store.archive(id), "A fresh failed write must not dismiss the conversation")
        XCTAssertEqual(store.flags(id).place, .inbox)
        XCTAssertFalse(store.bin(id), "A blocked store must not dismiss the conversation")
        XCTAssertEqual(store.flags(id).place, .inbox)
        XCTAssertEqual(try Data(contentsOf: retained.appendingPathComponent("inbox.json")), saved)
    }

    func testEmailOpeningKeepsExistingDraftAndRetiresStaleIdentity() throws {
        let presenter = InboxEmailPresenter()
        var current = true
        let firstGeneration = UUID()
        presenter.bind(actorID: "00000000-0000-4000-8000-000000000001", organizationID: "00000000-0000-4000-8000-000000000002", origin: "https://app.thorbis.com", generation: firstGeneration, current: { current })
        let first = try XCTUnwrap(MailDraft(recipient: "first@example.com"))
        let second = try XCTUnwrap(MailDraft(recipient: "second@example.com"))
        presenter.open(first, context: "customer:one")
        let original = try XCTUnwrap(presenter.opening)
        presenter.open(second, context: "customer:two")
        XCTAssertEqual(presenter.opening?.id, original.id, "A second action cannot replace an unsaved composer")
        XCTAssertEqual(presenter.opening?.mail.recipient, "first@example.com")
        current = false
        XCTAssertFalse(presenter.isCurrent(original), "A sheet cannot display under retired authority")
        presenter.open(second, context: "customer:two")
        XCTAssertNil(presenter.opening, "A stale session cannot open or retain an email")
        current = true
        presenter.bind(actorID: "00000000-0000-4000-8000-000000000003", organizationID: "00000000-0000-4000-8000-000000000004", origin: "https://app.thorbis.com", generation: UUID(), current: { current })
        presenter.open(second, context: "customer:two")
        let newer = try XCTUnwrap(presenter.opening)
        presenter.close(original.id)
        XCTAssertEqual(presenter.opening?.id, newer.id, "An old sheet callback cannot close a new scope")
        presenter.unbind()
        XCTAssertNil(presenter.opening)
    }

    func testMailtoSeedPreservesAllFieldsAndRejectsUnsupportedHeaders() throws {
        let original = try XCTUnwrap(MailDraft(recipients: ["first@example.com", "second@example.com"],
            cc: ["copy@example.com"], bcc: ["private@example.com"], subject: "Job & estimate", body: "First\nSecond & final"))
        let roundTrip = try XCTUnwrap(MailDraft(mailtoURL: XCTUnwrap(original.mailtoURL)))
        let draft = CommsMailDraft(mail: roundTrip)
        XCTAssertEqual(draft.to, "first@example.com, second@example.com")
        XCTAssertEqual(draft.cc, "copy@example.com")
        XCTAssertEqual(draft.bcc, "private@example.com")
        XCTAssertEqual(draft.subject, "Job & estimate")
        XCTAssertEqual(draft.body, "First\nSecond & final")
        XCTAssertNil(MailDraft(mailtoURL: try XCTUnwrap(URL(string: "mailto:first@example.com?x-extra=secret"))))
        XCTAssertNil(MailDraft(mailtoURL: try XCTUnwrap(URL(string: "mailto:first@example.com?subject=one&subject=two"))))
    }

    func testEmailRecoveryIsDeviceScopedAndIsolatedByIdentityAndOrigin() throws {
        let actor = UUID().uuidString, otherActor = UUID().uuidString, org = UUID().uuidString
        let initial = try XCTUnwrap(MailDraft(recipient: "customer@example.com", subject: "Visit"))
        let namespace = UUID().uuidString
        func scope(_ actor: String, _ origin: String) throws -> CommsEmailRecoveryScope {
            try XCTUnwrap(CommsEmailRecoveryScope(actorID: actor, organizationID: org, origin: origin, context: "job:one", namespace: namespace))
        }
        let owner = try scope(actor, "https://app.thorbis.com")
        let wrongActor = try scope(otherActor, "https://app.thorbis.com")
        let wrongOrigin = try scope(actor, "http://localhost:8787")
        let wrongJob = try XCTUnwrap(CommsEmailRecoveryScope(actorID: actor, organizationID: org,
            origin: "https://app.thorbis.com", context: "job:two", namespace: namespace))
        XCTAssertFalse(owner.account.contains("customer@example.com"))
        XCTAssertNotEqual(owner, wrongActor); XCTAssertNotEqual(owner, wrongOrigin); XCTAssertNotEqual(owner, wrongJob)
        let store = KeychainCommsEmailRecoveryStore.shared
        defer { try? store.remove(scope: owner) }
        var draft = CommsMailDraft(mail: initial); draft.cc = "copy@example.com"; draft.bcc = "private@example.com"; draft.body = "Private details"
        try store.save(CommsEmailRecovery(draft), scope: owner)
        XCTAssertEqual(try store.load(scope: owner), CommsEmailRecovery(draft))
        XCTAssertNil(try store.load(scope: wrongActor)); XCTAssertNil(try store.load(scope: wrongOrigin)); XCTAssertNil(try store.load(scope: wrongJob))
        try store.remove(scope: owner)
        XCTAssertNil(try store.load(scope: owner))
    }

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

    func testInvalidatedStoreClearsMemoryAndRejectsLateDraftWrites() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = CommsLocalStore(file: file)
        let mail = CommsLocalStore.Mail(to: ["customer@example.com"], subject: "Visit", body: "private details")
        XCTAssertNotNil(store.commitMail(mail, send: false))
        let snapshot = try Data(contentsOf: file)
        store.invalidate()
        XCTAssertFalse(store.isActive)
        XCTAssertTrue(store.threads.isEmpty)
        XCTAssertNil(store.commitMail(mail, send: false))
        XCTAssertNil(store.threadForPhone("5550100100"))
        store.toggleStar("late-call")
        XCTAssertTrue(store.callFlags.isEmpty)
        store.saveCannedReply(name: "Private", body: "private details")
        XCTAssertFalse(store.cannedReplies.contains(where: { $0.body == "private details" }))
        XCTAssertEqual(try Data(contentsOf: file), snapshot, "A stale view must not write after sign-out")
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
        let text = try XCTUnwrap(store.threadForPhone("(555) 010-0144", contactName: "Danielle"))
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

    func testTextsNeverSendAndFindTheirThreadByDigits() throws {
        let store = CommsLocalStore(file: nil)
        let id = try XCTUnwrap(store.threadForPhone("+1 (555) 010-0144", contactName: "Danielle"))
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

    func testEmailDraftCanBeSavedBeforeChoosingRecipient() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = CommsLocalStore(file: file)
        let initial = CommsLocalStore.Mail(to: [], subject: "Visit", body: "Work summary")
        let threadID = try XCTUnwrap(store.commitMail(initial, send: false))
        let reloaded = CommsLocalStore(file: file)
        let original = try XCTUnwrap(reloaded.thread(threadID))
        XCTAssertEqual(original.recipientlessDraft, true)
        let draft = try XCTUnwrap(original.messages.first)
        XCTAssertEqual(draft.status, .draft)
        XCTAssertEqual(original.contactName, "Draft email")
        XCTAssertNil(original.email)
        XCTAssertNil(reloaded.commitMail(initial, send: true, threadID: threadID, editing: draft.id, expected: initial))
        let updated = CommsLocalStore.Mail(to: ["customer@example.com"], subject: "Visit", body: "Work summary")
        XCTAssertEqual(reloaded.commitMail(updated, send: false, threadID: threadID, editing: draft.id, expected: initial), threadID)
        let saved = try XCTUnwrap(reloaded.thread(threadID))
        XCTAssertEqual(saved.messages.count, 1)
        XCTAssertEqual(saved.messages.first?.to, ["customer@example.com"])
        XCTAssertEqual(saved.email, "customer@example.com")
        XCTAssertEqual(saved.contactName, "customer@example.com")
        XCTAssertEqual(reloaded.commitMail(initial, send: false, threadID: threadID, editing: draft.id, expected: updated), threadID)
        XCTAssertNil(reloaded.thread(threadID)?.email)
        XCTAssertEqual(reloaded.thread(threadID)?.contactName, "Draft email")
    }

    func testOlderConversationSnapshotWithoutDraftMarkerStillDecodes() throws {
        let thread = CommsLocalThread(id: "old", contactName: "Customer", phone: "", email: "customer@example.com", channel: .email, subject: nil, unread: false, flags: CommsThreadFlags(), messages: [], composing: nil)
        let encoded = try JSONEncoder().encode(thread)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "recipientlessDraft")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(CommsLocalThread.self, from: legacy)
        XCTAssertEqual(decoded.contactName, "Customer")
        XCTAssertNil(decoded.recipientlessDraft)
    }

    func testEditingExistingEmailDoesNotReplaceItsContactAssociation() throws {
        let store = CommsLocalStore(file: nil)
        let original = CommsLocalStore.Mail(to: ["original@example.com"], subject: "Visit", body: "Hi")
        let id = try XCTUnwrap(store.commitMail(original, send: false))
        let message = try XCTUnwrap(store.thread(id)?.messages.first)
        let changed = CommsLocalStore.Mail(to: ["other@example.com"], subject: "Visit", body: "Updated")
        XCTAssertEqual(store.commitMail(changed, send: false, threadID: id, editing: message.id, expected: original), id)
        XCTAssertEqual(store.thread(id)?.contactName, "original@example.com")
        XCTAssertEqual(store.thread(id)?.email, "original@example.com")
        XCTAssertEqual(store.thread(id)?.messages.first?.to, ["other@example.com"])
    }

    func testEmailRecoveryCopyIncludesAllEnteredFields() {
        var draft = CommsMailDraft(to: "customer@example.com", subject: "Visit")
        draft.cc = "office@example.com"
        draft.bcc = "private@example.com"
        draft.body = "Scope details"
        XCTAssertEqual(draft.recoveryText, "To: customer@example.com\nCc: office@example.com\nBcc: private@example.com\nSubject: Visit\n\nScope details")
    }

    func testEmailSaveFailureDoesNotPublishDraftOrClaimSuccess() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = parent.appendingPathComponent("inbox.json") // The parent deliberately does not exist.
        let store = CommsLocalStore(file: file)
        let draft = CommsLocalStore.Mail(to: ["a@example.com"], subject: "Visit", body: "Keep my words")
        XCTAssertNil(store.commitMail(draft, send: false))
        XCTAssertEqual(store.lastMailSaveFailure, .storage)
        XCTAssertTrue(store.threads.isEmpty)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        XCTAssertNil(store.commitMail(draft, send: false), "An uncertain write must not be retried blindly")
        XCTAssertNil(store.threadForPhone("5550100100"))
        let reloaded = CommsLocalStore(file: file)
        let id = try XCTUnwrap(reloaded.commitMail(draft, send: false))
        XCTAssertNil(reloaded.lastMailSaveFailure)
        XCTAssertEqual(CommsLocalStore(file: file).thread(id)?.messages.first?.body, "Keep my words")
    }

    func testMissingPersistentStorageCannotClaimEmailSave() {
        let store = CommsLocalStore(file: nil, requiresPersistence: true)
        let draft = CommsLocalStore.Mail(to: [], subject: "Visit", body: "Keep my words")
        XCTAssertNil(store.commitMail(draft, send: false))
        XCTAssertEqual(store.lastMailSaveFailure, .storage)
        XCTAssertTrue(store.threads.isEmpty)
    }

    func testUnreadableSnapshotIsNotOverwrittenAsEmptyInbox() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let corrupt = Data("{not a valid inbox".utf8)
        try corrupt.write(to: file)
        let store = CommsLocalStore(file: file, requiresPersistence: true)
        XCTAssertTrue(store.storageBlocked)
        let draft = CommsLocalStore.Mail(to: ["a@example.com"], subject: "Visit", body: "New")
        XCTAssertNil(store.commitMail(draft, send: false))
        XCTAssertNil(store.threadForPhone("5550100100"))
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }

    func testStaleEmailEditorCannotOverwriteOrResurrectDraft() throws {
        let store = CommsLocalStore(file: nil)
        let original = CommsLocalStore.Mail(to: ["a@example.com"], subject: "Visit", body: "First")
        let id = try XCTUnwrap(store.commitMail(original, send: false))
        let message = try XCTUnwrap(store.thread(id)?.messages.first)
        let newer = CommsLocalStore.Mail(to: ["a@example.com"], subject: "Visit", body: "Newer edit")
        XCTAssertEqual(store.commitMail(newer, send: false, threadID: id, editing: message.id, expected: original), id)
        let stale = CommsLocalStore.Mail(to: ["a@example.com"], subject: "Visit", body: "Stale edit")
        XCTAssertNil(store.commitMail(stale, send: false, threadID: id, editing: message.id, expected: original))
        XCTAssertEqual(store.thread(id)?.messages.first?.body, "Newer edit")
        store.discardDraft(id, messageID: message.id)
        XCTAssertNil(store.commitMail(stale, send: false, threadID: id, editing: message.id, expected: original))
        XCTAssertNil(store.commitMail(stale, send: false, threadID: id), "A reply cannot silently create a new thread")
        XCTAssertNil(store.thread(id))
        XCTAssertTrue(store.threads.isEmpty)
    }

    func testEmailQueuesOrDraftsAndAnOnlyDraftDiscardsItsThread() throws {
        let store = CommsLocalStore(file: nil)
        XCTAssertNil(store.commitMail(.init(to: [" "], subject: "", body: "x"), send: true), "An email needs someone to go to")
        let id = try XCTUnwrap(store.commitMail(.init(to: ["a@example.com"], cc: ["b@example.com"], subject: "", body: "Hi"), send: false))
        let draft = try XCTUnwrap(store.thread(id)?.messages.first)
        XCTAssertEqual(draft.status, .draft)
        XCTAssertEqual(draft.subject, "(no subject)")
        XCTAssertEqual(draft.cc, ["b@example.com"])
        store.commitMail(.init(to: ["a@example.com"], subject: "Visit", body: "Hello"), send: true, threadID: id, editing: draft.id, expected: .init(to: ["a@example.com"], cc: ["b@example.com"], subject: "", body: "Hi"))
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
        let id = try XCTUnwrap(store.threadForPhone("5550100144"))
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
