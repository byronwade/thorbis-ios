import SwiftUI
import ThorbisCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("thorbis.appearance") private var appearance: Appearance = .system
    @State private var confirmingSignOut = false
    @State private var confirmingDeletion = false
    @State private var deletionStatus: String?
    @State private var deletionBusy = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: Theme.Space.m) {
                    Avatar(name: model.account?.name ?? model.account?.email ?? "?", size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.account?.name ?? "Signed in").font(.headline.weight(.medium)).foregroundStyle(Theme.ink)
                        if let email = model.account?.email {
                            Text(email).font(.subheadline).foregroundStyle(Theme.inkSecondary)
                        }
                    }
                }
                .padding(.vertical, Theme.Space.xs)
                .sheetRow()
            }

            Section("Workspace") {
                DetailRow(label: "Company", value: model.organization?.name ?? "—").sheetRow()
                Button("Switch workspace") { Task { await model.switchOrganization() } }.sheetRow()
                DetailRow(label: "Server", value: model.environment.name).sheetRow()
            }

            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .sheetRow()
            }

            Section {
                Button("Sign out") { confirmingSignOut = true }.sheetRow()
            }

            Section {
                Button("Delete account…", role: .destructive) { confirmingDeletion = true }
                    .disabled(deletionBusy)
                    .sheetRow()
                if let deletionStatus {
                    Text(deletionStatus).font(.footnote).foregroundStyle(Theme.inkSecondary).sheetRow()
                }
            } footer: {
                Text("Deleting your Thorbis account removes your sign-in and company memberships. Records your company must keep, like invoices, stay with the company.")
            }

            Section {
                DetailRow(label: "Version", value: version).sheetRow()
            } footer: {
                Text("Thorbis for field service. Your company manages access, roles and billing outside the app.")
            }
        }
        .thorbisList()
        .navigationTitle("Account")
        .task { await loadDeletionStatus() }
        .confirmationDialog("Sign out of Thorbis?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await model.signOut() } }
            Button("Stay signed in", role: .cancel) {}
        }
        .confirmationDialog("Delete your Thorbis account?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
            Button("Request deletion", role: .destructive) { Task { await requestDeletion() } }
            Button("Keep account", role: .cancel) {}
        } message: {
            Text("This starts a deletion request for your personal account. It can't be undone once processed.")
        }
    }

    private func loadDeletionStatus() async {
        if let request = try? await model.api.currentDeletionRequest() {
            deletionStatus = "Deletion requested (\(request.status.replacingOccurrences(of: "_", with: " ")))."
        }
    }

    private func requestDeletion() async {
        deletionBusy = true
        defer { deletionBusy = false }
        do {
            let request = try await model.api.requestAccountDeletion()
            deletionStatus = "Deletion requested (\(request.status.replacingOccurrences(of: "_", with: " "))). We'll sign you out when it's processed."
        } catch {
            // Production may require recent re-authentication first; say so plainly.
            deletionStatus = "Couldn't start deletion: \(model.message(for: error) ?? error.localizedDescription) Sign in again and retry, or contact your organization administrator."
        }
    }
}
