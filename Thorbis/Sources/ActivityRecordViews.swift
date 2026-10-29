import SwiftUI

/// The time shown on an opened note. An unreadable value stays as the server sent it.
enum ActivityRecordLabel {
    static func noteWhen(_ createdAt: String) -> String {
        guard let date = JobFiltering.date(createdAt) else { return createdAt }
        return date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute())
    }
}

/// Wraps an activity row in a link only when the row already names a real record.
struct ActivityLink<Content: View>: View {
    let destination: ActivityDestination?
    @ViewBuilder var content: () -> Content

    var body: some View {
        if let destination {
            NavigationLink(value: destination.route) { label }
                .buttonStyle(RowPressStyle())
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: 8) {
            content()
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            if destination != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
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
