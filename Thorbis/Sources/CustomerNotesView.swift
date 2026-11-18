import SwiftUI

/// Paper 48N › Notes: what this workspace wrote about the customer on this phone, newest first,
/// with Add, Edit and Delete; then the notes the server holds on the customer's places, to read.
struct CustomerNotesSection: View {
    let customerID: String
    let customerName: String
    let locations: [ServiceLocationRecord]
    @ObservedObject var model: CustomerNotesModel
    @EnvironmentObject private var session: SessionController
    @State private var editing: CustomerNoteEditing?
    @State private var removing: CustomerPhoneNote?
    @State private var problem: String?

    private var placeNotes: [ServiceLocationRecord] {
        locations.filter { !($0.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        let notes = model.notes(for: customerID)
        VStack(alignment: .leading, spacing: 20) {
            if let message = problem ?? model.error {
                Text(message).font(Theme.font(15)).foregroundStyle(Theme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .accessibilityIdentifier("customer-notes-problem")
            }
            VStack(alignment: .leading, spacing: 8) {
                PaperSection(title: "On this phone", count: notes.count) {
                    if notes.isEmpty {
                        LearnEmptyRow(title: "No notes yet",
                                      message: "Add what the next person should know: how they like to be reached, the dog, where to park.")
                            .accessibilityIdentifier("customer-notes-empty")
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                                if index > 0 { WellDivider() }
                                noteRow(note)
                            }
                        }
                    }
                } accessory: {
                    if model.isOpen {
                        LearnSectionAction(title: "Add", label: "Add a note about \(customerName)", identifier: "customer-notes-add") {
                            editing = CustomerNoteEditing(note: nil)
                        }
                        .padding(.vertical, -9)
                    }
                }
                LearnFootnote(text: "Kept on this phone for this workspace. They are not sent to Thorbis or shown on other phones.")
            }
            if !placeNotes.isEmpty {
                PaperSection("Property notes", count: placeNotes.count) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(placeNotes.enumerated()), id: \.element.id) { index, place in
                            if index > 0 { WellDivider() }
                            placeRow(place)
                        }
                    }
                }
                .accessibilityIdentifier("customer-notes-places")
            }
        }
        .sheet(item: $editing) { item in
            SheetSurface {
                CustomerNoteEditor(note: item.note, customerName: customerName) { text in
                    if let note = item.note {
                        try model.edit(note.id, body: text)
                    } else {
                        guard let author = session.user else {
                            throw Problem(title: "Sign in to add a note", status: nil, detail: nil)
                        }
                        try model.add(customerID: customerID, body: text, authorID: author.id,
                                      authorName: author.name ?? author.email ?? "")
                    }
                    problem = nil
                }
            }
        }
        .thorbisConfirm(item: $removing,
                        title: { _ in "Delete this note?" },
                        message: { _ in "It is removed from this phone and can\u{2019}t be brought back." },
                        actions: { note in
            [ThorbisConfirmAction("Delete", role: .destructive) {
                do { try model.remove(note.id); problem = nil }
                catch { problem = "The note was not deleted. \(error.localizedDescription)" }
            }]
        })
    }

    private func noteRow(_ note: CustomerPhoneNote) -> some View {
        let byline = CustomerNoteRules.byline(note)
        let items = [ThorbisMenuItem("Edit", icon: "pencil") { editing = CustomerNoteEditing(note: note) },
                     ThorbisMenuItem("Delete", icon: "trash", role: .destructive) { removing = note }]
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.body).font(Theme.font(16)).foregroundStyle(Theme.foreground)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Text(byline).font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)
            ThorbisMenu(items: items, accessibilityLabel: "Note actions") {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityIdentifier("customer-note-actions-\(note.id)")
        }
        .padding(.leading, PaperCardMetrics.inset).padding(.trailing, 4)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .accessibilityIdentifier("customer-note-\(note.id)")
    }

    /// A place's note as the server holds it. It is changed where the place is edited (Property).
    private func placeRow(_ place: ServiceLocationRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(place.notes ?? "").font(Theme.font(16)).foregroundStyle(Theme.foreground)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Text([place.label, place.address].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct CustomerNoteEditing: Identifiable {
    let note: CustomerPhoneNote?
    var id: String { note?.id ?? "new-note" }
}

/// Add or change a note: Cancel and Save over one field.
private struct CustomerNoteEditor: View {
    let note: CustomerPhoneNote?
    let customerName: String
    let onSave: (String) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var problem: String?
    @FocusState private var focused: Bool

    init(note: CustomerPhoneNote?, customerName: String, onSave: @escaping (String) throws -> Void) {
        self.note = note
        self.customerName = customerName
        self.onSave = onSave
        _text = State(initialValue: note?.body ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            LearnEditorHeader(title: note == nil ? "Add note" : "Edit note", saveIdentifier: "customer-note-save",
                              onCancel: { dismiss() }, onSave: save)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LearnCard {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Note about \(customerName)").font(Theme.font(13)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityHidden(true)
                            TextField("", text: Binding(get: { text }, set: { text = $0; problem = nil }),
                                      prompt: .placeholder("Prefers texts. Dog in the back yard."), axis: .vertical)
                                .font(Theme.font(16)).foregroundStyle(Theme.foreground)
                                .lineLimit(4...12)
                                .focused($focused)
                                .accessibilityLabel("Note about \(customerName)")
                                .accessibilityIdentifier("customer-note-field")
                            if let problem { FieldProblem(message: problem) }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    }
                    LearnFootnote(text: "Saved on this phone only, with your name and today\u{2019}s date.")
                }
                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background.ignoresSafeArea())
        .onAppear { focused = true }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { problem = "Write the note to save it."; return }
        guard trimmed.count <= CustomerNoteRules.limit else {
            problem = "Shorten the note to \(CustomerNoteRules.limit) characters."
            return
        }
        do { try onSave(trimmed); dismiss() }
        catch { problem = error.localizedDescription }
    }
}
