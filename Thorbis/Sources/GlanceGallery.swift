#if DEBUG
import SwiftUI
import WidgetKit

/// DEBUG only (`--paper-preview --paper-preview-screen glance-widgets|glance-lock|glance-island`):
/// draws the widget, Lock Screen and Dynamic Island views at their system sizes so they can be
/// screenshotted in the simulator. The fixtures are preview rows, never shown to a signed-in person.
struct GlanceGallery: View {
    let screen: String

    private static let items = [
        TodaySnapshot.Item(id: "1", at: Calendar.current.date(bySettingHour: 10, minute: 30, second: 0, of: .now),
                           title: "AC not cooling", customer: "Danielle Marlowe", status: "dispatched", street: "412 Birchwood Ln"),
        TodaySnapshot.Item(id: "2", at: Calendar.current.date(bySettingHour: 12, minute: 15, second: 0, of: .now),
                           title: "Kitchen sink backup", customer: "Alex Petrov", status: "scheduled", street: "88 Pine St"),
        TodaySnapshot.Item(id: "3", at: Calendar.current.date(bySettingHour: 14, minute: 30, second: 0, of: .now),
                           title: "Outlet replacement", customer: "Elena Alvarez", status: "scheduled"),
        TodaySnapshot.Item(id: "4", at: Calendar.current.date(bySettingHour: 16, minute: 0, second: 0, of: .now),
                           title: "AC recheck", customer: "Mei Nakamura", status: "scheduled", street: "1907 Larkspur Ct"),
    ]
    private static let entry = TodayEntry(date: .now, items: items, signedOut: false, progress: .visit(3, of: 6))
    private static let working = TodayEntry(date: .now, items: [TodaySnapshot.Item(id: "9", at: nil, title: "Water heater leak",
                                                                                   customer: "David Chen", status: "in_progress",
                                                                                   street: "27 Orchard Way")] + items.dropFirst(),
                                            signedOut: false, progress: .visit(2, of: 6))
    private static let attributes = JobActivityAttributes(jobID: "1", jobNumber: "JOB-2214", title: "AC not cooling",
                                                          customer: "Danielle Marlowe", address: "412 Birchwood Ln",
                                                          access: "Gate code · Dog on site",
                                                          scheduledFor: Calendar.current.date(bySettingHour: 10, minute: 30, second: 0, of: .now))
    private static func state(_ status: String, minutes: Double, waiting: Bool = false) -> JobActivityAttributes.ContentState {
        .init(status: status, since: .now.addingTimeInterval(-minutes * 60), waitingToSync: waiting)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch screen {
                case "glance-lock": lock
                case "glance-island": island
                default: widgets
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(screen == "glance-widgets" ? Color(white: 0.55) : Color(white: 0.18))
    }

    // MARK: Home Screen

    @ViewBuilder private var widgets: some View {
        HStack(spacing: 22) {
            widget(TodayJobsView(entry: Self.entry, previewFamily: .systemSmall), width: 170, height: 170)
            widget(NextStopView(entry: Self.entry), width: 170, height: 170)
        }
        widget(TodayJobsView(entry: Self.entry, previewFamily: .systemMedium), width: 364, height: 170)
        widget(TodayJobsView(entry: Self.working, previewFamily: .systemLarge), width: 364, height: 382)
        HStack(spacing: 22) {
            widget(NextStopView(entry: Self.working), width: 170, height: 170)
            widget(TodayJobsView(entry: TodayEntry(date: .now, items: [], signedOut: false, progress: .allDone(6)),
                                 previewFamily: .systemSmall), width: 170, height: 170)
        }
        .environment(\.colorScheme, .dark)
    }

    private func widget(_ content: some View, width: CGFloat, height: CGFloat) -> some View {
        content
            .padding(16)
            .frame(width: width, height: height)
            .background(WidgetInk.ground)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: Lock Screen

    @ViewBuilder private var lock: some View {
        HStack(spacing: 12) {
            accessory(TodayJobsView(entry: Self.entry, previewFamily: .accessoryCircular), width: 72, height: 72)
            accessory(TodayJobsView(entry: Self.entry, previewFamily: .accessoryRectangular), width: 172, height: 72)
        }
        TodayJobsView(entry: Self.entry, previewFamily: .accessoryInline)
            .font(WidgetInk.font(15)).foregroundStyle(.white)
        activity(Self.state("en_route", minutes: 7))
        activity(Self.state("arrived", minutes: 4))
        activity(Self.state("in_progress", minutes: 38, waiting: true))
            .environment(\.colorScheme, .dark)
    }

    private func accessory(_ content: some View, width: CGFloat, height: CGFloat) -> some View {
        content
            .foregroundStyle(.white)
            .frame(width: width, height: height)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func activity(_ state: JobActivityAttributes.ContentState) -> some View {
        JobLockScreenView(attributes: Self.attributes, state: state)
            .frame(width: 370)
            .background(WidgetInk.ground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: Dynamic Island

    @ViewBuilder private var island: some View {
        let driving = Self.state("en_route", minutes: 7)
        let onSite = Self.state("arrived", minutes: 4)
        Text("Compact").font(WidgetInk.font(13, weight: .medium)).foregroundStyle(.white.opacity(0.7))
        HStack {
            GlanceStatusWord(text: driving.shortLabel, tint: WidgetInk.tint(driving.status, island: true), size: 13,
                             textColor: WidgetInk.Island.text)
                .fixedSize()
            Spacer(minLength: 126)
            ElapsedText(since: driving.since).font(WidgetInk.number(13)).foregroundStyle(.white).frame(maxWidth: 52)
        }
        .padding(.horizontal, 14).frame(width: 290, height: 37).background(Capsule().fill(.black))
        Text("Minimal").font(WidgetInk.font(13, weight: .medium)).foregroundStyle(.white.opacity(0.7))
        Image(systemName: onSite.symbol).font(.system(size: 12, weight: .medium))
            .foregroundStyle(WidgetInk.tint(onSite.status, island: true))
            .frame(width: 37, height: 37).background(Circle().fill(.black))
        Text("Expanded").font(WidgetInk.font(13, weight: .medium)).foregroundStyle(.white.opacity(0.7))
        expanded(driving)
        expanded(onSite)
    }

    private func expanded(_ state: JobActivityAttributes.ContentState) -> some View {
        VStack(spacing: 10) {
            HStack {
                GlanceStatusWord(text: state.label, tint: WidgetInk.tint(state.status, island: true), size: 15,
                                 textColor: WidgetInk.Island.text)
                Spacer()
                ElapsedText(since: state.since).font(WidgetInk.number(15)).foregroundStyle(.white).frame(maxWidth: 70)
            }
            IslandExpandedBottom(attributes: Self.attributes, state: state)
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .frame(width: 370)
        .background(RoundedRectangle(cornerRadius: 44, style: .continuous).fill(.black))
    }
}
#endif
