#if DEBUG
import Darwin
import Foundation

/// BYR-1841, DEBUG only: measures each opening of Customer view on its Estimates page. At three
/// points of each opening it writes one NSLog line: CPU time of the main thread, of the process and
/// of every other thread since the previous line, how many times six view bodies have run, and the
/// footer height writes. On only under the Estimates UI tests' launch flag; otherwise every call
/// returns at once. It logs numbers, thread names and fixed labels only, never anything about a
/// person, a company, a job or an estimate.
/// Nothing here ships in Release: the whole file and every call site sit inside `#if DEBUG`.
enum FirstOpenProbe {
    /// The bodies counted. `count` is one integer increment per body run.
    enum Counted: Int, CaseIterable {
        case handoff, documents, owner, container, unlock, jobDetail
        var label: String {
            switch self {
            case .handoff: "handoff"
            case .documents: "documents"
            case .owner: "owner"
            case .container: "container"
            case .unlock: "unlock"
            case .jobDetail: "jobdetail"
            }
        }
    }

    /// a: just before `approving = true` (door opening or the Review estimates button);
    /// b: the Estimates page's onAppear; c: the first turn of its keyed task.
    enum Point: String {
        case a = "a", aButton = "a-button", b = "b", c = "c"
    }

    static let enabled = PaperPreview.isJobEstimateHandoff

    nonisolated(unsafe) private static var counts = [Int](repeating: 0, count: Counted.allCases.count)
    nonisolated(unsafe) private static var footerWrites = 0
    /// Count of footer writes when this opening's a line ran; footer_first holds the 8 after it.
    nonisolated(unsafe) private static var footerOpenStart = 0
    nonisolated(unsafe) private static var footerFirst = [Double](repeating: 0, count: 8)
    nonisolated(unsafe) private static var opens = 0
    nonisolated(unsafe) private static var marks = 0
    nonisolated(unsafe) private static var mainPort: UInt32 = 0
    nonisolated(unsafe) private static var anchorMs = -1
    /// Every live thread at the previous line, by Mach port, for the per-thread deltas.
    nonisolated(unsafe) private static var previous: [UInt32: ThreadTime] = [:]
    nonisolated(unsafe) private static var previousUpMs = -1
    nonisolated(unsafe) private static var previousMainMs = -1
    nonisolated(unsafe) private static var previousProcMs = -1

    static func count(_ body: Counted) {
        guard enabled else { return }
        if anchorMs < 0 { anchorMs = milliseconds(ProcessInfo.processInfo.systemUptime) }
        counts[body.rawValue] &+= 1
    }

    static func footer(_ height: Double) {
        guard enabled else { return }
        let index = footerWrites - footerOpenStart
        if index >= 0, index < footerFirst.count { footerFirst[index] = height }
        footerWrites &+= 1
    }

    static func mark(_ point: Point) {
        guard enabled else { return }
        let uptimeMs = milliseconds(ProcessInfo.processInfo.systemUptime)
        if point == .a || point == .aButton {
            opens += 1
            footerOpenStart = footerWrites
        }
        marks += 1
        let onMain = pthread_main_np() != 0
        if onMain { mainPort = pthread_mach_thread_np(pthread_self()) }
        let threads = threadTimes()
        let processMs = processMilliseconds()
        NSLog("%@", line(point: point, onMain: onMain, uptimeMs: uptimeMs, threads: threads, processMs: processMs))
        previous = Dictionary(threads.map { ($0.port, $0) }, uniquingKeysWith: { first, _ in first })
        previousUpMs = uptimeMs
        previousMainMs = threads.first(where: { $0.port == mainPort && mainPort != 0 })?.ms ?? -1
        previousProcMs = processMs
    }

    // MARK: Line

    struct ThreadTime {
        let port: UInt32
        let name: String
        let ms: Int
    }

    struct ThreadDelta {
        let thread: ThreadTime
        let ms: Int
    }

    static func line(point: Point, onMain: Bool, uptimeMs: Int, threads: [ThreadTime], processMs: Int) -> String {
        let mainMs = threads.first(where: { $0.port == mainPort && mainPort != 0 })?.ms ?? -1
        // Deltas since the previous line for every live thread but main. A port seen at the previous
        // line counts as the same thread only with the same name and no less CPU; otherwise it is new
        // (a port name can be reused after a thread exits) and its whole CPU time is its delta.
        var deltas: [ThreadDelta] = []
        var fresh = 0
        var matched = 0
        for thread in threads {
            let old = previous[thread.port]
            let same = old.map { $0.name == thread.name && $0.ms <= thread.ms } ?? false
            if same { matched += 1 }
            if thread.port == mainPort && mainPort != 0 { continue }
            if same, let old {
                deltas.append(ThreadDelta(thread: thread, ms: thread.ms - old.ms))
            } else {
                fresh += 1
                deltas.append(ThreadDelta(thread: thread, ms: thread.ms))
            }
        }
        let gone = previous.count - matched
        let ranked = deltas.sorted { $0.ms > $1.ms }
        let top = ranked.prefix(8)
        let topList = top.map { "\($0.thread.port)/\($0.thread.name)=\($0.ms):\($0.thread.ms)" }.joined(separator: ",")
        let restMs = ranked.dropFirst(8).reduce(0) { $0 + $1.ms }
        let restCount = max(0, ranked.count - 8)
        let first = previous.isEmpty ? 1 : 0
        let dUp = previousUpMs < 0 ? -1 : uptimeMs - previousUpMs
        let dMain = previousMainMs < 0 || mainMs < 0 ? -1 : mainMs - previousMainMs
        let dProc = previousProcMs < 0 || processMs < 0 ? -1 : processMs - previousProcMs
        let bodies = Counted.allCases.map { "\($0.label):\(counts[$0.rawValue])" }.joined(separator: ",")
        let openWrites = footerWrites - footerOpenStart
        let firstValues = footerFirst.prefix(max(0, min(openWrites, footerFirst.count))).map(tenths).joined(separator: ",")
        let sinceFirstBody = anchorMs < 0 ? -1 : uptimeMs - anchorMs
        return "[first-open-probe] v=2 point=\(point.rawValue) open=\(opens) mark=\(marks) onmain=\(onMain ? 1 : 0)"
            + " up_ms=\(uptimeMs) since_first_body_ms=\(sinceFirstBody) main_ms=\(mainMs) proc_ms=\(processMs)"
            + " threads=\(threads.count) threads_ms=\(threads.reduce(0) { $0 + $1.ms })"
            + " first_mark=\(first) d_up_ms=\(dUp) d_main_ms=\(dMain) d_proc_ms=\(dProc)"
            + " d_top=\(topList.isEmpty ? "-" : topList) d_rest_ms=\(restMs) d_rest_n=\(restCount)"
            + " d_new=\(fresh) d_gone=\(gone)"
            + " body=\(bodies) footer_writes=\(footerWrites) footer_open_writes=\(openWrites)"
            + " footer_first=\(firstValues.isEmpty ? "-" : firstValues)"
            + " ag_async=\(asyncLayouts)"
    }

    /// Read only, never set here: whether a test launched the app with AttributeGraph's async layout
    /// switch, so a later A/B run can be told apart in the same lines. Fixed values only.
    static let asyncLayouts: String = {
        guard let value = ProcessInfo.processInfo.environment["AG_ASYNC_LAYOUTS"] else { return "unset" }
        return value == "0" || value == "1" ? value : "other"
    }()

    static func milliseconds(_ seconds: Double) -> Int { Int((seconds * 1000).rounded()) }

    static func tenths(_ value: Double) -> String {
        guard value.isFinite, abs(value) < 1_000_000 else { return "nan" }
        let scaled = Int((abs(value) * 10).rounded())
        return "\(value < 0 && scaled != 0 ? "-" : "")\(scaled / 10).\(scaled % 10)"
    }

    /// Thread names are system labels; anything else is replaced so a line stays one greppable token.
    static func clean(_ raw: [Int8]) -> String {
        let bytes = raw.prefix { $0 != 0 }.prefix(32).map { UInt8(bitPattern: $0) }
        let text = String(decoding: bytes, as: UTF8.self)
        let kept = text.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_") ? $0 : "_" }
        return kept.isEmpty ? "-" : String(kept)
    }

    // MARK: CPU time

    /// This task's own Mach port. Swift 6 refuses a direct read of the C global `mach_task_self_`
    /// as shared mutable state, so its value is read once through dlsym. -2 is RTLD_DEFAULT, which
    /// dlfcn.h defines as `((void *) -2)`, a macro Swift does not import. nil turns the thread reads off.
    static let taskPort: mach_port_t? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "mach_task_self_") else { return nil }
        return symbol.load(as: mach_port_t.self)
    }()

    /// User plus system time of every live thread, from task_threads and THREAD_BASIC_INFO, spelled
    /// as Sentry's SentrySystemWrapper.cpuUsage, with the same cleanup of the list and its ports.
    static func threadTimes() -> [ThreadTime] {
        guard let task = taskPort else { return [] }
        var count: mach_msg_type_number_t = 0
        var list: thread_act_array_t?
        guard task_threads(task, &list, &count) == KERN_SUCCESS, let threadList = list else { return [] }
        defer {
            for i in 0..<Int(count) {
                mach_port_deallocate(task, threadList[i])
            }
            vm_deallocate(task, vm_address_t(bitPattern: threadList), vm_size_t(MemoryLayout<thread_t>.size) * vm_size_t(count))
        }
        var result: [ThreadTime] = []
        result.reserveCapacity(Int(count))
        for i in 0..<Int(count) {
            let thread = threadList[i]
            var infoSize = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
            var data = thread_basic_info_data_t()
            let status = withUnsafeMutablePointer(to: &data) { dataPtr in
                dataPtr.withMemoryRebound(to: integer_t.self, capacity: Int(infoSize)) { rawPtr in
                    thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), rawPtr, &infoSize)
                }
            }
            guard status == KERN_SUCCESS else { continue }
            let micros = (Int(data.user_time.seconds) + Int(data.system_time.seconds)) * 1_000_000
                + Int(data.user_time.microseconds) + Int(data.system_time.microseconds)
            // Names as EmergeTools' ETTrace reads them; an unnamed worker is "-", the main thread "main".
            var name = "-"
            if thread == mainPort && mainPort != 0 {
                name = "main"
            } else if let pthread = pthread_from_mach_thread_np(thread) {
                var buffer = [Int8](repeating: 0, count: 256)
                if pthread_getname_np(pthread, &buffer, buffer.count) == 0 { name = clean(buffer) }
            }
            result.append(ThreadTime(port: thread, name: name, ms: (micros + 500) / 1000))
        }
        return result
    }

    /// Whole process, threads that have ended included.
    static func processMilliseconds() -> Int {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return -1 }
        let micros = (Int(usage.ru_utime.tv_sec) + Int(usage.ru_stime.tv_sec)) * 1_000_000
            + Int(usage.ru_utime.tv_usec) + Int(usage.ru_stime.tv_usec)
        return (micros + 500) / 1000
    }
}
#endif
