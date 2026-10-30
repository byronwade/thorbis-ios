import SwiftUI

/// A focused working copy of a description. Applying changes updates only the caller's draft.
enum DescriptionPreview {
    static func isLong(_ text: String) -> Bool {
        text.count > 100 || text.filter { $0 == "\n" }.count >= 2
    }
}

enum DescriptionCanvasLimit {
    case utf16(Int)
    case utf16Raw(Int)
    case unicodeScalars(Int)

    var maximum: Int {
        switch self { case .utf16(let value), .utf16Raw(let value), .unicodeScalars(let value): value }
    }

    func count(_ text: String) -> Int {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self { case .utf16: return value.utf16.count; case .utf16Raw: return text.utf16.count; case .unicodeScalars: return value.unicodeScalars.count }
    }
}

struct DescriptionCanvas: View {
    @Binding var text: String
    let title: String
    let applyTitle: String
    let limit: DescriptionCanvasLimit?
    let scope: DescriptionCanvasScope
    @Binding var accessRetired: Bool
    @Binding var hasUnappliedChanges: Bool
    let targetAvailable: Bool
    let temporaryParentUnavailable: Bool
    let apply: ((String, String) -> Bool)?
    @EnvironmentObject private var session: SessionController
    @State private var working: String
    @State private var original: String
    @State private var confirmDiscard = false
    @Environment(\.dismiss) private var dismiss

    init(text: Binding<String>, title: String, applyTitle: String, limit: DescriptionCanvasLimit?,
         scope: DescriptionCanvasScope, accessRetired: Binding<Bool>, hasUnappliedChanges: Binding<Bool> = .constant(false),
         targetAvailable: Bool = true, temporaryParentUnavailable: Bool = false,
         originalText: String? = nil, apply: ((String, String) -> Bool)? = nil) {
        _text = text
        self.title = title
        self.applyTitle = applyTitle
        self.limit = limit
        self.scope = scope
        _accessRetired = accessRetired
        _hasUnappliedChanges = hasUnappliedChanges
        self.targetAvailable = targetAvailable
        self.temporaryParentUnavailable = temporaryParentUnavailable
        self.apply = apply
        _working = State(initialValue: originalText ?? text.wrappedValue)
        _original = State(initialValue: originalText ?? text.wrappedValue)
    }

    private var count: Int { limit?.count(working) ?? 0 }
    private var exceedsLimit: Bool { limit.map { count > $0.maximum } ?? false }
    private var scopeValid: Bool {
        session.phase == .ready && scope.matches(actor: session.user?.id,
            organization: session.activeOrganization?.id, generation: session.generation, authority: session.authorityRevision)
    }
    private var accessValid: Bool { !accessRetired && targetAvailable && scopeValid }

    var body: some View {
        NavigationStack {
            Group {
                if accessValid {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        TextEditor(text: $working)
                            .font(Theme.font(17))
                            .scrollContentBackground(.hidden)
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .frame(height: max(240, geometry.size.height * 0.62))
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                            .accessibilityLabel(title)
                            .accessibilityIdentifier("description-canvas-editor")
                        if let limit {
                            Text(exceedsLimit ? "This description is too long to save. \(count) of \(limit.maximum) allowed." : "\(count) of \(limit.maximum) allowed")
                                .font(Theme.font(14))
                                .foregroundStyle(exceedsLimit ? Theme.destructive : Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if text != original {
                            Text("This description changed while it was open. Close and open it again to review the latest version.")
                                .font(Theme.font(14)).foregroundStyle(Theme.destructive)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Changes are applied to the editor.")
                            .font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(20)
                }
            }
                } else {
                    ContentUnavailableView("Editor unavailable", systemImage: "lock", description: Text(temporaryParentUnavailable && scopeValid && !accessRetired ? "Waiting for the current document. Your unapplied text stays here." : "Access changed. Your unapplied text remains here until you discard it."))
                        .padding(20)
                }
            }
            .background(Theme.background)
            .foregroundStyle(Theme.foreground)
            .navigationTitle(accessValid ? title : "Description")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                #if DEBUG
                if PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--canvas-test-authority") && !ProcessInfo.processInfo.arguments.contains("--canvas-test-parent-revoke") {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button("Test revoke") { session.previewSetEstimateEditing(false) }
                        Button("Test restore") { session.previewSetEstimateEditing(true) }
                    }
                }
                if PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--canvas-test-removal") {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Test remove") {
                            NotificationCenter.default.post(name: Notification.Name("ThorbisPreviewRemoveCanvasLine"), object: nil)
                        }
                    }
                }
                if PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--canvas-test-new-estimate-job") {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button { NotificationCenter.default.post(name: Notification.Name("ThorbisPreviewLoseEstimateJob"), object: nil) }
                            label: { Image(systemName: "pause.circle") }.accessibilityLabel("Test job loss")
                        Button { NotificationCenter.default.post(name: Notification.Name("ThorbisPreviewReturnEstimateJob"), object: nil) }
                            label: { Image(systemName: "arrow.uturn.backward.circle") }.accessibilityLabel("Test job return")
                    }
                }
                if PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--canvas-test-parent-loss") {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button { NotificationCenter.default.post(name: Notification.Name("ThorbisPreviewLoseDocumentParent"), object: nil) }
                            label: { Image(systemName: "pause.circle") }.accessibilityLabel("Test parent loss")
                        Button { NotificationCenter.default.post(name: Notification.Name("ThorbisPreviewReturnDocumentParent"), object: nil) }
                            label: { Image(systemName: "arrow.uturn.backward.circle") }.accessibilityLabel("Test parent return")
                        Button { NotificationCenter.default.post(name: Notification.Name("ThorbisPreviewReplaceDocumentParent"), object: nil) }
                            label: { Image(systemName: "arrow.triangle.2.circlepath.circle") }.accessibilityLabel("Test parent replace")
                    }
                }
                if PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--canvas-test-replacement") {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Test replace") {
                            NotificationCenter.default.post(name: Notification.Name("ThorbisPreviewReplaceEstimateDraft"), object: nil)
                        }
                    }
                }
                #endif
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if working != original { confirmDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        guard accessValid, !exceedsLimit, text == original else { return }
                        if let apply {
                            if apply(original, working) { dismiss() }
                        } else {
                            text = working
                            dismiss()
                        }
                    }
                        .accessibilityLabel(applyTitle)
                        .accessibilityInputLabels(["Apply"])
                        .disabled(!accessValid || exceedsLimit || text != original)
                }
            }
            .confirmationDialog("Discard changes to this description?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) { }
            } message: {
                Text("Your changes in this editor haven't been applied.")
            }
            .onChange(of: accessValid) { _, valid in
                if !valid && (!scopeValid || !temporaryParentUnavailable) { accessRetired = true }
            }
            .onChange(of: scopeValid) { _, valid in if !valid { accessRetired = true } }
            .onChange(of: temporaryParentUnavailable) { _, temporary in
                if !temporary && !targetAvailable { accessRetired = true }
            }
            .onChange(of: working) { _, value in hasUnappliedChanges = value != original }
            .onDisappear { hasUnappliedChanges = false }
            .interactiveDismissDisabled(working != original)
        }
    }
}

struct DescriptionCanvasScope: Equatable {
    let actor: String
    let organization: String
    let generation: UUID
    let authority: UUID

    @MainActor static func current(_ session: SessionController) -> DescriptionCanvasScope? {
        guard session.phase == .ready, let actor = session.user?.id, let organization = session.activeOrganization?.id else { return nil }
        return .init(actor: actor, organization: organization, generation: session.generation, authority: session.authorityRevision)
    }

    func matches(actor: String?, organization: String?, generation: UUID, authority: UUID) -> Bool {
        self.actor == actor && self.organization == organization && self.generation == generation && self.authority == authority
    }
}
