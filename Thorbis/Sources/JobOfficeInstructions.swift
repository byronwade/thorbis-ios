import SwiftUI

/// The reader belongs to the current job and authority, not just to a displayed string.
struct JobOfficeInstructionsScope: Equatable {
    let jobID: String
    let organizationID: String
    let actorID: String
    let generation: UUID
    let authorityRevision: UUID
    let updatedAt: String?
    let text: String
    let origin: String
    let api: UUID
}

private struct JobOfficeInstructionsOpening: Identifiable {
    let id = UUID()
    let scope: JobOfficeInstructionsScope
}

/// Keeps long office instructions compact while letting the technician read and select the whole note.
struct JobOfficeInstructions: View {
    let job: JobRecord
    let text: String
    let readAllowed: Bool
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var opening: JobOfficeInstructionsOpening?

    private var needsReader: Bool { text.count > 180 || text.filter { $0 == "\n" }.count >= 3 }

    private var scope: JobOfficeInstructionsScope? {
        guard readAllowed, session.phase == .ready, let actor = session.user?.id,
              session.activeOrganization?.id == job.organizationId,
              session.can("job.view", feature: "jobs"), let origin = api.normalizedOrigin else { return nil }
        return JobOfficeInstructionsScope(jobID: job.id, organizationID: job.organizationId,
                                          actorID: actor, generation: session.generation,
                                          authorityRevision: session.authorityRevision,
                                          updatedAt: job.updatedAt, text: text, origin: origin, api: api.requestGeneration)
    }

    var body: some View {
        Group {
        if scope != nil {
        VStack(alignment: .leading, spacing: 3) {
            Text("From the office").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.font(15)).foregroundStyle(Theme.foreground).lineSpacing(3)
                .lineLimit(needsReader ? 3 : nil)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityLabel("From the office: \(text)")
            if needsReader, let current = scope {
                Button("Show more") { opening = JobOfficeInstructionsOpening(scope: current) }
                    .font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.brandText)
                    .frame(minHeight: 44).contentShape(Rectangle())
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Show full office instructions")
                    .accessibilityIdentifier("job-office-note-more")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 12)
        }
        }
        .sheet(item: $opening) { selected in
            SheetSurface {
                if scope == selected.scope {
                    NavigationStack {
                        ScrollView {
                            Text(selected.scope.text)
                                .font(Theme.font(16)).lineSpacing(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                                .padding(Theme.gutter)
                        }
                        .navigationTitle("Office instructions")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ThorbisToolbarItem(placement: .confirmationAction, prominent: true) {
                                Button("Done") { opening = nil }
                            }
                        }
                        .background(Theme.canvas)
                    }
                    .presentationDetents([.large])
                }
            }
        }
        .onChange(of: scope) { _, _ in opening = nil }
        .onDisappear { opening = nil }
    }
}
