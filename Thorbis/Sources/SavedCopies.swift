import CryptoKit
import Foundation
import SwiftUI

/// Server answers for job, customer, estimate and invoice reads, kept on this phone so a tech
/// who opened their day with signal can still open every job, its customer and its paper in a
/// basement. Only the server's own JSON is kept, byte for byte; nothing is made up. A copy is
/// served only when the live read fails for lack of signal (or the app already knows it is
/// offline), and the screen then says "Saved on this phone · <time>".
///
/// Scoped per actor and workspace, complete file protection until first unlock, deleted on
/// sign-out. Money movement (payments, pay links, refunds) and media are never kept.
enum SavedCopies {
    /// Set around a pull to refresh: always ask the server, never reuse a read from moments ago.
    @TaskLocal static var liveOnly = false

    /// Reads worth keeping: a job's, customer's, estimate's or invoice's own record and lists.
    static func isKept(_ path: String, query: [URLQueryItem] = []) -> Bool {
        // The bare job and customer lists belong to the schedule's own cache (WorkspaceCache);
        // filtered lists (a customer's jobs, the Customers tab) are kept here.
        if path == "/v1/jobs" || path == "/v1/customers" { return query.contains { $0.name != "cursor" } }
        let prefixes = ["/v1/jobs/", "/v1/customers/", "/v1/estimates", "/v1/invoices"]
        guard prefixes.contains(where: { path.hasPrefix($0) }) else { return false }
        let excluded = ["/payments", "/pay-link", "/refund", "/media", "/photos", "/document", "/recording",
                        "/sms-consent", "/assignees"]
        return !excluded.contains(where: { path.contains($0) })
    }

    /// The disk file for one read. The name is a digest, so no customer data is in a filename.
    static func key(origin: String, path: String, query: [URLQueryItem]) -> String {
        let canonical = origin + path + "?" + query.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func scope(actorID: String, organizationID: String) -> String {
        "\(actorID)_\(organizationID)".filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}

/// The on-disk store. Reads are small and happen only without signal; writes go through one
/// serial queue, so a sign-out's `clearAll` always lands after any write already queued.
final class SavedCopyStore: @unchecked Sendable {
    static let shared = SavedCopyStore()
    private let directory: URL
    private let queue = DispatchQueue(label: "com.thorbis.field.saved-copies", qos: .utility)
    /// The largest single answer kept (a whole-workspace list can be bigger than is useful).
    private let maxBytes = 2 * 1024 * 1024

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.directory = base.appendingPathComponent("SavedCopies", isDirectory: true)
    }

    private func file(scope: String, key: String) -> URL {
        directory.appendingPathComponent(scope, isDirectory: true).appendingPathComponent("\(key).json")
    }

    func exists(scope: String, key: String) -> Bool {
        FileManager.default.fileExists(atPath: file(scope: scope, key: key).path)
    }

    func read(scope: String, key: String) -> (data: Data, savedAt: Date)? {
        let url = file(scope: scope, key: key)
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        let savedAt = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
        return (data, savedAt)
    }

    func write(_ data: Data, scope: String, key: String) {
        guard data.count <= maxBytes else { return }
        let url = file(scope: scope, key: key)
        queue.async {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch {
                // Only the offline copy is lost; the live answer was already used.
            }
        }
    }

    /// Copies older than two weeks are of no use on a job site; drop them when a workspace binds.
    func prune(scope: String, olderThan age: TimeInterval = 14 * 86_400) {
        let folder = directory.appendingPathComponent(scope, isDirectory: true)
        queue.async {
            let cutoff = Date().addingTimeInterval(-age)
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for url in files {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                if modified < cutoff { try? FileManager.default.removeItem(at: url) }
            }
        }
    }

    /// Sign-out. Runs after every queued write, and synchronously, so nothing survives it.
    func clearAll() {
        queue.sync { try? FileManager.default.removeItem(at: directory) }
    }
}

/// "Saved on this phone · 9:41 AM", the same quiet line the property history uses.
struct SavedCopyNote: View {
    let savedAt: Date?

    var body: some View {
        if let savedAt {
            HStack(spacing: 6) {
                Image(systemName: "iphone").font(.system(size: 12, weight: .medium)).accessibilityHidden(true)
                Text("Saved on this phone · \(Self.label(savedAt))")
            }
            .font(Theme.font(13)).foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.gutter).padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }

    static func label(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.tradeTime
            : "\(date.formatted(.dateTime.weekday(.abbreviated))) \(date.tradeTime)"
    }
}

extension APIClient {
    /// Customer names read six at a time (a technician's schedule refresh used to read up to 40
    /// one after another). Unreadable ones are left out, as before.
    func customerNames(_ ids: [String]) async -> [String: Customer] {
        var found: [String: Customer] = [:]
        for start in stride(from: 0, to: ids.count, by: 6) {
            let chunk = Array(ids[start..<min(start + 6, ids.count)])
            let read = await withTaskGroup(of: Customer?.self, returning: [Customer].self) { group in
                for id in chunk {
                    group.addTask { await self.customerName(id) }
                }
                var results: [Customer] = []
                for await customer in group { if let customer { results.append(customer) } }
                return results
            }
            for customer in read { found[customer.id] = customer }
        }
        return found
    }

    private func customerName(_ id: String) async -> Customer? {
        guard let record = try? await fieldCustomer(id) else { return nil }
        return Customer(id: record.id, name: record.name, archived: nil, createdAt: nil)
    }
}

extension APIClient {
    /// For reads that feed a customer's signature, a payment or an edit: a copy saved on this phone
    /// is refused as if there were no signal, so those flows only ever act on a live answer.
    func liveFieldEstimate(_ id: String) async throws -> EstimateRecord {
        let record = try await fieldEstimate(id)
        try requireLive("/v1/estimates/\(id)")
        return record
    }

    func liveFieldInvoice(_ id: String) async throws -> InvoiceRecord {
        let record = try await fieldInvoice(id)
        try requireLive("/v1/invoices/\(id)")
        return record
    }

    func liveFieldJob(_ id: String) async throws -> JobRecord {
        let record = try await SavedCopies.$liveOnly.withValue(true) { try await fieldJob(id) }
        try requireLive("/v1/jobs/\(id)")
        return record
    }

    /// The job's estimate links for a signature's membership check: a copy saved on this phone
    /// (served when the read drops) must never stand in for the server's answer.
    func liveFieldJobEstimateLinks(_ jobID: String) async throws -> [JobEstimateLink] {
        let links = try await fieldJobEstimateLinks(jobID)
        try requireLive("/v1/jobs/\(jobID)/estimates")
        return links
    }

    private func requireLive(_ path: String) throws {
        guard savedCopyDate(path) == nil else {
            throw Problem(title: "Network error", status: nil, detail: "This needs a connection. Try again when you have signal.")
        }
    }
}
