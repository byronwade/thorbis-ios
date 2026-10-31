import Foundation
import Network

/// Watches the device's network path so the app can resync the moment signal returns.
@MainActor
final class ConnectivityMonitor: ObservableObject {
    @Published private(set) var isConnected = true
    var onReconnect: (() -> Void)?
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                guard let self, self.isConnected != connected else { return }
                self.isConnected = connected
                if connected { self.onReconnect?() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.thorbis.field.connectivity"))
    }

    deinit { monitor.cancel() }
}

/// The last jobs and customers the server returned for one actor in one workspace,
/// kept on disk (complete file protection until first unlock) so the schedule opens
/// without signal. Cleared on sign-out.
struct WorkspaceCache {
    struct Contents: Codable {
        let savedAt: Date
        let jobs: [Job]
        let customers: [Customer]
    }

    private let directory: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.directory = base.appendingPathComponent("WorkspaceCache", isDirectory: true)
    }

    private func file(actorID: String, organizationID: String) -> URL {
        let safe = "\(actorID)_\(organizationID)".filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return directory.appendingPathComponent("\(safe).json")
    }

    func load(actorID: String, organizationID: String) -> Contents? {
        guard let data = try? Data(contentsOf: file(actorID: actorID, organizationID: organizationID)) else { return nil }
        return try? JSONDecoder().decode(Contents.self, from: data)
    }

    func save(_ contents: Contents, actorID: String, organizationID: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(contents)
            try data.write(to: file(actorID: actorID, organizationID: organizationID),
                           options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // A cache write failure only costs the offline copy; live data is unaffected.
        }
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Job details and notes as last read, so a job opened before still opens without signal.
enum JobDetailCache {
    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JobDetailCache", isDirectory: true)
    }

    private static func write<T: Encodable>(_ value: T, _ name: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: directory.appendingPathComponent(name),
                                                  options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {}
    }

    private static func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        (try? Data(contentsOf: directory.appendingPathComponent(name))).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    static func save(_ job: JobRecord) { write(job, "\(job.id).job.json") }
    static func save(notes: [JobNoteRecord], jobID: String) { write(notes, "\(jobID).notes.json") }
    static func job(_ id: String) -> JobRecord? { read(JobRecord.self, "\(id).job.json") }
    static func save(stop: NextStopPlace) { write(stop, "\(stop.jobID).stop.json") }
    static func stop(_ id: String) -> NextStopPlace? { read(NextStopPlace.self, "\(id).stop.json") }
    static func notes(_ id: String) -> [JobNoteRecord] { read([JobNoteRecord].self, "\(id).notes.json") ?? [] }
    static func clearAll() { try? FileManager.default.removeItem(at: directory) }
}
