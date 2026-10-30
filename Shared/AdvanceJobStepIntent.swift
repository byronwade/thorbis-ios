import AppIntents
import Foundation

/// The Lock Screen and Dynamic Island button that moves a job one field step forward.
///
/// A LiveActivityIntent runs in the app's process, never the widget extension's, so it uses the
/// app's signed-in session, the same progress call and the same offline outbox as the job screen.
/// The extension compiles this type only to draw `Button(intent:)`.
struct AdvanceJobStepIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Move job to its next step"
    static let description = IntentDescription("Marks On my way, Arrived or Started work on the job under way.")
    static let isDiscoverable = false

    @Parameter(title: "Job") var jobID: String
    /// The status the step moves to: en_route, arrived or in_progress.
    @Parameter(title: "Step") var target: String

    init() {}

    init(jobID: String, target: String) {
        self.jobID = jobID
        self.target = target
    }

    func perform() async throws -> some IntentResult {
        #if !THORBIS_WIDGET_EXTENSION
        try await JobStepIntentRunner.run(jobID: jobID, target: target)
        #endif
        return .result()
    }
}
