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

struct ThorbisShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenNextJobIntent(),
                    phrases: ["Open my next job in \(.applicationName)",
                              "What's my next job in \(.applicationName)",
                              "Next \(.applicationName) job"],
                    shortTitle: "Next job",
                    systemImageName: "wrench.and.screwdriver")
        AppShortcut(intent: OpenScheduleIntent(),
                    phrases: ["Show my schedule in \(.applicationName)",
                              "Open my \(.applicationName) schedule"],
                    shortTitle: "Schedule",
                    systemImageName: "calendar")
    }
}
