import AppIntents
import SwiftUI
import WidgetKit

/// Control Center and Action button: the next job's next step (On my way, Arrived, Start), named
/// with the street it applies to. It runs the same `AdvanceJobStepIntent` as the Lock Screen card,
/// in the app's process. Working, paused or nothing booked: there is no step to take, and the
/// "Next job" control opens the app instead.
struct NextStepControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: TodaySnapshot.controlKind, provider: Provider()) { stop in
            // One intent type per control. With no step to take the target is empty and the app
            // answers "Open the job to make this change"; the label already says there's none.
            ControlWidgetButton(action: AdvanceJobStepIntent(jobID: stop.jobID ?? "", target: stop.step?.target ?? "")) {
                Label(stop.step?.buttonTitle ?? "No step to take", systemImage: stop.step?.symbol ?? "checkmark.circle")
                Text(stop.headline)
            }
        }
        .displayName("Next step")
        .description("On my way, Arrived or Start for your next job.")
    }

    struct Stop: Sendable {
        let jobID: String?
        let step: JobNextStep?
        let headline: String
    }

    struct Provider: ControlValueProvider {
        var previewValue: Stop {
            Stop(jobID: nil, step: JobNextStep.after("dispatched"), headline: "Your next job")
        }

        func currentValue() async throws -> Stop {
            guard let snapshot = TodaySnapshot.load() else {
                return Stop(jobID: nil, step: nil, headline: "Open Thorbis to sign in")
            }
            guard let next = snapshot.upcoming(on: .now).first else {
                return Stop(jobID: nil, step: nil, headline: "No more jobs today")
            }
            return Stop(jobID: next.id, step: JobNextStep.after(next.status), headline: next.headline)
        }
    }
}

/// Control Center and Action button: open the job under way, or the next booked one.
struct NextJobControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.thorbis.field.next-job") {
            ControlWidgetButton(action: OpenJobIntent(jobID: JobActivityLink.nextJob)) {
                Label("Next job", systemImage: "wrench.and.screwdriver")
            }
        }
        .displayName("Next job")
        .description("Opens the job you're on, or your next booked job.")
    }
}
