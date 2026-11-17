import CryptoKit
import Foundation

/// Where a lead stands. New, Visit booked and Quoted are open; Won and Lost are how one ends.
enum LeadStage: String, Codable, CaseIterable, Hashable {
    case new, visitBooked, quoted, won, lost

    static let open: [LeadStage] = [.new, .visitBooked, .quoted]

    var label: String {
        switch self {
        case .new: "New"
        case .visitBooked: "Visit booked"
        case .quoted: "Quoted"
        case .won: "Won"
        case .lost: "Lost"
        }
    }

    var isOpen: Bool { LeadStage.open.contains(self) }

    /// The stage an open lead moves to next.
    var next: LeadStage? {
        switch self {
        case .new: .visitBooked
        case .visitBooked: .quoted
        case .quoted: .won
        case .won, .lost: nil
        }
    }
}

/// A lead is a company record, but no server route holds leads yet: it is kept on this phone.
struct LeadRecord: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var name: String
    var phone: String?
    /// What they need ("Water heater quote, 50 gal gas").
    var need: String?
    var source: String?
    /// The likely value, in cents. An estimate the person typed, not a quote.
    var valueCents: Int?
    var note: String?
    var stage: LeadStage
    let createdAt: Date
    var updatedAt: Date

    init(id: String = UUID().uuidString, name: String, phone: String? = nil, need: String? = nil,
         source: String? = nil, valueCents: Int? = nil, note: String? = nil, stage: LeadStage = .new,
         createdAt: Date = Date(), updatedAt: Date? = nil) {
        self.id = id; self.name = name; self.phone = phone; self.need = need; self.source = source
        self.valueCents = valueCents; self.note = note; self.stage = stage
        self.createdAt = createdAt; self.updatedAt = updatedAt ?? createdAt
    }

    private var dialable: String? {
        let digits = (phone ?? "").filter { $0.isNumber || $0 == "+" }
        return digits.count >= 7 ? digits : nil
    }
    var callURL: URL? { dialable.flatMap { URL(string: "tel:\($0)") } }
    var textURL: URL? { dialable.flatMap { URL(string: "sms:\($0)") } }
}

/// Counts and totals for the pipeline, kept apart from the screens so they can be tested.
enum PipelineMath {
    static let sources = ["Phone call", "Google", "Referral", "Website", "Repeat customer", "Other"]

    static func count(_ leads: [LeadRecord], in stage: LeadStage) -> Int { leads.filter { $0.stage == stage }.count }

    static func counts(_ leads: [LeadRecord]) -> [LeadStage: Int] {
        var result: [LeadStage: Int] = [:]
        for stage in LeadStage.allCases { result[stage] = 0 }
        for lead in leads { result[lead.stage, default: 0] += 1 }
        return result
    }

    static func openCount(_ leads: [LeadRecord]) -> Int { leads.filter { $0.stage.isOpen }.count }

    /// The likely value of one stage; leads with no estimate add nothing.
    static func value(_ leads: [LeadRecord], in stage: LeadStage) -> Int {
        leads.reduce(0) { $1.stage == stage ? $0 + max(0, $1.valueCents ?? 0) : $0 }
    }

    /// What the open leads could be worth: New, Visit booked and Quoted. Won and Lost are left out.
    static func possibleValue(_ leads: [LeadRecord]) -> Int {
        leads.reduce(0) { $1.stage.isOpen ? $0 + max(0, $1.valueCents ?? 0) : $0 }
    }

    /// One stage's leads, the most recently touched first.
    static func leads(_ leads: [LeadRecord], in stage: LeadStage) -> [LeadRecord] {
        leads.filter { $0.stage == stage }.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// "9 leads · $34,800 possible"
    static func summary(_ leads: [LeadRecord]) -> String {
        let open = openCount(leads)
        let count = open == 1 ? "1 lead" : "\(open) leads"
        let value = possibleValue(leads)
        return value > 0 ? "\(count) \u{00B7} \(money(value)) possible" : count
    }

    /// "$6,200": whole dollars unless there are cents.
    static func money(_ cents: Int) -> String {
        (Decimal(cents) / 100).formatted(.currency(code: "USD").precision(.fractionLength(cents % 100 == 0 ? 0 : 2)))
    }

    /// "9:41 AM" today, "Yesterday", the weekday within a week, otherwise "Jul 9".
    static func when(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return date.formatted(date: .omitted, time: .shortened) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day,
           days > 0, days < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

private struct PipelineBookContents: Codable {
    var leads: [LeadRecord] = []
}

/// One protected JSON file for each workspace, in Application Support on this phone.
@MainActor
final class PipelineRecords {
    let organizationID: String
    let fileURL: URL
    private var book: PipelineBookContents

    var leads: [LeadRecord] { book.leads }

    private static func partitionURL(organizationID: String, directory: URL?) throws -> URL {
        let key = organizationID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { throw Problem(title: "No workspace is open", status: nil, detail: nil) }
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PipelineBooks", isDirectory: true)
        let digest = SHA256.hash(data: Data("v1|\(key)".utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("\(digest).json")
    }

    private static func encoder() -> JSONEncoder { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return encoder }
    private static func decoder() -> JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder }

    init(organizationID: String, directory: URL? = nil) throws {
        self.organizationID = organizationID.lowercased()
        self.fileURL = try Self.partitionURL(organizationID: organizationID, directory: directory)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            self.book = try Self.decoder().decode(PipelineBookContents.self, from: Data(contentsOf: fileURL))
        } else {
            self.book = PipelineBookContents()
        }
    }

    private func commit(_ next: PipelineBookContents) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                    attributes: [.protectionKey: FileProtectionType.complete])
        try Self.encoder().encode(next).write(to: fileURL, options: .atomic)
        try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: fileURL.path)
        book = next
    }

    func lead(_ id: String) -> LeadRecord? { book.leads.first { $0.id == id } }

    func save(_ lead: LeadRecord, now: Date = Date()) throws {
        guard !lead.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Problem(title: "A lead needs a name", status: nil, detail: nil)
        }
        var next = book
        var saved = lead
        if next.leads.contains(where: { $0.id == lead.id }) { saved.updatedAt = now }
        next.leads.removeAll { $0.id == lead.id }
        next.leads.append(saved)
        try commit(next)
    }

    /// Moves a lead between stages, or marks it won or lost.
    func move(_ id: String, to stage: LeadStage, now: Date = Date()) throws {
        guard var lead = lead(id) else { throw Problem(title: "This lead is no longer on this phone", status: nil, detail: nil) }
        guard lead.stage != stage else { return }
        lead.stage = stage
        try save(lead, now: now)
    }

    func remove(_ id: String) throws {
        var next = book
        next.leads.removeAll { $0.id == id }
        try commit(next)
    }
}
