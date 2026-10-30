// The test bundle also compiles this file; there the shared types live in the app module.
#if WIDGET_TESTS
@testable import Thorbis
#endif
import ActivityKit
import SwiftUI
import WidgetKit

/// Paper tokens the extension needs; it cannot see the app's Theme.
private enum Ink {
    static let ground = Color(red: 0x1F / 255, green: 0x1F / 255, blue: 0x1F / 255)
    static let brand = Color(red: 0x2F / 255, green: 0x6B / 255, blue: 0xFF / 255)
    static let brandText = Color(red: 0x52 / 255, green: 0x85 / 255, blue: 0xFF / 255)
    static let warning = Color(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255)
    static let muted = Color.white.opacity(0.6)
    static let track = Color.white.opacity(0.14)

    static func tint(_ state: JobActivityAttributes.ContentState) -> Color {
        state.status == "en_route" ? brandText : warning
    }
}

struct JobLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JobActivityAttributes.self) { context in
            JobLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Ink.ground)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(JobActivityLink.url(jobID: context.attributes.jobID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.label, systemImage: context.state.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Ink.tint(context.state))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedText(since: context.state.since)
                        .font(.subheadline.monospacedDigit().weight(.medium))
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.state.waitingToSync ? "Waiting to sync" : place(context.attributes))
                            .font(.caption)
                            .foregroundStyle(context.state.waitingToSync ? Ink.warning : Ink.muted)
                            .lineLimit(1)
                        StepTrack(step: context.state.step, tint: Ink.tint(context.state))
                        NextStepButton(jobID: context.attributes.jobID, state: context.state)
                    }
                }
            } compactLeading: {
                // The status is always a word; the color only reinforces it.
                Text(context.state.shortLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Ink.tint(context.state))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } compactTrailing: {
                ElapsedText(since: context.state.since)
                    .font(.caption.monospacedDigit().weight(.medium))
                    .frame(maxWidth: 52)
            } minimal: {
                Text(context.state.shortLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Ink.tint(context.state))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityLabel(context.state.label)
            }
            .widgetURL(JobActivityLink.url(jobID: context.attributes.jobID))
            .keylineTint(Ink.brand)
        }
    }
}

private func place(_ attributes: JobActivityAttributes) -> String {
    [attributes.customer, attributes.address].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
}

private struct ElapsedText: View {
    let since: Date
    var body: some View {
        Text(timerInterval: since...Date.distantFuture, countsDown: false)
            .multilineTextAlignment(.trailing)
    }
}

struct JobLockScreenView: View {
    let attributes: JobActivityAttributes
    let state: JobActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: state.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(state.status == "en_route" ? Ink.brand : Ink.warning))
                Text(state.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Ink.tint(state))
                Spacer(minLength: 8)
                ElapsedText(since: state.since)
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 90, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(attributes.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(state.waitingToSync ? "\(attributes.jobNumber) · Waiting to sync" : "\(attributes.jobNumber) · \(place(attributes))")
                    .font(.caption)
                    .foregroundStyle(Ink.muted)
                    .lineLimit(1)
            }
            StepTrack(step: state.step, tint: Ink.tint(state))
            NextStepButton(jobID: attributes.jobID, state: state)
        }
        .padding(16)
    }
}

/// The one forward step (On my way, Mark arrived, Start work). It runs in the app process and the
/// card only changes once the server or the phone's outbox has the step; nothing shows success early.
struct NextStepButton: View {
    let jobID: String
    let state: JobActivityAttributes.ContentState

    var body: some View {
        if let next = state.nextStep {
            Button(intent: AdvanceJobStepIntent(jobID: jobID, target: next.target)) {
                Label(next.title, systemImage: next.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(Ink.brand))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Updates this job's status.")
        }
    }
}

/// Driving → On site → Working, the three field steps in order.
private struct StepTrack: View {
    let step: Int
    let tint: Color
    private let names = ["Driving", "On site", "Working"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(names.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 4) {
                    Capsule()
                        .fill(index <= step ? tint : Ink.track)
                        .frame(height: 4)
                    Text(names[index])
                        .font(.caption2.weight(index == step ? .semibold : .regular))
                        .foregroundStyle(index == step ? .white : Ink.muted)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step + 1) of 3, \(names[step])")
    }
}

#Preview("Lock Screen", as: .content, using: JobActivityAttributes(jobID: "1", jobNumber: "JOB-2214", title: "AC not cooling",
                                                                     customer: "Danielle Marlowe", address: "412 Birchwood Ln")) {
    JobLiveActivityWidget()
} contentStates: {
    JobActivityAttributes.ContentState(status: "en_route", since: .now.addingTimeInterval(-420), waitingToSync: false)
    JobActivityAttributes.ContentState(status: "in_progress", since: .now.addingTimeInterval(-1800), waitingToSync: true)
}
