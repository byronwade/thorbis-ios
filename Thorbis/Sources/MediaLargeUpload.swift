import CryptoKit
import Foundation

// Files over 8 MiB go to storage in 8 MiB parts (contracts/api/http.md, "Job media upload"). The
// rules that can be checked without a server live here: how a file is cut and hashed, what is kept
// on the phone about an unfinished send, the words for it, and whether this server can take big
// files at all. `MediaTransfer.uploadLarge` does the sending; `PendingMediaStore` keeps the file.

/// A file's size, its whole SHA-256, and the SHA-256 of each 8 MiB part.
struct MediaFileDigest: Equatable, Sendable {
    let sizeBytes: Int
    let contentHash: String
    let partHashes: [String]
}

enum MediaParts {
    /// The server's part size (`MEDIA_PART_SIZE_BYTES`). A file of this size or less is one upload.
    static let partSize = 8 * 1024 * 1024
    /// Parts in the largest file the server stores (a 200 MiB video).
    static let maxParts = 25

    static func isLarge(_ sizeBytes: Int) -> Bool { sizeBytes > partSize }

    /// Every part is 8 MiB except the last, which holds what is left (`resumablePartSizes`).
    static func sizes(for sizeBytes: Int) -> [Int] {
        guard sizeBytes > 0 else { return [] }
        let count = (sizeBytes + partSize - 1) / partSize
        return (0..<count).map { $0 == count - 1 ? sizeBytes - partSize * (count - 1) : partSize }
    }

    private static func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }

    /// Reads the file once, a megabyte at a time, so a 200 MB video is never held in memory.
    static func digest(of file: URL, chunk: Int = 1024 * 1024, partSize: Int = MediaParts.partSize) throws -> MediaFileDigest {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var whole = SHA256(), part = SHA256()
        var inPart = 0, total = 0
        var parts: [String] = []
        while true {
            try Task.checkCancellation()
            guard let data = try handle.read(upToCount: min(chunk, partSize - inPart)), !data.isEmpty else { break }
            whole.update(data: data); part.update(data: data)
            inPart += data.count; total += data.count
            if inPart == partSize {
                parts.append(hex(part.finalize()))
                part = SHA256(); inPart = 0
            }
        }
        if inPart > 0 { parts.append(hex(part.finalize())) }
        return MediaFileDigest(sizeBytes: total, contentHash: hex(whole.finalize()), partHashes: parts)
    }

    /// The bytes of one part (1-based), read straight from the file.
    static func read(_ file: URL, partNumber: Int, sizeBytes: Int, partSize: Int = MediaParts.partSize) throws -> Data {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64((partNumber - 1) * partSize))
        let data = try handle.read(upToCount: sizeBytes) ?? Data()
        guard data.count == sizeBytes else { throw CocoaError(.fileReadCorruptFile) }
        return data
    }

    /// The request for a file of this size: part hashes go with a large file and never with a small one.
    static func registration(clientAssetID: String, kind: String, mime: String, originalFilename: String,
                             digest: MediaFileDigest, capturedAt: Date, tags: [String], caption: String?) -> FieldMediaRegistrationRequest {
        FieldMediaRegistrationRequest(clientAssetId: clientAssetID, kind: kind, mime: mime, sizeBytes: digest.sizeBytes,
                                      originalFilename: originalFilename, contentHash: digest.contentHash,
                                      capturedAt: ISO8601DateFormatter().string(from: capturedAt),
                                      tags: tags.isEmpty ? nil : tags, caption: caption,
                                      partHashes: isLarge(digest.sizeBytes) ? digest.partHashes : nil)
    }

    /// Parts 1…N in order, each with the tag storage answered and the hash declared for it. Nil
    /// until every part has a tag.
    static func confirmation(uploadID: String, digest: MediaFileDigest, etags: [Int: String]) -> FieldMultipartConfirmation? {
        var parts: [FieldMultipartConfirmation.Part] = []
        for (index, hash) in digest.partHashes.enumerated() {
            guard let etag = etags[index + 1] else { return nil }
            parts.append(.init(partNumber: index + 1, etag: etag, contentHash: hash))
        }
        return parts.isEmpty ? nil : FieldMultipartConfirmation(uploadId: uploadID, parts: parts)
    }
}

/// What the phone remembers about a big file that is part-way sent, kept beside the file so a
/// restart carries on. The server's answer still decides which parts are really there.
struct MediaUploadProgress: Codable, Equatable, Sendable {
    var uploadID: String
    var totalParts: Int
    /// Part number → the tag storage answered for it.
    var etags: [Int: String] = [:]

    var sentParts: Int { etags.keys.filter { (1...max(totalParts, 1)).contains($0) }.count }
    /// 0…100. A send that has every part but is not confirmed yet stays under 100.
    var percent: Int { totalParts > 0 ? min(99, sentParts * 100 / totalParts) : 0 }

    /// What an attempt starts from: the parts the server says storage holds. After the server
    /// refuses the upload ID, every part is sent again whatever it lists.
    static func starting(uploadID: String, totalParts: Int, held: [Int: String], sendEveryPart: Bool = false) -> MediaUploadProgress {
        MediaUploadProgress(uploadID: uploadID, totalParts: totalParts,
                            etags: sendEveryPart ? [:] : held.filter { (1...max(totalParts, 1)).contains($0.key) })
    }

    var missingParts: [Int] { totalParts > 0 ? (1...totalParts).filter { etags[$0] == nil } : [] }
}

/// The words a person reads when a send can't finish.
enum MediaUploadWords {
    /// A big file on a server that can only take 8 MB so far.
    static let tooBigForNow = "This file is too big to send yet. Files can be up to 8 MB."
    /// The server's storage is not answering (502 or 504). Nothing is lost.
    static let storageDown = "Photos can\u{2019}t be saved right now. They\u{2019}re kept on this phone and will send later."

    /// The size line under the add buttons, following what this server has shown it can take:
    /// the big limits once it took a big file, 8 MB once it refused one, and neither promise
    /// while it is not known yet (a big file is tried then, with a smaller copy kept beside it).
    static func limitNote(_ answer: MediaLargeUploads.Answer) -> String {
        switch answer {
        case .yes: "Photos and PDFs up to 50 MB. Videos up to 200 MB."
        case .no: "Photos, PDFs and clips up to 8 MB."
        case .unknown: "Photos, PDFs and videos. A very big file may be sent as a smaller copy."
        }
    }

    /// The same line for a document on its own.
    static func documentLimitNote(_ answer: MediaLargeUploads.Answer) -> String {
        switch answer {
        case .yes: "PDFs up to 50 MB."
        case .no: "Up to 8 MB."
        case .unknown: "PDF files."
        }
    }

    /// "Video clips are limited to 8 MB for now, so the first 20 seconds were kept."
    static func keptFirstPart(seconds: Double?) -> String {
        guard let seconds else { return "Video clips are limited to 8 MB for now, so a smaller copy was sent." }
        return "Video clips are limited to 8 MB for now, so the first \(Int(seconds)) seconds were kept."
    }
}

/// Whether this server takes files over 8 MB, learned from its answers. There is no flag for it,
/// so the phone finds out the first time a big file is sent, and remembers for a day when the
/// answer is no: until then it keeps fitting clips and PDFs to 8 MB exactly as before.
enum MediaLargeUploads {
    enum Answer: Equatable { case unknown, yes, no }

    static let recheckAfter: TimeInterval = 24 * 60 * 60
    private static let key = "thorbis.media.largeUploads.v1"

    static func answer(origin: String?, now: Date = Date(), defaults: UserDefaults = .standard) -> Answer {
        guard let origin, let saved = (defaults.dictionary(forKey: key) ?? [:])[origin] as? Double else { return .unknown }
        if saved == 0 { return .yes }
        return now.timeIntervalSince1970 - saved < recheckAfter ? .no : .unknown
    }

    /// Big files are prepared and queued unless this server said no within the last day.
    static func allowed(origin: String?, now: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
        answer(origin: origin, now: now, defaults: defaults) != .no
    }

    static func record(_ supported: Bool, origin: String?, now: Date = Date(), defaults: UserDefaults = .standard) {
        guard let origin else { return }
        var all = defaults.dictionary(forKey: key) ?? [:]
        all[origin] = supported ? 0 : now.timeIntervalSince1970
        defaults.set(all, forKey: key)
    }

    static func forget(defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key) }
}
