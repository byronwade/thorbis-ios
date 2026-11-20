import CryptoKit
import Foundation

// Training (Paper 28 "Content portal", 58C "Licenses and compliance"). There is no course
// catalogue on the server, so this place keeps what one person can truthfully keep on one
// phone: their own licenses and certifications, and the courses they are taking. Nothing here
// is sent anywhere; it is a notebook for this account in this workspace.

/// One license or certification the person holds.
struct TrainingCredential: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var name: String
    var number: String?
    var issuer: String?
    /// The day it runs out, as "yyyy-MM-dd". A day, not a moment: it does not move with time zones.
    var expiresOn: String?
    /// The card's photo, a file name inside this partition's photo folder.
    var photoFile: String?
    var notes: String?
    let createdAt: String

    init(id: String = UUID().uuidString, name: String, number: String? = nil, issuer: String? = nil,
         expiresOn: String? = nil, photoFile: String? = nil, notes: String? = nil,
         createdAt: String = ISO8601DateFormatter().string(from: Date())) {
        self.id = id; self.name = name; self.number = number; self.issuer = issuer
        self.expiresOn = expiresOn; self.photoFile = photoFile; self.notes = notes; self.createdAt = createdAt
    }
}

/// A course or link the person is working through, with their own note on how far they are.
struct TrainingCourse: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var title: String
    var link: String?
    var progress: String?
    var done: Bool
    let createdAt: String

    init(id: String = UUID().uuidString, title: String, link: String? = nil, progress: String? = nil,
         done: Bool = false, createdAt: String = ISO8601DateFormatter().string(from: Date())) {
        self.id = id; self.title = title; self.link = link; self.progress = progress
        self.done = done; self.createdAt = createdAt
    }
}

/// Calendar days written as "yyyy-MM-dd", read and written in the calendar they are shown in.
enum LearnDay {
    static func string(from date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The start of that day; nil for anything that is not a real "yyyy-MM-dd" day.
    static func date(from text: String?, calendar: Calendar = .current) -> Date? {
        guard let text else { return nil }
        let pieces = text.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 3, pieces[0].count == 4, pieces[1].count == 2, pieces[2].count == 2,
              let year = Int(pieces[0]), let month = Int(pieces[1]), let day = Int(pieces[2]) else { return nil }
        var parts = DateComponents()
        parts.year = year; parts.month = month; parts.day = day
        guard let date = calendar.date(from: parts) else { return nil }
        // Calendar rolls "2026-02-31" forward; a day that does not round-trip is not a day.
        return string(from: date, calendar: calendar) == text ? date : nil
    }

    /// "Mar 1, 2027", in the calendar's own time zone.
    static func label(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMMdyyyy")
        return formatter.string(from: date)
    }
}

/// Where a license stands today. Whole days only: a card that runs out today is still good today.
enum CredentialExpiry: Equatable {
    /// No expiry was written down.
    case none
    case expired(days: Int)
    case today
    /// Inside the warning window (Paper 28: "Expires in 14 days").
    case soon(days: Int)
    case valid(days: Int)

    /// How far ahead a card starts asking for attention.
    static let soonWindow = 30

    /// Whole days from today to the expiry day: 0 today, negative once it has passed.
    static func daysLeft(expiresOn: String?, today: Date, calendar: Calendar = .current) -> Int? {
        guard let expiry = LearnDay.date(from: expiresOn, calendar: calendar) else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: expiry).day
    }

    init(expiresOn: String?, today: Date, calendar: Calendar = .current) {
        guard let days = Self.daysLeft(expiresOn: expiresOn, today: today, calendar: calendar) else {
            self = .none
            return
        }
        if days < 0 { self = .expired(days: -days) }
        else if days == 0 { self = .today }
        else if days <= Self.soonWindow { self = .soon(days: days) }
        else { self = .valid(days: days) }
    }

    /// Expired, or about to be.
    var needsAttention: Bool {
        switch self {
        case .expired, .today, .soon: true
        case .none, .valid: false
        }
    }

    /// "Expired 3 days ago", "Expires today", "Expires in 14 days", "To Mar 1, 2027", "No expiry date".
    static func label(expiresOn: String?, today: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        switch CredentialExpiry(expiresOn: expiresOn, today: today, calendar: calendar) {
        case .none: return "No expiry date"
        case .expired(let days): return days == 1 ? "Expired yesterday" : "Expired \(days) days ago"
        case .today: return "Expires today"
        case .soon(let days): return days == 1 ? "Expires tomorrow" : "Expires in \(days) days"
        case .valid:
            guard let date = LearnDay.date(from: expiresOn, calendar: calendar) else { return "No expiry date" }
            return "To \(LearnDay.label(date, calendar: calendar, locale: locale))"
        }
    }

    /// Soonest first: expired, then by days left, then cards with no date, each group by name.
    static func sorted(_ credentials: [TrainingCredential], today: Date, calendar: Calendar = .current) -> [TrainingCredential] {
        credentials.sorted { lhs, rhs in
            let left = daysLeft(expiresOn: lhs.expiresOn, today: today, calendar: calendar)
            let right = daysLeft(expiresOn: rhs.expiresOn, today: today, calendar: calendar)
            switch (left, right) {
            case let (a?, b?) where a != b: return a < b
            case (.some, .none): return true
            case (.none, .some): return false
            default: return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }
}

/// A link the person typed for a course. Kept as written; only a plain https or http address
/// with a host counts as one, so it can be copied or shared.
enum TrainingLink {
    static func url(_ text: String?) -> URL? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), let host = url.host, host.contains(".") else { return nil }
        return url
    }

    /// "epa.gov", for the row's quiet line.
    static func host(_ text: String?) -> String? {
        guard let host = url(text)?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// Where this feature's on-phone files live: one JSON file per exact identity, named by a hash
/// so no account or workspace id is readable on disk (as `LocalWorkspaceRecords` does).
enum LearnPartition {
    static func root(_ directory: URL?) -> URL {
        directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LearnBooks", isDirectory: true)
    }

    /// `actorID` is nil for a book the whole workspace's sign-ins on this phone share.
    static func name(kind: String, actorID: String?, organizationID: String) throws -> String {
        guard UUID(uuidString: organizationID) != nil, actorID.map({ UUID(uuidString: $0) != nil }) ?? true else {
            throw Problem(title: "Invalid local book identity", status: nil, detail: nil)
        }
        let partition = "v1|\(kind)|\((actorID ?? "-").lowercased())|\(organizationID.lowercased())"
        return SHA256.hash(data: Data(partition.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func write(_ data: Data, to url: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                    attributes: [.protectionKey: FileProtectionType.complete])
        try data.write(to: url, options: .atomic)
        try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    }
}

/// What Save does with a card's photo.
enum CredentialPhotoChange: Equatable {
    case keep
    case remove
    /// JPEG data for the new photo.
    case replace(Data)
}

private struct TrainingBook: Codable {
    var credentials: [TrainingCredential] = []
    var courses: [TrainingCourse] = []
}

/// One person's licenses and courses in one workspace, on this phone only.
@MainActor
final class TrainingRecords {
    let fileURL: URL
    /// Card photos sit beside the book, in a folder of their own.
    let photosURL: URL
    private var book: TrainingBook

    var credentials: [TrainingCredential] { book.credentials }
    var courses: [TrainingCourse] { book.courses }

    init(actorID: String, organizationID: String, directory: URL? = nil) throws {
        let name = try LearnPartition.name(kind: "training", actorID: actorID, organizationID: organizationID)
        let root = LearnPartition.root(directory)
        fileURL = root.appendingPathComponent("\(name).json")
        photosURL = root.appendingPathComponent("\(name)-cards", isDirectory: true)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            book = try JSONDecoder().decode(TrainingBook.self, from: Data(contentsOf: fileURL))
        } else {
            book = TrainingBook()
        }
    }

    private func commit(_ next: TrainingBook) throws {
        try LearnPartition.write(JSONEncoder().encode(next), to: fileURL)
        book = next
    }

    /// The photo's place on disk; nil for a name that is not one of this folder's own files.
    func photoURL(_ file: String?) -> URL? {
        guard let file, !file.isEmpty, !file.contains("/"), !file.hasPrefix(".") else { return nil }
        return photosURL.appendingPathComponent(file)
    }

    private func deletePhoto(_ file: String?) {
        guard let url = photoURL(file) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Saves the card and applies the photo change. The new photo is written before the book
    /// names it, and the old one is removed only after the book no longer does.
    @discardableResult
    func save(_ credential: TrainingCredential, photo: CredentialPhotoChange = .keep) throws -> TrainingCredential {
        var record = credential
        let previous = book.credentials.first { $0.id == credential.id }?.photoFile
        switch photo {
        case .keep:
            record.photoFile = previous
        case .remove:
            record.photoFile = nil
        case .replace(let data):
            let file = "\(UUID().uuidString.lowercased()).jpg"
            try LearnPartition.write(data, to: photosURL.appendingPathComponent(file))
            record.photoFile = file
        }
        var next = book
        if let index = next.credentials.firstIndex(where: { $0.id == record.id }) {
            next.credentials[index] = record
        } else {
            next.credentials.append(record)
        }
        do {
            try commit(next)
        } catch {
            if record.photoFile != previous { deletePhoto(record.photoFile) }
            throw error
        }
        if record.photoFile != previous { deletePhoto(previous) }
        return record
    }

    func save(_ course: TrainingCourse) throws {
        var next = book
        if let index = next.courses.firstIndex(where: { $0.id == course.id }) {
            next.courses[index] = course
        } else {
            next.courses.append(course)
        }
        try commit(next)
    }

    func removeCredential(_ id: String) throws {
        let photo = book.credentials.first { $0.id == id }?.photoFile
        var next = book
        next.credentials.removeAll { $0.id == id }
        try commit(next)
        deletePhoto(photo)
    }

    func removeCourse(_ id: String) throws {
        var next = book
        next.courses.removeAll { $0.id == id }
        try commit(next)
    }

    /// Removes this identity's book and every card photo with it.
    func erasePartition() throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: fileURL.path) { try manager.removeItem(at: fileURL) }
        if manager.fileExists(atPath: photosURL.path) { try manager.removeItem(at: photosURL) }
        book = TrainingBook()
    }
}
