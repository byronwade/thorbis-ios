import SwiftUI

/// Mirrors the web Inbox honesty contract: authored messages are draft or queued only.
/// There is no transport, scheduler, provider receipt, or persisted sent history.
struct InboxLocalMessage: Identifiable, Equatable {
    enum Channel: String, CaseIterable { case sms = "Text", email = "Email" }
    enum Status: String { case draft, queued }
    let id: String
    var channel: Channel
    var recipient: String
    var subject: String
    var body: String
    var status: Status
    var scheduledAt: String?
    let createdAt: String
}

@MainActor
final class InboxLocalDrafts: ObservableObject {
    enum Mode { case draft, queue }
    @Published private(set) var actorID: String?
    @Published private(set) var organizationID: String?
    @Published private(set) var messages: [InboxLocalMessage] = []

    func bind(actorID: String, organizationID: String) {
        guard self.actorID != actorID || self.organizationID != organizationID else { return }
        clear()
        self.actorID = actorID
        self.organizationID = organizationID
    }

    /// Call synchronously on session invalidation; reinjection of an old actor stays empty.
    func clear() {
        messages = []
        actorID = nil
        organizationID = nil
    }

    @discardableResult
    func save(id: String = UUID().uuidString, channel: InboxLocalMessage.Channel,
              recipient: String, subject: String, body: String, mode: Mode,
              scheduledAt: String? = nil) throws -> InboxLocalMessage {
        guard actorID != nil, organizationID != nil else {
            throw Problem(title: "Inbox session unavailable", status: nil, detail: nil)
        }
        let recipient = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recipient.isEmpty, !body.isEmpty else {
            throw Problem(title: "Recipient and message are required", status: nil, detail: nil)
        }
        if channel == .sms && mode == .queue && scheduledAt == nil {
            throw Problem(title: "Text queue requires a scheduled time", status: nil,
                          detail: "Text drafts cannot be sent from this device.")
        }
        let existing = messages.first { $0.id == id }
        guard existing?.status != .queued else {
            throw Problem(title: "Queued message cannot be edited", status: nil, detail: nil)
        }
        let message = InboxLocalMessage(
            id: id, channel: channel, recipient: recipient, subject: channel == .email ? subject.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            body: body, status: mode == .queue ? .queued : .draft,
            scheduledAt: mode == .queue && channel == .sms ? scheduledAt : nil,
            createdAt: existing?.createdAt ?? ISO8601DateFormatter().string(from: Date()))
        messages.removeAll { $0.id == id }
        messages.insert(message, at: 0)
        return message
    }

    func cancelScheduled(_ id: String) {
        guard let index = messages.firstIndex(where: { $0.id == id && $0.status == .queued && $0.scheduledAt != nil }) else { return }
        messages[index].status = .draft
        messages[index].scheduledAt = nil
    }

    func discard(_ id: String) { messages.removeAll { $0.id == id && $0.status == .draft } }
}

private struct InboxComposer: Identifiable {
    let id: String
    var channel: InboxLocalMessage.Channel
    var recipient: String
    var subject: String
    var body: String
    var scheduleText: Bool
    var scheduledDate: Date

    init(message: InboxLocalMessage? = nil) {
        id = message?.id ?? UUID().uuidString
        channel = message?.channel ?? .sms
        recipient = message?.recipient ?? ""
        subject = message?.subject ?? ""
        body = message?.body ?? ""
        scheduleText = false
        scheduledDate = Date().addingTimeInterval(3_600)
    }
}

/// A session-only draft board. Rebinding to a new actor/workspace clears authored content.
struct InboxLocalDraftView: View {
    let actorID: String
    let organizationID: String
    @EnvironmentObject private var inbox: InboxLocalDrafts
    @State private var composer: InboxComposer?
    @State private var composerOwner: String?
    @State private var actionError: String?

    private var identityKey: String { "\(actorID.lowercased())|\(organizationID.lowercased())" }

    private func present(_ draft: InboxComposer) {
        composerOwner = identityKey
        composer = draft
    }

    var body: some View {
        List {
            Section {
                Text("On this device · Current session only")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Drafts and queued messages are not sent. Scheduling here does not start a timer or notify the recipient.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let actionError { Text(actionError).foregroundStyle(.red) }
            if inbox.actorID == actorID && inbox.organizationID == organizationID {
                Section("Drafts and queued") {
                    ForEach(inbox.messages) { message in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(message.recipient).font(.headline)
                                Spacer()
                                Text(message.status.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                            }
                            if message.channel == .email && !message.subject.isEmpty { Text(message.subject) }
                            Text(message.body).lineLimit(2).font(.subheadline).foregroundStyle(.secondary)
                            if let scheduledAt = message.scheduledAt {
                                Text("Scheduled locally for \(scheduledAt) · Will not auto-send")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            HStack {
                                if message.status == .draft {
                                    Button("Edit") { present(InboxComposer(message: message)) }
                                    Button("Discard", role: .destructive) { inbox.discard(message.id) }
                                } else if message.scheduledAt != nil {
                                    Button("Cancel schedule") { inbox.cancelScheduled(message.id) }
                                }
                            }.buttonStyle(.borderless)
                        }
                    }
                    if inbox.messages.isEmpty { Text("No drafts in this session").foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("Inbox drafts")
        .toolbar {
            Button("Compose", systemImage: "square.and.pencil") { present(InboxComposer()) }
                .disabled(inbox.actorID != actorID || inbox.organizationID != organizationID)
        }
        .task(id: identityKey) {
            composer = nil
            composerOwner = nil
            actionError = nil
            inbox.bind(actorID: actorID, organizationID: organizationID)
        }
        .sheet(item: $composer) { editing in
            if composerOwner == identityKey && inbox.actorID == actorID && inbox.organizationID == organizationID {
                InboxLocalComposerView(composer: editing) { saved, mode in
                    guard composerOwner == identityKey && inbox.actorID == actorID && inbox.organizationID == organizationID else {
                        throw Problem(title: "Session changed", status: nil, detail: nil)
                    }
                    let scheduled = saved.channel == .sms && mode == .queue && saved.scheduleText
                        ? ISO8601DateFormatter().string(from: saved.scheduledDate) : nil
                    try inbox.save(id: saved.id, channel: saved.channel, recipient: saved.recipient,
                                   subject: saved.subject, body: saved.body, mode: mode, scheduledAt: scheduled)
                    actionError = nil
                }
            } else {
                Text("Session changed").foregroundStyle(.secondary)
            }
        }
    }
}

private struct InboxLocalComposerView: View {
    @State var composer: InboxComposer
    let onSave: (InboxComposer, InboxLocalDrafts.Mode) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Message") {
                    Picker("Channel", selection: $composer.channel) {
                        ForEach(InboxLocalMessage.Channel.allCases, id: \.self) { channel in
                            Text(channel.rawValue).tag(channel)
                        }
                    }
                    TextField(composer.channel == .sms ? "Phone number" : "Email address", text: $composer.recipient)
                        .textInputAutocapitalization(.never)
                    if composer.channel == .email { TextField("Subject", text: $composer.subject) }
                    TextEditor(text: $composer.body).frame(minHeight: 130)
                }
                if composer.channel == .sms {
                    Section("Optional local schedule") {
                        Toggle("Queue for a time", isOn: $composer.scheduleText)
                        if composer.scheduleText { DatePicker("Intended time", selection: $composer.scheduledDate) }
                    }
                }
                Text("Queued means held on this screen. No message will be delivered or sent automatically.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Compose")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save draft") { save(.draft) }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(composer.channel == .sms ? "Queue locally" : "Queue email locally") { save(.queue) }
                        .disabled(composer.channel == .sms && !composer.scheduleText)
                }
            }
        }
    }

    private func save(_ mode: InboxLocalDrafts.Mode) {
        do { try onSave(composer, mode); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
