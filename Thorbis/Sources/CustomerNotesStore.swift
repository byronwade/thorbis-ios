import Foundation

// Paper 48N "Notes": the last row of the customer's card ("Prefers texts · dog in back yard").
// The server has no note on a customer (only on their locations, equipment and memberships), so
// these are kept on this phone for the workspace: anyone who signs in to this workspace on this
// phone reads them, and nobody else does. Each note says who wrote it and when.

/// A note about a customer, written on this phone.
struct CustomerPhoneNote: Codable, Identifiable, Equatable {
    let id: String
    let customerID: String
    var body: String
    /// Who wrote it: the account id, and the name as it was then.
    let authorID: String
    let authorName: String
    let createdAt: String
    /// Set when the words were changed after they were first saved.
    var editedAt: String?

    init(id: String = UUID().uuidString, customerID: String, body: String, authorID: String, authorName: String,
         createdAt: String = ISO8601DateFormatter().string(from: Date()), editedAt: String? = nil) {
        self.id = id; self.customerID = customerID; self.body = body; self.authorID = authorID
        self.authorName = authorName; self.createdAt = createdAt; self.editedAt = editedAt
    }
}

enum CustomerNoteRules {
    static let limit = 2_000

    /// The words as they are kept: trimmed. Nil when there is nothing to keep or it is too long.
    static func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.count > limit ? nil : trimmed
    }

    /// Newest first; notes saved in the same second keep a steady order.
    static func newestFirst(_ notes: [CustomerPhoneNote]) -> [CustomerPhoneNote] {
        notes.sorted { a, b in
            switch (JobFiltering.date(a.createdAt), JobFiltering.date(b.createdAt)) {
            case let (x?, y?): x == y ? a.id > b.id : x > y
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): a.createdAt == b.createdAt ? a.id > b.id : a.createdAt > b.createdAt
            }
        }
    }

    /// The hub row's line: the newest notes' first lines ("Prefers texts · dog in back yard").
    static func summary(_ notes: [CustomerPhoneNote], limit: Int = 2) -> String? {
        let lines = newestFirst(notes).prefix(limit).compactMap { note in
            note.body.split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespaces) }
        }.filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines.joined(separator: " · ")
    }

    /// "Ramon Mendez · Nov 17, 2026" and "edited" when it was.
    static func byline(_ note: CustomerPhoneNote, calendar: Calendar = .current, locale: Locale = .current) -> String {
        var parts = [note.authorName.isEmpty ? "Someone on this phone" : note.authorName]
        if let date = JobFiltering.date(note.createdAt) {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate("MMMdyyyy")
            parts.append(formatter.string(from: date))
        }
        if note.editedAt != nil { parts.append("edited") }
        return parts.joined(separator: " · ")
    }
}

private struct CustomerNotesBook: Codable {
    var notes: [CustomerPhoneNote] = []
}

/// The workspace's customer notes on this phone: one protected file per workspace, named by a
/// hash so no id is readable on disk. Every change is written before it shows.
@MainActor
final class CustomerNotesStore {
    let fileURL: URL
    private var book: CustomerNotesBook

    init(organizationID: String, directory: URL? = nil) throws {
        let name = try LearnPartition.name(kind: "customer-notes", actorID: nil, organizationID: organizationID)
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CustomerNotes", isDirectory: true)
        fileURL = root.appendingPathComponent("\(name).json")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            book = try JSONDecoder().decode(CustomerNotesBook.self, from: Data(contentsOf: fileURL))
        } else {
            book = CustomerNotesBook()
        }
    }

    private func commit(_ next: CustomerNotesBook) throws {
        try LearnPartition.write(JSONEncoder().encode(next), to: fileURL)
        book = next
    }

    /// This customer's notes, newest first.
    func notes(for customerID: String) -> [CustomerPhoneNote] {
        CustomerNoteRules.newestFirst(book.notes.filter { $0.customerID.caseInsensitiveCompare(customerID) == .orderedSame })
    }

    @discardableResult
    func add(customerID: String, body: String, authorID: String, authorName: String, now: Date = Date()) throws -> CustomerPhoneNote {
        guard let text = CustomerNoteRules.clean(body) else {
            throw Problem(title: "Write the note first", status: nil, detail: "A note needs words, up to \(CustomerNoteRules.limit) characters.")
        }
        let note = CustomerPhoneNote(customerID: customerID, body: text, authorID: authorID,
                                     authorName: authorName.trimmingCharacters(in: .whitespacesAndNewlines),
                                     createdAt: ISO8601DateFormatter().string(from: now))
        var next = book
        next.notes.append(note)
        try commit(next)
        return note
    }

    /// Changes a note's words. Who wrote it and when stay; it is marked edited.
    @discardableResult
    func edit(_ id: String, body: String, now: Date = Date()) throws -> CustomerPhoneNote {
        guard let text = CustomerNoteRules.clean(body) else {
            throw Problem(title: "Write the note first", status: nil, detail: "A note needs words, up to \(CustomerNoteRules.limit) characters.")
        }
        guard let index = book.notes.firstIndex(where: { $0.id == id }) else {
            throw Problem(title: "That note is no longer on this phone", status: nil, detail: nil)
        }
        var next = book
        if next.notes[index].body != text {
            next.notes[index].body = text
            next.notes[index].editedAt = ISO8601DateFormatter().string(from: now)
            try commit(next)
        }
        return next.notes[index]
    }

    func remove(_ id: String) throws {
        var next = book
        next.notes.removeAll { $0.id == id }
        try commit(next)
    }
}

/// Owns the open store for the views. Another workspace hides the old one's notes at once.
@MainActor
final class CustomerNotesModel: ObservableObject {
    @Published private(set) var revision = 0
    @Published private(set) var error: String?
    private var key: String?
    private var store: CustomerNotesStore?

    var isOpen: Bool { store != nil }

    func bind(organizationID: String?) {
        guard let organizationID else {
            store = nil; key = nil; error = nil; revision += 1
            return
        }
        let next = organizationID.lowercased()
        guard key != next || store == nil else { return }
        store = nil
        key = next
        do {
            store = try CustomerNotesStore(organizationID: organizationID)
            error = nil
        } catch {
            self.error = "Notes on this phone could not be opened. \(error.localizedDescription)"
        }
        revision += 1
    }

    func notes(for customerID: String) -> [CustomerPhoneNote] { store?.notes(for: customerID) ?? [] }

    private func open() throws -> CustomerNotesStore {
        guard let store else { throw Problem(title: "Notes are not open on this phone", status: nil, detail: nil) }
        return store
    }

    func add(customerID: String, body: String, authorID: String, authorName: String) throws {
        try open().add(customerID: customerID, body: body, authorID: authorID, authorName: authorName)
        revision += 1
    }

    func edit(_ id: String, body: String) throws {
        try open().edit(id, body: body)
        revision += 1
    }

    func remove(_ id: String) throws {
        try open().remove(id)
        revision += 1
    }
}
