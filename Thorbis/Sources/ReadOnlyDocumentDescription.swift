import SwiftUI

/// The complete displayed document, including its job scope and issued revision.
enum DocumentDescriptionIdentity: Equatable {
    case estimate(scope: JobDocumentScope, record: EstimateRecord, issued: CustomerIssuedEstimateRevision?)
    case invoice(scope: JobDocumentScope, record: InvoiceRecord)
}

struct DocumentDescriptionAccess: Equatable {
    let identity: DocumentDescriptionIdentity
    let organizationID: String
    let capability: String
    let feature: String
    let sourceGeneration: UUID?
    let fresh: Bool
    let active: Bool
    let scopeValid: Bool

    @MainActor func authorized(_ session: SessionController) -> Bool {
        active && scopeValid && sourceGeneration == session.generation && session.phase == .ready && session.user != nil
            && session.activeOrganization?.id == organizationID && session.can(capability, feature: feature)
    }

    @MainActor func permits(_ session: SessionController) -> Bool { fresh && authorized(session) }
}

private struct DescriptionSessionIdentity: Equatable {
    let actorID: String
    let generation: UUID
    let authorityRevision: UUID

    @MainActor init?(_ session: SessionController) {
        guard let actorID = session.user?.id else { return nil }
        self.actorID = actorID
        generation = session.generation
        authorityRevision = session.authorityRevision
    }
}

private struct DescriptionOpening: Identifiable {
    let id = UUID()
    let access: DocumentDescriptionAccess
    let session: DescriptionSessionIdentity
}

/// A customer can read the entire current description without editing a document.
struct ReadOnlyDocumentDescription: View {
    let text: String
    let fontSize: CGFloat
    let access: DocumentDescriptionAccess
    @State private var opening: DescriptionOpening?
    @EnvironmentObject private var session: SessionController

    private var needsDetails: Bool { text.count > 80 || text.contains("\n") }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if access.authorized(session) {
                Text(text)
                    .font(Theme.font(fontSize))
                    .lineLimit(needsDetails && access.permits(session) ? 2 : nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if needsDetails && access.permits(session) {
                Button("Show more") {
                    guard access.permits(session), let identity = DescriptionSessionIdentity(session) else { return }
                    opening = DescriptionOpening(access: access, session: identity)
                }
                .font(Theme.font(fontSize, weight: .medium))
                .foregroundStyle(Theme.brandText)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
        }
        .sheet(item: $opening) { snapshot in
            if snapshot.access == access && snapshot.session == DescriptionSessionIdentity(session) && access.permits(session) {
                NavigationStack {
                    ScrollView {
                        Text(text)
                            .font(Theme.font(fontSize))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(Theme.gutter)
                    }
                    .navigationTitle("Description")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ThorbisToolbarItem(placement: .confirmationAction, prominent: true) { Button("Done") { opening = nil } } }
                    .background(Theme.background)
                }
                .presentationDetents([.large])
            }
        }
        .onChange(of: text) { _, _ in opening = nil }
        .onChange(of: access) { _, _ in opening = nil }
        .onChange(of: session.authorityRevision) { _, _ in opening = nil }
        .onDisappear { opening = nil }
    }
}
