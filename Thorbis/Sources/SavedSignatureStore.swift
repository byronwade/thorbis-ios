import CryptoKit
import Foundation
import SwiftUI

// Paper 65D "Saved signature": the technician's own signature, drawn once and kept on this phone
// for that person. It is a drawing in a protected file, never sent anywhere, and never used as a
// customer's signature: customers sign for themselves on the estimate or invoice.

/// A person's signature as they drew it: the strokes and the size of the pad they were drawn on.
struct SavedSignature: Codable, Equatable {
    var strokes: [[CGPoint]]
    var padWidth: Double
    var padHeight: Double
    /// The person's name when it was saved, shown under the line.
    var signerName: String
    var savedAt: String
}

enum SavedSignatureInk {
    /// The strokes that hold ink (two points or more).
    static func inked(_ strokes: [[CGPoint]]) -> [[CGPoint]] { strokes.filter { $0.count > 1 } }

    /// The strokes moved and scaled to sit centred inside `size` with `padding` around them, keeping
    /// their shape. Ink is never enlarged past `maxScale`, so a small signature stays a signature.
    static func fit(_ strokes: [[CGPoint]], in size: CGSize, padding: CGFloat = 12, maxScale: CGFloat = 1.5) -> [[CGPoint]] {
        let ink = inked(strokes)
        let points = ink.flatMap { $0 }
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max(),
              size.width > padding * 2, size.height > padding * 2 else { return [] }
        let width = max(maxX - minX, 1), height = max(maxY - minY, 1)
        let scale = min((size.width - padding * 2) / width, (size.height - padding * 2) / height, maxScale)
        let offsetX = (size.width - width * scale) / 2
        let offsetY = (size.height - height * scale) / 2
        return ink.map { stroke in
            stroke.map { CGPoint(x: ($0.x - minX) * scale + offsetX, y: ($0.y - minY) * scale + offsetY) }
        }
    }

    /// "Saved Jun 3", with the year once it is not this one.
    static func savedLabel(_ raw: String, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard let date = JobFiltering.date(raw) else { return "Saved" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(calendar.isDate(date, equalTo: now, toGranularity: .year) ? "MMMd" : "MMMdyyyy")
        return "Saved \(formatter.string(from: date))"
    }
}

/// One person's saved signature on this phone: a protected file named by a hash of the account,
/// so it follows the person across their workspaces and no id is readable on disk.
@MainActor
final class SavedSignatureStore {
    let fileURL: URL
    private(set) var signature: SavedSignature?

    static func fileURL(actorID: String, directory: URL? = nil) throws -> URL {
        guard UUID(uuidString: actorID) != nil else {
            throw Problem(title: "Invalid signature identity", status: nil, detail: nil)
        }
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SavedSignatures", isDirectory: true)
        let digest = SHA256.hash(data: Data("v1|saved-signature|\(actorID.lowercased())".utf8))
            .map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("\(digest).json")
    }

    /// Whether this person has one on file, without opening it.
    static func isOnFile(actorID: String?, directory: URL? = nil) -> Bool {
        guard let actorID, let url = try? fileURL(actorID: actorID, directory: directory) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    init(actorID: String, directory: URL? = nil) throws {
        fileURL = try Self.fileURL(actorID: actorID, directory: directory)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            signature = try JSONDecoder().decode(SavedSignature.self, from: Data(contentsOf: fileURL))
        }
    }

    /// Replaces the saved signature. Strokes without ink are refused.
    @discardableResult
    func save(strokes: [[CGPoint]], padSize: CGSize, signerName: String, now: Date = Date()) throws -> SavedSignature {
        let ink = SavedSignatureInk.inked(strokes)
        guard !ink.isEmpty else {
            throw Problem(title: "Draw your signature first", status: nil, detail: nil)
        }
        let next = SavedSignature(strokes: ink, padWidth: Double(padSize.width), padHeight: Double(padSize.height),
                                  signerName: signerName.trimmingCharacters(in: .whitespacesAndNewlines),
                                  savedAt: ISO8601DateFormatter().string(from: now))
        try LearnPartition.write(JSONEncoder().encode(next), to: fileURL)
        signature = next
        return next
    }

    /// Deletes the file. Nothing else holds a copy.
    func clear() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        signature = nil
    }
}
