// The test bundle also compiles this file; there the shared types live in the app module.
#if WIDGET_TESTS
@testable import Thorbis
#endif
import ActivityKit
import SwiftUI
import WidgetKit

/// The job under way on the Lock Screen and in the Dynamic Island. The views live in
/// Shared/GlanceViews.swift so the app's DEBUG preview can draw them too.
struct JobLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JobActivityAttributes.self) { context in
            JobLockScreenView(attributes: context.attributes, state: context.state)
                // Paper 94: the card colour at 88% over the Lock Screen's blur.
                .activityBackgroundTint(WidgetInk.panel.opacity(0.88))
                .activitySystemActionForegroundColor(WidgetInk.ink)
                .widgetURL(JobActivityLink.url(jobID: context.attributes.jobID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    GlanceStatusWord(text: context.state.label, tint: WidgetInk.tint(context.state.status, island: true),
                                     size: 15, textColor: WidgetInk.Island.text)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedText(since: context.state.since)
                        .font(WidgetInk.number(15, relativeTo: .subheadline))
                        .foregroundStyle(WidgetInk.Island.text)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandExpandedBottom(attributes: context.attributes, state: context.state)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                // Paper 94: the status mark alone beside the timer; VoiceOver still gets the word,
                // and the expanded island and the Lock Screen card spell it out.
                Circle()
                    .fill(WidgetInk.tint(context.state.status, island: true))
                    .frame(width: 8, height: 8)
                    .padding(.leading, 4)
                    .accessibilityLabel(context.state.shortLabel)
            } compactTrailing: {
                ElapsedText(since: context.state.since)
                    .font(WidgetInk.number(14, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(WidgetInk.Island.text)
                    .frame(maxWidth: 52)
            } minimal: {
                // Too small for a word at a legible size: the step's symbol, tinted, with the word
                // as its spoken label. The compact and expanded views carry the word.
                Image(systemName: context.state.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WidgetInk.tint(context.state.status, island: true))
                    .accessibilityLabel(context.state.label)
            }
            .widgetURL(JobActivityLink.url(jobID: context.attributes.jobID))
            .keylineTint(WidgetInk.Island.accent)
        }
    }
}

#Preview("Lock Screen", as: .content, using: JobActivityAttributes(jobID: "1", jobNumber: "JOB-2214", title: "AC not cooling",
                                                                     customer: "Danielle Marlowe", address: "412 Birchwood Ln",
                                                                     access: "Gate code · Dog on site")) {
    JobLiveActivityWidget()
} contentStates: {
    JobActivityAttributes.ContentState(status: "en_route", since: .now.addingTimeInterval(-420), waitingToSync: false)
    JobActivityAttributes.ContentState(status: "arrived", since: .now.addingTimeInterval(-300), waitingToSync: false)
    JobActivityAttributes.ContentState(status: "in_progress", since: .now.addingTimeInterval(-1800), waitingToSync: true)
}
