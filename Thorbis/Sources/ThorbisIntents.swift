import AppIntents
import Foundation

/// "Open my next job": Siri, Spotlight, Shortcuts and the Action button land on the job under way
/// (or the next booked one) the same way a Live Activity tap does.
struct OpenNextJobIntent: AppIntent {
    static let title: LocalizedStringResource = "Open my next job"
    static let description = IntentDescription("Opens the job you're working on, or your next booked job.")

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "thorbis://job/\(JobActivityLink.nextJob)")!))
    }
}

/// "Show my schedule": opens the Schedule tab.
struct OpenScheduleIntent: AppIntent {
    static let title: LocalizedStringResource = "Show my schedule"
    static let description = IntentDescription("Opens today's schedule in Thorbis.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "thorbis://schedule")!))
    }
}

/// "Search Thorbis": Siri asks what to find, then the app opens search with that text typed in.
/// Results come from the signed-in workspace only, the same as typing in the app.
struct SearchThorbisIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Thorbis"
    static let description = IntentDescription("Searches your jobs and customers in Thorbis.")
    static let openAppWhenRun = true

    @Parameter(title: "Search for", requestValueDialog: "What do you want to find?")
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(SearchLink.url(query: query)))
    }
}

struct ThorbisShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenNextJobIntent(),
                    phrases: ["Show my next job in \(.applicationName)",
                              "Open my next job in \(.applicationName)",
                              "What's my next job in \(.applicationName)",
                              "Next \(.applicationName) job"],
                    shortTitle: "Next job",
                    systemImageName: "wrench.and.screwdriver")
        AppShortcut(intent: OpenScheduleIntent(),
                    phrases: ["Open my schedule in \(.applicationName)",
                              "Show my schedule in \(.applicationName)",
                              "Open my \(.applicationName) schedule"],
                    shortTitle: "Schedule",
                    systemImageName: "calendar")
        // App Shortcut phrases can't carry free text, so Siri asks for the search words next.
        AppShortcut(intent: SearchThorbisIntent(),
                    phrases: ["Search \(.applicationName)",
                              "Search in \(.applicationName)",
                              "Find something in \(.applicationName)"],
                    shortTitle: "Search",
                    systemImageName: "magnifyingglass")
    }
}

/// `thorbis://search?q=<words>`: opens search with the words typed in.
enum SearchLink {
    static func url(query: String) -> URL {
        var components = URLComponents()
        components.scheme = "thorbis"
        components.host = "search"
        components.queryItems = [URLQueryItem(name: "q", value: String(query.prefix(200)))]
        return components.url ?? URL(string: "thorbis://search")!
    }

    /// The words to search for; empty opens search with nothing typed. Nil when not a search link.
    static func query(from url: URL) -> String? {
        guard url.scheme == "thorbis", url.host() == "search" else { return nil }
        let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value ?? ""
        return String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
    }
}
