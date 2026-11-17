import SwiftUI

/// Paper TE1/TE2/TE6: the full-screen editor for a line's wording, opened from a builder line.
/// Cancel puts back the wording the editor opened with; Done keeps what is written. Select, cut,
/// copy and paste are the system's own. The wording is saved and shown to customers as plain
/// text, so there is no formatting bar and no Markdown tab: neither would show on the customer's
/// copy. Customer view shows the line as the customer reads it.
struct LineDescriptionEditor: View {
    @Binding var text: String
    /// Under the title, e.g. the document number. Left out when the caller has none.
    var subtitle: String? = nil
    /// The line total the customer sees beside the wording.
    var totalText: String? = nil
    /// Where the wording came from, e.g. "Edited · price book $145.00".
    var note: String? = nil
    var resetTitle: String? = nil
    var resetHint: String? = nil
    var reset: (() -> Void)? = nil

    private static let writeTab = "Write"
    private static let customerTab = "Customer view"

    @Environment(\.dismiss) private var dismiss
    @State private var original = ""
    @State private var loaded = false
    @State private var tab = LineDescriptionEditor.writeTab
    @FocusState private var writing: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            PaperTabs(options: [Self.writeTab, Self.customerTab], selection: $tab)
            if tab == Self.customerTab {
                customerView
            } else {
                write
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            guard !loaded else { return }
            original = text
            loaded = true
            writing = true
        }
        .onChange(of: tab) { _, value in writing = value == Self.writeTab }
    }

    // MARK: Title bar

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                if loaded { text = original }
                dismiss()
            } label: {
                Text("Cancel").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                    .padding(.horizontal, 16).frame(minHeight: 44)
                    .background(Theme.card, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("description-editor-cancel")
            VStack(spacing: 0) {
                Text("Description").font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.foreground)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(Theme.font(12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            Button {
                dismiss()
            } label: {
                Text("Done").font(Theme.font(15, weight: .semibold)).foregroundStyle(Color.white)
                    .padding(.horizontal, 18).frame(minHeight: 44)
                    .background(Theme.brand, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("description-editor-done")
        }
    }

    // MARK: Write (TE1, TE2)

    private var write: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let note, !note.isEmpty {
                HStack(spacing: 6) {
                    Text(note).font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let reset, let resetTitle {
                        Text("·").font(Theme.font(13)).foregroundStyle(Theme.muted).accessibilityHidden(true)
                        Button {
                            reset()
                            // Reset is its own decision: Cancel afterwards keeps it.
                            original = text
                        } label: {
                            Text(resetTitle).font(Theme.font(13)).foregroundStyle(Theme.brandText)
                                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(resetHint ?? "")
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 22)
            }
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Describe this item").font(Theme.font(17)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 22).padding(.top, 8)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $text)
                    .font(Theme.font(17))
                    .foregroundStyle(Theme.foreground)
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .focused($writing)
                    .padding(.horizontal, 17)
                    .accessibilityLabel("Line description")
                    .accessibilityIdentifier("description-editor-text")
            }
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Customer view (TE6)

    private var customerView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "eye").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                        .accessibilityHidden(true)
                    Text("What your customer sees").font(Theme.font(13)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 4)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(trimmed.isEmpty ? "Nothing written yet" : trimmed)
                        .font(Theme.font(16, weight: .semibold))
                        .foregroundStyle(trimmed.isEmpty ? Theme.muted : Theme.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let totalText {
                        Text(totalText).font(Theme.font(16, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(Theme.foreground)
                    }
                }
                .padding(16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
                .accessibilityElement(children: .combine)
                Text("Read only. Switch to Write to change the text.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4).padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }
}
