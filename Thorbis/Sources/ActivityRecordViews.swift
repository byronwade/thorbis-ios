import SwiftUI

/// The time shown on an opened note. An unreadable value stays as the server sent it.
enum ActivityRecordLabel {
    static func noteWhen(_ createdAt: String) -> String {
        guard let date = JobFiltering.date(createdAt) else { return createdAt }
        return date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute())
    }
}

/// Feed information shown when no verified record can be opened.
struct ActivityFallback {
    let title: String
    var body: String? = nil
    var when: String? = nil
    let capability: String
    let feature: String
}

struct ActivitySnapshotScope: Equatable {
    let actorID: String
    let organizationID: String
    let generation: UUID
    let authorityRevision: UUID
    let capability: String
    let feature: String

    @MainActor static func capture(session: SessionController, capability: String, feature: String) -> Self? {
        guard session.can(capability, feature: feature), let actorID = session.user?.id,
              let organizationID = session.activeOrganization?.id else { return nil }
        return Self(actorID: actorID, organizationID: organizationID, generation: session.generation,
                    authorityRevision: session.authorityRevision, capability: capability, feature: feature)
    }

    @MainActor func isCurrent(session: SessionController) -> Bool {
        Self.capture(session: session, capability: capability, feature: feature) == self
    }
}

private struct ActivitySnapshot: Identifiable {
    let id = UUID()
    let fallback: ActivityFallback
    let scope: ActivitySnapshotScope
}

/// Opens a named record when available; otherwise shows only the feed's own details.
struct ActivityLink<Content: View>: View {
    let destination: ActivityDestination?
    let fallback: ActivityFallback
    @ViewBuilder var content: () -> Content
    @EnvironmentObject private var session: SessionController
    @State private var snapshot: ActivitySnapshot?

    var body: some View {
        Group {
            if let destination {
                NavigationLink(value: destination.route) { label }
                    .buttonStyle(RowPressStyle())
            } else {
                Button {
                    guard let scope = ActivitySnapshotScope.capture(session: session, capability: fallback.capability, feature: fallback.feature) else { return }
                    snapshot = ActivitySnapshot(fallback: fallback, scope: scope)
                } label: { label }
                .buttonStyle(RowPressStyle())
                .sheet(item: $snapshot) { detail in
                    NavigationStack {
                        ActivitySnapshotView(snapshot: detail)
                    }
                }
            }
        }
    }

    private var label: some View {
        HStack(spacing: 8) {
            content()
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}

private struct ActivitySnapshotView: View {
    let snapshot: ActivitySnapshot
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss

    private var authorized: Bool { snapshot.scope.isCurrent(session: session) }

    var body: some View {
        ScrollView {
            if authorized {
                VStack(alignment: .leading, spacing: 12) {
                    Text(snapshot.fallback.title).font(Theme.font(20, weight: .medium))
                    if let body = snapshot.fallback.body, !body.isEmpty {
                        Text(body).font(Theme.font(17)).textSelection(.enabled)
                    }
                    if let when = snapshot.fallback.when, !when.isEmpty {
                        Text(when).font(Theme.font(13)).foregroundStyle(Theme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.gutter)
            } else {
                Text("This activity is no longer available.")
                    .font(Theme.font(17)).padding(Theme.gutter)
            }
        }
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

struct JobNoteDetailView: View {
    let jobID: String
    let noteID: String
    @EnvironmentObject private var api: APIClient
    @State private var note: JobNoteRecord?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if loading { SkeletonRows(count: 3, inset: 0) }
                if let error {
                    ErrorBanner(message: error) { await load() }
                }
                if let note {
                    Text(note.body)
                        .font(Theme.font(17))
                        .foregroundStyle(Theme.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    Text(ActivityRecordLabel.noteWhen(note.createdAt))
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 16)
        }
        .background(Theme.background)
        .navigationTitle("Note")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = note == nil
        do {
            let notes = try await api.fieldNotes(jobID)
            note = notes.first { $0.id == noteID }
            error = note == nil ? "This note is not on the job." : nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

struct JobMediaDetailView: View {
    let jobID: String
    let assetID: String
    @EnvironmentObject private var api: APIClient
    @StateObject private var preview = DocumentPreviewController()
    @State private var asset: MediaAssetRecord?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if loading || preview.loading { SkeletonRows(count: 3, inset: 0) }
                if let message = error ?? preview.error {
                    ErrorBanner(message: message) { await load() }
                }
                if let asset {
                    Text(asset.caption.flatMap { $0.isEmpty ? nil : $0 } ?? asset.originalFilename)
                        .font(Theme.font(17, weight: .medium))
                        .foregroundStyle(Theme.foreground)
                    Text(asset.kind == "photo" ? "Photo" : "Document")
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.muted)
                }
                if let url = preview.url {
                    NativeDocumentPreview(url: url)
                        .frame(minHeight: 420)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 16)
        }
        .background(Theme.background)
        .navigationTitle(asset?.kind == "photo" ? "Photo" : "File")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onDisappear { preview.clear() }
    }

    private func load() async {
        loading = asset == nil
        do {
            let assets = try await api.fieldMedia(jobID)
            let match = assets.first { $0.id == assetID && !$0.archived }
            asset = match
            guard let match else {
                error = "This file is not on the job."
                loading = false
                return
            }
            error = nil
            preview.open { try await MediaTransfer(api: api).download(mediaID: match.id, filename: match.originalFilename) }
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

struct CustomerContactDetailView: View {
    let customerID: String
    let contactID: String
    @EnvironmentObject private var api: APIClient
    @State private var contact: CustomerContactRecord?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if loading { SkeletonRows(count: 3, inset: 0) }
                if let error { ErrorBanner(message: error) { await load() } }
                if let contact {
                    Text(contact.name).font(Theme.font(22, weight: .medium)).foregroundStyle(Theme.foreground)
                    if let role = contact.role, !role.isEmpty {
                        Text(role).font(Theme.font(15)).foregroundStyle(Theme.muted)
                    }
                    labeled("Phone", contact.phone)
                    labeled("Email", contact.email)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .navigationTitle("Contact")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func labeled(_ title: String, _ value: String?) -> some View {
        Group {
            if let value, !value.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.font(13)).foregroundStyle(Theme.muted)
                    Text(value).font(Theme.font(17)).foregroundStyle(Theme.foreground).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
    }

    private func load() async {
        loading = contact == nil
        do {
            let contacts = try await api.fieldContacts(customerID)
            contact = contacts.first { $0.id == contactID }
            error = contact == nil ? "This contact is not on the customer." : nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

struct ServiceLocationDetailView: View {
    let customerID: String
    let locationID: String
    @EnvironmentObject private var api: APIClient
    @State private var location: ServiceLocationRecord?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if loading { SkeletonRows(count: 3, inset: 0) }
                if let error { ErrorBanner(message: error) { await load() } }
                if let location {
                    Text(location.label).font(Theme.font(22, weight: .medium)).foregroundStyle(Theme.foreground)
                    Text(location.address).font(Theme.font(17)).foregroundStyle(Theme.foreground).textSelection(.enabled)
                    if let notes = location.notes, !notes.isEmpty {
                        Text(notes).font(Theme.font(15)).foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .navigationTitle("Location")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = location == nil
        do {
            let locations = try await api.fieldLocations(customerID)
            location = locations.first { $0.id == locationID }
            error = location == nil ? "This location is not on the customer." : nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
