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
        // design 2026-10-30: the list system — each draft a row with its state as a word; its
        // actions (Edit, Discard, Cancel schedule) moved into the row's ••• menu; New draft is the commit.
        let bound = inbox.actorID == actorID && inbox.organizationID == organizationID
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Message drafts").font(Theme.font(30, weight: .medium)).tracking(-0.6)
                        .accessibilityAddTraits(.isHeader)
                    Text("On this device · Current session only").font(Theme.font(15)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
                if let actionError {
                    Text(actionError).font(Theme.font(15)).foregroundStyle(Theme.destructive)
                        .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
                }
                if bound {
                    PaperSection("Drafts and queued", count: inbox.messages.isEmpty ? nil : inbox.messages.count) {
                        if inbox.messages.isEmpty {
                            Text("No drafts in this session").font(Theme.font(15)).foregroundStyle(Theme.muted)
                                .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 14)
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(inbox.messages) { message in
                                    HStack(alignment: .top, spacing: 0) {
                                        PaperListRow(title: message.recipient,
                                                     subtitle: [message.channel == .email && !message.subject.isEmpty ? message.subject : nil, message.body]
                                                         .compactMap { $0 }.joined(separator: " · "),
                                                     meta: message.scheduledAt.map { "Scheduled locally for \($0) · Will not auto-send" },
                                                     subtitleLines: 2) {
                                            StatusWord(text: message.status.rawValue.capitalized,
                                                       tint: message.scheduledAt != nil ? Theme.warning : nil)
                                        }
                                        let items: [ThorbisMenuItem] = message.status == .draft
                                            ? [ThorbisMenuItem("Edit", icon: "pencil") { present(InboxComposer(message: message)) },
                                               ThorbisMenuItem("Discard", icon: "trash", role: .destructive) { inbox.discard(message.id) }]
                                            : message.scheduledAt != nil
                                                ? [ThorbisMenuItem("Cancel schedule", icon: "xmark.circle") { inbox.cancelScheduled(message.id) }]
                                                : []
                                        if !items.isEmpty {
                                            ThorbisMenu(items: items, accessibilityLabel: "Options for the draft to \(message.recipient)") {
                                                Image(systemName: "ellipsis").foregroundStyle(Theme.muted)
                                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                                            }
                                            .padding(.trailing, 4).padding(.top, 4)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, PaperCardMetrics.edge)
                        }
                    }
                }
                Text("Drafts and queued messages are not sent. Scheduling here does not start a timer or notify the recipient.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
            }
            .paperCardMargin().padding(.top, 8).padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            PaperActionBar(title: "New draft", symbol: "square.and.pencil", disabled: !bound) { present(InboxComposer()) }
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
            // design 2026-10-30: one column, labels above, field wells; Save draft is the ink
            // commit, Queue locally the quiet text action beside it (was the bottom toolbar).
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PaperFormField("Channel") {
                        ThorbisSelect(options: InboxLocalMessage.Channel.allCases.map { ($0, $0.rawValue) },
                                      selection: $composer.channel, label: "Channel").fieldWell()
                    }
                    PaperFormField(composer.channel == .sms ? "Phone number" : "Email address") {
                        TextField(composer.channel == .sms ? "Phone number" : "Email address", text: $composer.recipient)
                            .textInputAutocapitalization(.never).font(Theme.font(16)).fieldWell()
                    }
                    if composer.channel == .email {
                        PaperFormField("Subject") { TextField("Subject", text: $composer.subject).font(Theme.font(16)).fieldWell() }
                    }
                    PaperFormField("Message") {
                        TextEditor(text: $composer.body).font(Theme.font(16)).scrollContentBackground(.hidden)
                            .frame(minHeight: 130).padding(8)
                            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    }
                    if composer.channel == .sms {
                        PaperFormField("Optional local schedule") {
                            VStack(spacing: 0) {
                                Toggle("Queue for a time", isOn: $composer.scheduleText).font(Theme.font(16)).tint(Theme.brand)
                                    .frame(minHeight: 44)
                                if composer.scheduleText {
                                    DatePicker("Intended time", selection: $composer.scheduledDate).font(Theme.font(16))
                                        .frame(minHeight: 44)
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 2)
                            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                        }
                    }
                    Text("Queued means held on this screen. No message will be delivered or sent automatically.")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    if let error { Text(error).font(Theme.font(15)).foregroundStyle(Theme.destructive) }
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle("Compose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ThorbisToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    PaperActionBar(title: "Save draft") { save(.draft) }
                    Button { save(.queue) } label: {
                        Text(composer.channel == .sms ? "Queue locally" : "Queue email locally")
                            .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(PressStyle())
                    .disabled(composer.channel == .sms && !composer.scheduleText)
                    .background(Theme.background)
                }
            }
        }
    }

    private func save(_ mode: InboxLocalDrafts.Mode) {
        do { try onSave(composer, mode); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
