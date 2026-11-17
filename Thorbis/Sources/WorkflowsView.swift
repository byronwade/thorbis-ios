import SwiftUI

// Business settings › Workflows (Paper 92).
//
// Paper 92 draws a list of workflows with approvals waiting on the owner. There is no workflow
// store on the server: the web's Workflow Studio keeps its drafts on the computer they were built
// on, and nothing on a phone could run one. A list here would be a list of things that never run,
// so this page says where workflows are built and lists what Thorbis already does on its own.
// Each item below is real: review requests (communications review-requests), booking and travel
// notices (communications job-notices) and this phone's morning digest (PushNotifications).

/// One thing Thorbis does without being asked, in Paper 92's "Active" grammar.
struct WorkflowAutomation: Identifiable, Equatable {
    enum Destination: Equatable { case reviewRequests, notices }

    let id: String
    let title: String
    /// "Runs when …"
    let trigger: String
    /// "On" or "Off" where the app knows; nil where it can't tell.
    var state: String? = nil
    var isOn = false
    /// The screen that changes it, when this person may open one.
    var destination: Destination? = nil
}

enum WorkflowAutomations {
    struct Inputs: Equatable {
        /// May change company settings (review requests).
        var canEditSettings = false
        /// May open Notification rules.
        var canManageNotices = false
        /// Gets the 6:30 digest on this phone, and whether it is switched on.
        var receivesDigest = false
        var digestOn = false
        /// The company profile once read; nil while unknown.
        var reviewRequests: String? = nil
        var reviewLink: String? = nil
        var profileLoaded = false
    }

    /// On only when the switch is on and a usable link is saved; unknown until the profile is read.
    static func reviewState(_ inputs: Inputs) -> (word: String, on: Bool)? {
        guard inputs.profileLoaded else { return nil }
        if inputs.reviewRequests == "off" { return ("Off", false) }
        if inputs.reviewLink.flatMap({ ReviewLink.validated($0) }) == nil { return ("No link", false) }
        return ("On", true)
    }

    static func items(_ inputs: Inputs) -> [WorkflowAutomation] {
        var items: [WorkflowAutomation] = []
        let review = reviewState(inputs)
        items.append(.init(id: "review-request", title: "Send review request",
                           trigger: "Runs when an invoice is paid in full",
                           state: review?.word, isOn: review?.on ?? false,
                           destination: inputs.canEditSettings ? .reviewRequests : nil))
        items.append(.init(id: "booking-notices", title: "Tell the team about bookings",
                           trigger: "Runs when a job is booked, changed or canceled",
                           destination: inputs.canManageNotices ? .notices : nil))
        items.append(.init(id: "visit-updates", title: "Update the customer on the visit",
                           trigger: "Runs when a tech is on the way, arrives, starts and finishes. Each job’s notices show what was sent."))
        if inputs.receivesDigest {
            items.append(.init(id: "morning-digest", title: "Morning digest on this phone",
                               trigger: "Runs at 6:30 with yesterday’s collections, today’s jobs and overdue invoices",
                               state: inputs.digestOn ? "On" : "Off", isOn: inputs.digestOn, destination: .notices))
        }
        return items
    }
}

/// Business settings › Workflows.
struct WorkflowsView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var profile: OrganizationProfile?
    @State private var digestOn = PushNotifications.morningDigest

    private var inputs: WorkflowAutomations.Inputs {
        .init(canEditSettings: session.can("organization.settings.edit"),
              canManageNotices: MenuItem.notices.permitted(session),
              receivesDigest: PushNotifications.receivesMorningDigest(session),
              digestOn: digestOn,
              reviewRequests: profile?.value("review_requests"),
              reviewLink: profile?.value("review_link"),
              profileLoaded: profile != nil)
    }

    var body: some View {
        let items = WorkflowAutomations.items(inputs)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaperHeader(title: "Workflows", subtitle: "Built on the web")
                    .environment(\.paperMenuButton, false)
                    .environment(\.paperDrawer, nil)
                VStack(alignment: .leading, spacing: 20) {
                    PaperCard(padding: PaperCardMetrics.inset) {
                        Text("Workflows are built on the web today. The web keeps them on the computer they were built on, so there are none to show or run on this phone.")
                            .font(Theme.font(15)).foregroundStyle(Theme.foreground)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        PaperSection("Already automatic", count: items.count) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { WellDivider(leading: PaperCardMetrics.inset) }
                                row(item)
                            }
                        }
                        Text("These run for your company without a workflow.")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 10).padding(.bottom, 44)
            }
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("workflows-root")
        // Runs again on the way back from a row's screen, so On and Off match what was saved.
        .onAppear {
            digestOn = PushNotifications.morningDigest
            Task { await load() }
        }
    }

    @ViewBuilder
    private func row(_ item: WorkflowAutomation) -> some View {
        let content = PaperListRow(title: item.title, subtitle: item.trigger, subtitleLines: 3) {
            HStack(spacing: 8) {
                if let state = item.state {
                    StatusWord(text: state, tint: item.isOn ? Theme.statusDone : nil)
                }
                if item.destination != nil {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.muted).accessibilityHidden(true)
                }
            }
        }
        switch item.destination {
        case .reviewRequests:
            NavigationLink { ReviewRequestsView().thorbisBackButton() } label: { content }
                .buttonStyle(RowPressStyle())
                .accessibilityIdentifier("workflows-\(item.id)")
        case .notices:
            NavigationLink { NoticeSettingsView().thorbisBackButton() } label: { content }
                .buttonStyle(RowPressStyle())
                .accessibilityIdentifier("workflows-\(item.id)")
        case nil:
            content.accessibilityElement(children: .combine)
        }
    }

    private func load() async {
        guard session.can("organization.settings.edit") else { return }
        let generation = session.generation
        // A failed read leaves the row without On or Off rather than guessing.
        if let fresh = try? await api.organizationProfile(), session.generation == generation { profile = fresh }
    }
}
