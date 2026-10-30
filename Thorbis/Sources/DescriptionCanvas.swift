import SwiftUI

/// A focused working copy of a description. Applying changes updates only the caller's draft.
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

struct DescriptionCanvasLink: View {
    @Binding var text: String
    let title: String
    let applyTitle: String
    let limit: DescriptionCanvasLimit?
    let identifier: String
    @Environment(\.isEnabled) private var isEnabled
    @State private var showing = false

    var body: some View {
        Button("Show more") { showing = true }
            .font(Theme.font(14, weight: .medium))
            .foregroundStyle(Theme.brandText)
            .frame(minHeight: 44)
            .accessibilityLabel("Show more \(title.lowercased())")
            .accessibilityIdentifier(identifier)
            .sheet(isPresented: $showing) {
                DescriptionCanvas(text: $text, title: title, applyTitle: applyTitle, limit: limit, canApply: isEnabled)
                    .presentationDetents([.large])
            }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled { showing = false }
            }
    }
}

private struct DescriptionCanvas: View {
    @Binding var text: String
    let title: String
    let applyTitle: String
    let limit: DescriptionCanvasLimit?
    let canApply: Bool
    @State private var working: String
    @State private var original: String
    @State private var confirmDiscard = false
    @Environment(\.dismiss) private var dismiss

    init(text: Binding<String>, title: String, applyTitle: String, limit: DescriptionCanvasLimit?, canApply: Bool) {
        _text = text
        self.title = title
        self.applyTitle = applyTitle
        self.limit = limit
        self.canApply = canApply
        _working = State(initialValue: text.wrappedValue)
        _original = State(initialValue: text.wrappedValue)
    }

    private var count: Int { limit?.count(working) ?? 0 }
    private var exceedsLimit: Bool { limit.map { count > $0.maximum } ?? false }

    var body: some View {
        NavigationStack {
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
            .background(Theme.background)
            .foregroundStyle(Theme.foreground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if working != original { confirmDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { text = working; dismiss() }
                        .accessibilityLabel(applyTitle)
                        .accessibilityInputLabels(["Apply"])
                        .disabled(exceedsLimit || !canApply || text != original)
                }
            }
            .confirmationDialog("Discard changes to this description?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) { }
            } message: {
                Text("Your changes in this editor haven't been applied.")
            }
            .interactiveDismissDisabled(working != original)
        }
    }
}
