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

/// Opens a job (or the schedule when `jobID` is empty) from a control or widget that has no
/// step to take. Opens the app, so it performs in the app's process.
struct OpenJobIntent: AppIntent {
    static let title: LocalizedStringResource = "Open job"
    static let description = IntentDescription("Opens a job in Thorbis.")
    static let isDiscoverable = false
    static let openAppWhenRun = true

    @Parameter(title: "Job") var jobID: String

    init() {}

    init(jobID: String) {
        self.jobID = jobID
    }

    func perform() async throws -> some IntentResult {
        #if !THORBIS_WIDGET_EXTENSION
        await JobStepIntentRunner.open(jobID: jobID)
        #endif
        return .result()
    }
}
