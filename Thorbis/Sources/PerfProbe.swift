import Foundation
import os

/// DEBUG-only measurement hooks for the performance pass. Nothing here ships in Release.
/// `--perf-log` prints one line per API request and a timing line per measured section to
/// stdout, so `simctl launch --stdout=` can capture them; `--perf-probe` also runs the date
/// micro-benchmark once at launch.
enum PerfProbe {
    #if DEBUG
    static let enabled = ProcessInfo.processInfo.arguments.contains("--perf-log")
        || ProcessInfo.processInfo.arguments.contains("--perf-probe")
    static let signposter = OSSignposter(subsystem: "com.thorbis.field", category: "perf")

    static func request(_ method: String, _ path: String, note: String? = nil) {
        guard enabled else { return }
        print("[perf] \(method) \(path)\(note.map { " (\($0))" } ?? "")")
    }

    static func measure<T>(_ label: StaticString, _ body: () throws -> T) rethrows -> T {
        guard enabled else { return try body() }
        let state = signposter.beginInterval(label)
        let clock = ContinuousClock()
        let start = clock.now
        defer {
            signposter.endInterval(label, state)
            print("[perf] \(label) \(clock.now - start)")
        }
        return try body()
    }

    static func measure<T>(_ label: StaticString, isolation: isolated (any Actor)? = #isolation, _ body: () async throws -> T) async rethrows -> T {
        guard enabled else { return try await body() }
        let state = signposter.beginInterval(label)
        let clock = ContinuousClock()
        let start = clock.now
        defer {
            signposter.endInterval(label, state)
            print("[perf] \(label) \(clock.now - start)")
        }
        return try await body()
    }

    /// A/B of the timestamp parser used in list sorts: the old formatter-per-call shape against
    /// `JobFiltering.date`, over the same 2,000 server timestamps, and a 300-job sort by time.
    static func runDateBenchmark() {
        guard ProcessInfo.processInfo.arguments.contains("--perf-probe") else { return }
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamps = (0..<2000).map { iso.string(from: base.addingTimeInterval(Double($0 * 977))) }
        func legacy(_ raw: String?) -> Date? {
            guard let raw else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: raw) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: raw)
        }
        let clock = ContinuousClock()
        for round in 1...3 {
            var sink = 0.0
            let old = clock.measure { for stamp in stamps { sink += legacy(stamp)?.timeIntervalSince1970 ?? 0 } }
            let new = clock.measure { for stamp in stamps { sink += JobFiltering.date(stamp)?.timeIntervalSince1970 ?? 0 } }
            let jobs = stamps.prefix(300).shuffled()
            let oldSort = clock.measure {
                _ = jobs.sorted { (legacy($0) ?? .distantFuture) < (legacy($1) ?? .distantFuture) }
            }
            let newSort = clock.measure {
                _ = jobs.sorted { (JobFiltering.date($0) ?? .distantFuture) < (JobFiltering.date($1) ?? .distantFuture) }
            }
            // Today's schedule over 300 jobs: the old filter + per-comparison parse against JobFiltering.schedule.
            let today = Date()
            let board = (0..<300).map { index in
                Job(id: "job-\(index)", customerId: nil, title: "Job \(index)", status: "scheduled", createdAt: nil, updatedAt: nil,
                    allowedTransitions: nil, scheduledFor: iso.string(from: today.addingTimeInterval(Double((index * 7919) % 600))))
            }
            let oldSchedule = clock.measure {
                _ = board.filter { job in
                    guard let scheduled = legacy(job.scheduledFor) else { return false }
                    return Calendar.current.isDate(scheduled, inSameDayAs: today)
                }.sorted { (legacy($0.scheduledFor) ?? .distantFuture) < (legacy($1.scheduledFor) ?? .distantFuture) }
            }
            let newSchedule = clock.measure { _ = JobFiltering.schedule(board, range: .today, now: today) }
            print("[perf] date-parse round \(round): 2000 parses legacy=\(old) current=\(new); 300-stamp sort legacy=\(oldSort) current=\(newSort); today's schedule of 300 jobs legacy=\(oldSchedule) current=\(newSchedule) (\(Int(sink) % 7))")
        }
    }
    #else
    static func request(_ method: String, _ path: String, note: String? = nil) {}
    static func measure<T>(_ label: StaticString, _ body: () throws -> T) rethrows -> T { try body() }
    static func measure<T>(_ label: StaticString, isolation: isolated (any Actor)? = #isolation, _ body: () async throws -> T) async rethrows -> T { try await body() }
    static func runDateBenchmark() {}
    #endif
}
