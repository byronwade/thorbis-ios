import SwiftUI

/// One thing the "Add to job" sheet can add: Paper 22's row, a 22pt glyph, the name at 16 Medium
/// over what it is for at 14 muted, and a chevron.
struct JobAddRow: Identifiable {
    let id: String
    let glyph: PaperGlyph
    let title: String
    let subtitle: String
    let action: () -> Void
}

/// Paper 22 "Job details (add drawer)": a bottom sheet titled "Add to job" with a close circle,
/// then "Billing" and "On the job", each a 13 Semibold label 8 over one card of 62pt rows. Only the
/// rows this person can use are passed in; an empty group is left out. A tapped row closes the
/// sheet, then runs (`onDismiss` in the caller), so a row that opens its own sheet never collides.
struct JobAddSheet: View {
    let billing: [JobAddRow]
    let onTheJob: [JobAddRow]
    let choose: (JobAddRow) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var height: CGFloat = 420

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text("Add to job").font(Theme.font(22, weight: .bold)).tracking(-0.44)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Button { dismiss() } label: {
                        PaperIcon(.addClose, size: 18).frame(width: 44, height: 44).background(Theme.quietFill, in: Circle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("job-add-close")
                }
                .padding(.horizontal, 4).padding(.bottom, 4)
                if !billing.isEmpty { group("Billing", rows: billing).padding(.top, 12) }
                if !onTheJob.isEmpty { group("On the job", rows: onTheJob).padding(.top, billing.isEmpty ? 12 : 20) }
            }
            .padding(.horizontal, 16).padding(.top, 23).padding(.bottom, 12)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .foregroundStyle(Theme.foreground)
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(height)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
        .accessibilityIdentifier("job-add-sheet")
    }

    private func group(_ title: String, rows: [JobAddRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    Button { choose(row) } label: {
                        HStack(spacing: 12) {
                            PaperIcon(row.glyph, size: 22).frame(width: 24).accessibilityHidden(true)
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(row.title).font(Theme.font(16, weight: .medium)).tracking(-0.16)
                                    Text(row.subtitle).font(Theme.font(14)).foregroundStyle(Theme.muted)
                                }
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                PaperIcon(.addChevron, size: 16, color: Theme.borderStrong).accessibilityHidden(true)
                            }
                            .padding(.trailing, 14).padding(.vertical, 8)
                            .frame(minHeight: 62)
                            .overlay(alignment: .top) {
                                if index > 0 { Rectangle().fill(Theme.border).frame(height: 1) }
                            }
                        }
                        .padding(.leading, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityIdentifier("job-add-\(row.id)")
                }
            }
            .background(Theme.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}
