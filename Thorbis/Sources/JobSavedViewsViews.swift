import SwiftUI

// Paper 20B "Jobs (saved views)" and 20C "Saved views": the chips under the Jobs search field,
// the "Save this view" sheet and the list where a view is renamed, starred or archived.

/// What the Jobs screen knows about one saved view: the view and how it reads on this phone.
struct JobSavedViewEntry: Identifiable {
    let view: SavedJobView
    let reading: JobSavedViewMapping.Reading
    var id: String { view.id }

    var choices: JobBoardChoices? {
        if case .choices(let choices) = reading { return choices }
        return nil
    }
    var unsupportedReason: String? {
        if case .unsupported(let reason) = reading { return reason }
        return nil
    }
}

// MARK: - Chips (Paper 20B)

/// Paper 20B: the saved views as 40pt chips in one scrolling row, the one in use brand-tinted, then
/// "Save this view" while the filters on screen are not a view yet, then the list of views.
struct JobSavedViewChips: View {
    let entries: [JobSavedViewEntry]
    let favorites: Set<String>
    let selectedID: String?
    let showsSave: Bool
    let onPick: (JobSavedViewEntry) -> Void
    let onSave: () -> Void
    let onManage: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(entries) { entry in
                    chip(entry)
                }
                if showsSave {
                    Button(action: onSave) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus").font(.system(size: 13, weight: .semibold)).accessibilityHidden(true)
                            Text("Save this view").font(Theme.font(14, weight: .semibold))
                        }
                        .foregroundStyle(Theme.foreground)
                        .padding(.leading, 11).padding(.trailing, 14).frame(minHeight: 40)
                        .background(Theme.foreground.opacity(0.09), in: Capsule())
                        .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityIdentifier("jobviews-save")
                }
                if !entries.isEmpty {
                    Button(action: onManage) {
                        Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.foreground)
                            .frame(width: 40, height: 40)
                            .background(Theme.card, in: Circle())
                            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Saved views")
                    .accessibilityHint("Rename, star or archive a view")
                    .accessibilityIdentifier("jobviews-manage")
                }
            }
            .padding(.horizontal, PaperCardMetrics.margin)
        }
        .accessibilityIdentifier("jobviews-chips")
    }

    private func chip(_ entry: JobSavedViewEntry) -> some View {
        let selected = entry.id == selectedID
        let usable = entry.choices != nil
        return Button { onPick(entry) } label: {
            HStack(spacing: 6) {
                if favorites.contains(entry.id) {
                    Image(systemName: "star.fill").font(.system(size: 10, weight: .semibold)).accessibilityHidden(true)
                }
                Text(entry.view.label).font(Theme.font(14, weight: selected ? .semibold : .medium)).lineLimit(1)
                if !usable {
                    Image(systemName: "exclamationmark.circle").font(.system(size: 13, weight: .medium)).accessibilityHidden(true)
                }
            }
            .foregroundStyle(selected ? Theme.brandText : usable ? Theme.foreground : Theme.muted)
            .padding(.horizontal, 14).frame(minHeight: 40)
            .background(selected ? Theme.brand.opacity(0.24) : Theme.card, in: Capsule())
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(entry.view.label)
        .accessibilityValue(selected ? "Showing" : usable ? "" : "Can\u{2019}t be shown on this phone")
        .accessibilityHint(selected ? "Clears this view" : usable ? "Shows this view" : "Opens saved views to say why")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("jobviews-chip-\(entry.id)")
    }
}

// MARK: - Save this view (Paper 20C sheet)

/// Paper 20C "Save this view": a name and the filters the view will hold. It is saved for the
/// person only (a personal view on the server).
struct JobSavedViewSaveSheet: View {
    @ObservedObject var book: JobSavedViewsBook
    let choices: JobBoardChoices
    let roster: [String: String]
    let onSaved: (SavedJobView) -> Void
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var busy = false
    @State private var problem: String?
    @FocusState private var focused: Bool

    private var written: Result<JobSavedViewMapping.Written, JobSavedViewMapping.WriteProblem> {
        JobSavedViewMapping.write(choices)
    }
    private var blocked: String? {
        if case .failure(let reason) = written { return reason.message }
        return nil
    }

    var body: some View {
        ThorbisModalSheet(title: "Save this view", closeLabel: "Cancel", onClose: busy ? nil : { dismiss() },
                          closeStyle: .headerPill, detents: [.medium, .large], commitTitle: "Save", busy: busy,
                          commitDisabledReason: blocked, commitIdentifier: "jobviews-save-commit",
                          commit: { save() }, commitInHeader: blocked == nil) {
            ThorbisSheetField(label: "Name", error: problem) {
                TextField("Name", text: $name, prompt: .placeholder("Waiting on parts"))
                    .font(Theme.font(17, weight: .medium))
                    .fieldWell()
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { save() }
                    .onChange(of: name) { _, _ in problem = nil }
                    .accessibilityLabel("View name")
                    .accessibilityIdentifier("jobviews-name")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Filters in this view").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)
                FlowRow(spacing: 6, lineSpacing: 6) {
                    ForEach(JobSavedViewMapping.summary(choices, me: session.user?.id, techName: { roster[$0] }), id: \.self) { word in
                        Text(word).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.subtle)
                            .padding(.horizontal, 10).frame(minHeight: 30)
                            .background(Theme.fill, in: Capsule())
                    }
                }
                Text("Only you see this view. It is saved to your account, so it is on the web too.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4).padding(.top, 4)
            }
        }
        .interactiveDismissDisabled(busy)
        .onAppear { focused = blocked == nil }
    }

    private func save() {
        guard !busy, case .success(let written) = written else { return }
        let label = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(128))
        guard !label.isEmpty else { problem = "Give the view a name."; return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let view = try await book.create(label: label, written: written, api: api)
                onSaved(view)
                dismiss()
            } catch is CancellationError {
            } catch {
                problem = "Could not save the view. \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Saved views (Paper 20C)

/// Paper 20C "Saved views": every view the person can see for jobs. A row shows the view; the star
/// keeps it first, the pencil renames it and the box archives it. A view this phone cannot filter
/// by says why and is not applied.
struct JobSavedViewsSheet: View {
    @ObservedObject var book: JobSavedViewsBook
    let entries: [JobSavedViewEntry]
    let roster: [String: String]
    /// The filters on screen can be saved as a new view.
    let canSaveCurrent: Bool
    let onApply: (JobSavedViewEntry) -> Void
    let onSaveCurrent: () -> Void
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: SavedJobView?
    @State private var archiving: SavedJobView?
    @State private var busyID: String?
    @State private var problem: String?

    private var canEditOrganization: Bool { session.can("organization.settings.edit") }

    var body: some View {
        VStack(spacing: 0) {
            ThorbisSheetHeader(title: "Saved views", subtitle: "Shown as chips at the top of Jobs", onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let problem { ErrorBanner(message: problem, outer: 0) }
                    if let loadProblem = book.problem {
                        ErrorBanner(message: loadProblem, action: .init(title: "Try again") {
                            await book.load(api: api, identity: JobSavedViewsBook.identity(session))
                        }, outer: 0)
                    }
                    HStack {
                        Text("Your views").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 8)
                        Text("\(entries.count)").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                            .accessibilityLabel("\(entries.count) view\(entries.count == 1 ? "" : "s")")
                    }
                    .padding(.horizontal, 4).padding(.top, 8)
                    if entries.isEmpty {
                        Text(book.loaded ? "No saved views yet. Set filters on Jobs, then save them as a view." : "Loading your views.")
                            .font(Theme.font(15)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    } else {
                        ThorbisSheetGroup {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 { WellDivider(leading: 16) }
                                row(entry)
                            }
                        }
                    }
                    if canSaveCurrent {
                        Button { dismiss(); onSaveCurrent() } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus").font(.system(size: 15, weight: .semibold)).accessibilityHidden(true)
                                Text("Save current filters as a view").font(Theme.font(16, weight: .semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(Theme.brandText)
                            .padding(.horizontal, 16).frame(minHeight: 56)
                            .background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .padding(.top, 12)
                        .accessibilityIdentifier("jobviews-save-current")
                    }
                    Text("Archiving a view doesn\u{2019}t change any jobs. Views marked Company are shared with everyone in the workspace.")
                        .font(Theme.font(13)).foregroundStyle(Theme.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4).padding(.top, 4)
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .thorbisSheetPresentation([.large])
        .accessibilityIdentifier("jobviews-sheet")
        .sheet(item: $renaming) { view in
            JobSavedViewRenameSheet(book: book, view: view)
        }
        .thorbisConfirm(item: $archiving,
                        title: { "Archive \u{201C}\($0.label)\u{201D}?" },
                        message: { _ in "It leaves your saved views here and on the web. No jobs change." },
                        actions: { view in
                            [ThorbisConfirmAction("Archive view", role: .destructive) { archive(view) }]
                        })
    }

    private func row(_ entry: JobSavedViewEntry) -> some View {
        let view = entry.view
        let starred = book.favorites.contains(view.id)
        let mine = JobSavedViewsBook.canChange(view, me: session.user?.id, canEditOrganization: canEditOrganization)
        let busy = busyID == view.id
        return HStack(spacing: 4) {
            Button { star(view, on: !starred) } label: {
                Image(systemName: starred ? "star.fill" : "star").font(.system(size: 16, weight: .medium))
                    .foregroundStyle(starred ? Theme.brandText : Theme.subtle)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .disabled(busy)
            .accessibilityLabel(starred ? "Remove \(view.label) from favourites" : "Favourite \(view.label)")
            .accessibilityIdentifier("jobviews-star-\(view.id)")
            Button {
                guard entry.choices != nil else { return }
                onApply(entry)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(view.label).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail(entry)).font(Theme.font(14))
                        .foregroundStyle(entry.choices == nil ? Theme.warning : Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10).frame(minHeight: 64).contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .disabled(entry.choices == nil)
            .accessibilityHint(entry.choices == nil ? "" : "Shows this view on Jobs")
            .accessibilityIdentifier("jobviews-row-\(view.id)")
            if mine {
                Button { renaming = view } label: {
                    Image(systemName: "pencil").font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .disabled(busy)
                .accessibilityLabel("Rename \(view.label)")
                .accessibilityIdentifier("jobviews-rename-\(view.id)")
                Button { archiving = view } label: {
                    Image(systemName: "archivebox").font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.destructive)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .disabled(busy)
                .accessibilityLabel("Archive \(view.label)")
                .accessibilityIdentifier("jobviews-archive-\(view.id)")
            }
        }
        .padding(.leading, 2).padding(.trailing, 6)
    }

    /// "Mine · Status: On hold · 3 jobs", or why the phone cannot show the view.
    private func detail(_ entry: JobSavedViewEntry) -> String {
        guard let choices = entry.choices else {
            return "Can\u{2019}t be shown on this phone. " + (entry.unsupportedReason ?? "")
        }
        var words = JobSavedViewMapping.summary(choices, me: session.user?.id, techName: { roster[$0] })
        if entry.view.visibility == "organization" { words.insert("Company", at: 0) }
        let count = choices.jobs(from: store.jobs).count
        words.append("\(count) job\(count == 1 ? "" : "s")")
        return words.joined(separator: " \u{00B7} ")
    }

    private func star(_ view: SavedJobView, on: Bool) {
        run(view) { try await book.setFavorite(view, on: on, api: api) }
    }

    private func archive(_ view: SavedJobView) {
        run(view) { try await book.archive(view, api: api) }
    }

    private func run(_ view: SavedJobView, _ work: @escaping () async throws -> Void) {
        guard busyID == nil else { return }
        busyID = view.id
        problem = nil
        Task {
            defer { busyID = nil }
            do { try await work() }
            catch is CancellationError {}
            catch { problem = "Could not change \u{201C}\(view.label)\u{201D}. \(error.localizedDescription)" }
        }
    }
}

/// Rename a view: its name only. The filters stay as they were saved.
private struct JobSavedViewRenameSheet: View {
    @ObservedObject var book: JobSavedViewsBook
    let view: SavedJobView
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var busy = false
    @State private var problem: String?
    @FocusState private var focused: Bool

    init(book: JobSavedViewsBook, view: SavedJobView) {
        self.book = book
        self.view = view
        _name = State(initialValue: view.label)
    }

    var body: some View {
        ThorbisModalSheet(title: "Rename view", closeLabel: "Cancel", onClose: busy ? nil : { dismiss() },
                          detents: [.medium], commitTitle: "Save name", busy: busy,
                          commitIdentifier: "jobviews-rename-commit", commit: { save() }) {
            ThorbisSheetField(label: "Name", error: problem) {
                TextField("Name", text: $name, prompt: .placeholder("View name"))
                    .font(Theme.font(17, weight: .medium))
                    .fieldWell()
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { save() }
                    .onChange(of: name) { _, _ in problem = nil }
                    .accessibilityLabel("View name")
                    .accessibilityIdentifier("jobviews-rename-name")
            }
        }
        .interactiveDismissDisabled(busy)
        .onAppear { focused = true }
    }

    private func save() {
        guard !busy else { return }
        let label = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(128))
        guard !label.isEmpty else { problem = "Give the view a name."; return }
        guard label != view.label else { dismiss(); return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await book.rename(view, to: label, api: api)
                dismiss()
            } catch is CancellationError {
            } catch {
                problem = "Could not rename the view. \(error.localizedDescription)"
            }
        }
    }
}

extension JobSavedViewsBook {
    /// Views belong to one person in one workspace; a new sign-in or workspace starts over.
    static func identity(_ session: SessionController) -> String {
        "\(session.user?.id ?? "")|\(session.activeOrganization?.id ?? "")|\(session.generation)"
    }
}
