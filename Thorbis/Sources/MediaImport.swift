import CoreTransferable
import Foundation
import UniformTypeIdentifiers

// Adding many photos, videos and PDFs to a job at once. Everything picked is saved on the phone
// first (PendingMediaStore), then sent one after another; the rules for what can be added and how
// the queue is described live here so they can be tested without a picker or a server.

/// What a file may be and how big, checked before anything is saved.
enum MediaLimits {
    static let megabyte = 1024 * 1024
    /// The server's ceilings per kind (domains/media `MAX_SIZE_BYTES`): the most it will ever store.
    static let serverMaxBytes: [String: Int] = ["photo": 50 * megabyte, "video": 200 * megabyte, "document": 50 * megabyte]
    /// The server's allowed types per kind (`ALLOWED_MIME`). Anything else is refused at registration.
    static let allowedMime: [String: [String]] = [
        "photo": ["image/jpeg", "image/png", "image/webp", "image/heic"],
        "video": ["video/mp4", "video/quicktime"],
        "document": ["application/pdf"],
    ]
    /// One file goes up as a single upload of at most 8 MB. Larger files need the server's
    /// multi-part upload, which its confirm route cannot finish yet, so the app holds to this
    /// (photos are resized and clips re-encoded to fit; a PDF over it is refused with words).
    static let singleUploadBytes = 8 * megabyte

    enum Refusal: Equatable {
        case empty
        case unsupported
        case tooLarge(limitBytes: Int)
    }

    /// "photo", "video" or "document" for an allowed type; nil for anything else.
    static func kind(mime: String) -> String? {
        let mime = mime.lowercased()
        return ["photo", "video", "document"].first { allowedMime[$0]?.contains(mime) == true }
    }

    /// The most this app can send for a kind today: the server's ceiling, held to one upload.
    static func uploadLimit(kind: String) -> Int {
        min(serverMaxBytes[kind] ?? singleUploadBytes, singleUploadBytes)
    }

    /// Nil when the file can be queued; otherwise why not.
    static func check(mime: String, bytes: Int) -> Refusal? {
        guard let kind = kind(mime: mime) else { return .unsupported }
        guard bytes > 0 else { return .empty }
        let limit = uploadLimit(kind: kind)
        return bytes > limit ? .tooLarge(limitBytes: limit) : nil
    }

    static func message(_ refusal: Refusal, name: String) -> String {
        switch refusal {
        case .empty: "\(name) is empty."
        case .unsupported: "\(name) isn\u{2019}t a photo, a video or a PDF."
        case .tooLarge(let limit): "\(name) is too big. Files can be up to \(limit / megabyte) MB."
        }
    }
}

/// How a library pick is handled, and the words for what happened to it.
enum MediaImportPlan {
    enum Picked: Equatable { case photo, video, other }
    enum Route: Equatable {
        /// One photo keeps the quick Before / After and caption step.
        case tagOne
        /// Several items, or any video: each is saved to the queue in the order picked.
        case queueAll
    }

    static func picked(_ types: [UTType]) -> Picked {
        if types.contains(where: { $0.conforms(to: .movie) || $0.conforms(to: .video) }) { return .video }
        if types.contains(where: { $0.conforms(to: .image) }) { return .photo }
        return .other
    }

    static func route(_ items: [Picked]) -> Route {
        items.count == 1 && items.first == .photo ? .tagOne : .queueAll
    }

    /// The queue sends oldest first, so each item of one pick is stamped a moment after the one
    /// before it: the files go up in the order they were chosen.
    static func capturedAt(base: Date, position: Int) -> Date {
        base.addingTimeInterval(Double(position) / 1000)
    }

    /// "photo-20261120T101500-3.jpg": the pick's time, then the item's place in it.
    static func filename(_ picked: Picked, stamp: String, position: Int) -> String {
        let (prefix, ext) = picked == .video ? ("clip", "mp4") : ("photo", "jpg")
        return "\(prefix)-\(stamp)-\(position + 1).\(ext)"
    }

    /// "Adding 3 of 12…" while the pick is being read and saved.
    static func progress(done: Int, total: Int) -> String {
        "Adding \(min(done + 1, total)) of \(total)\u{2026}"
    }

    /// What to say once a pick is saved: nil when everything was added and nothing was cut short.
    static func summary(added: Int, failed: Int, trimmed: Int) -> String? {
        var parts: [String] = []
        if failed > 0 {
            parts.append(added == 0 ? (failed == 1 ? "That one couldn\u{2019}t be added." : "None of the \(failed) could be added.")
                         : "\(added) added. \(failed) couldn\u{2019}t be added.")
        }
        if trimmed > 0 {
            parts.append(trimmed == 1 ? "One video was long, so its first part was kept."
                         : "\(trimmed) videos were long, so their first parts were kept.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

/// The queue in one line, and what a failed send does to the items after it.
enum MediaQueue {
    /// Oldest capture first; the ID settles a tie so the order never shuffles between reads.
    static func sendsBefore(_ first: PendingMedia, _ second: PendingMedia) -> Bool {
        first.capturedAt == second.capturedAt ? first.id < second.id : first.capturedAt < second.capturedAt
    }

    enum AfterFailure: Equatable {
        /// This item waits with its reason; the next one is still tried.
        case next
        /// No connection, or the send was called off: everything left waits for the next try.
        case stop
    }

    static func afterFailure(cancelled: Bool, connectivity: Bool) -> AfterFailure {
        cancelled || connectivity ? .stop : .next
    }

    /// "Sending 2 of 5…", "2 couldn't send. Tap one to see why.", or why they are waiting.
    static func line(waiting: [String], sendingID: String?, failed: Int, offline: Bool) -> String {
        if let sendingID, let place = waiting.firstIndex(of: sendingID) {
            return waiting.count == 1 ? "Sending now\u{2026}" : "Sending \(place + 1) of \(waiting.count)\u{2026}"
        }
        if sendingID != nil { return "Sending now\u{2026}" }
        if failed > 0 { return "\(failed) couldn\u{2019}t send. Tap one to see why." }
        if offline { return "They send by themselves when you\u{2019}re back online." }
        return "Waiting to send."
    }
}

/// A video chosen from the library, copied to a file of the app's own before the picker's goes away.
struct PickedMovie: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("pick-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}
