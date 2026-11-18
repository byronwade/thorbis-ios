import SwiftUI

/// The Excel files web Reports offers (apps/web reports.tsx ReportDownloads), one menu on the phone.
/// Each file opens in Quick Look, whose share button sends it to Files, Mail or Numbers.
struct ReportExport: Identifiable, Hashable {
    let id: String
    let label: String
    let path: String
    /// Matches the server's own gate for the export route.
    let capability: String
    let feature: String
    var alsoNeeds: [String] = []

    static let all: [ReportExport] = [
        .init(id: "operations", label: "Estimates and jobs", path: "/v1/reports/operations.xlsx",
              capability: "estimate.view", feature: "estimates", alsoNeeds: ["jobs"]),
        .init(id: "activity", label: "Customer activity", path: "/v1/reports/activity.xlsx",
              capability: "invoice.view", feature: "invoicing", alsoNeeds: ["estimates", "jobs"]),
        .init(id: "schedule", label: "Schedule utilization", path: "/v1/reports/schedule.xlsx",
              capability: "job.view", feature: "jobs"),
        .init(id: "revenue", label: "Revenue", path: "/v1/reports/revenue.xlsx",
              capability: "invoice.view", feature: "invoicing", alsoNeeds: ["payments"]),
        .init(id: "payment-activity", label: "Payment activity", path: "/v1/reports/payment-activity.xlsx",
              capability: "invoice.view", feature: "invoicing", alsoNeeds: ["payments"]),
    ]

    @MainActor static func available(_ session: SessionController) -> [ReportExport] {
        all.filter { export in
            session.can(export.capability, feature: export.feature) && export.alsoNeeds.allSatisfy { session.isFeatureOn($0) }
        }
    }

    /// thorbis-revenue-2026-10-28.xlsx
    func fileName(on day: Date = Date()) -> String {
        "thorbis-\(id)-\(day.formatted(.iso8601.year().month().day())).xlsx"
    }
}

private struct ReportExportMenu: ViewModifier {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @StateObject private var preview = DocumentPreviewController()
    @State private var choosing = false

    func body(content: Content) -> some View {
        let exports = ReportExport.available(session)
        content
            .toolbar {
                if !exports.isEmpty {
                    ThorbisToolbarItem(placement: .topBarTrailing) {
                        Button { choosing = true } label: {
                            // Paper 60: the share circle at the top right, 44 on the card tone.
                            if preview.loading {
                                ProgressView()
                                    .frame(width: 44, height: 44)
                                    .background(Theme.card, in: Circle())
                            } else {
                                CreamCircleLabel(symbol: "square.and.arrow.up")
                            }
                        }
                        .buttonStyle(PressStyle())
                        .disabled(preview.loading)
                        .accessibilityLabel("Export report")
                    }
                }
            }
            .sheet(isPresented: $choosing) {
                ReportExportSheet(exports: exports) { export in open(export) }
            }
            .sheet(isPresented: Binding(get: { preview.url != nil }, set: { if !$0 { preview.clear() } })) {
                if let url = preview.url { NativeDocumentPreview(url: url).ignoresSafeArea() }
            }
            .alert("The file did not download", isPresented: Binding(get: { preview.error != nil }, set: { if !$0 { preview.clear() } })) {
                Button("OK", role: .cancel) { preview.clear() }
            } message: {
                Text(preview.error ?? "")
            }
            .task {
                #if DEBUG
                if PaperPreview.enabled, PaperPreview.screen == "export-report" { choosing = true }
                #endif
            }
    }

    private func open(_ export: ReportExport) {
        preview.open { [api] in
            let data = try await api.spreadsheetData(export.path)
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("report-exports", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent(export.fileName())
            try? FileManager.default.removeItem(at: file)
            try data.write(to: file, options: [.atomic, .completeFileProtection])
            return file
        }
    }
}

extension View {
    /// Adds the Excel download menu to a report screen's bar.
    func reportExports() -> some View { modifier(ReportExportMenu()) }
}

/// Paper P6 "Export report": Cancel, the title and the blue Export pill over one card of choices,
/// each with Paper's 22pt radio. The server makes Excel files of whole reports, so Paper's PDF/CSV
/// tiles and date range are left out; the file opens in Quick Look, whose share button is Paper's
/// "Send to" (Files, Mail, anything else).
struct ReportExportSheet: View {
    let exports: [ReportExport]
    let onExport: (ReportExport) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var picked: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Button { dismiss() } label: {
                    Text("Cancel").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .background(Theme.foreground.opacity(0.08), in: Capsule())
                }
                .buttonStyle(PressStyle())
                Spacer(minLength: 0)
                Button {
                    guard let export = exports.first(where: { $0.id == (picked ?? exports.first?.id) }) else { return }
                    dismiss()
                    onExport(export)
                } label: {
                    Text("Export").font(Theme.font(16, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).frame(minHeight: 44)
                        .background(Theme.brand, in: Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("export-report-commit")
            }
            .overlay {
                Text("Export report").font(Theme.font(17, weight: .semibold)).foregroundStyle(Theme.foreground)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 96)
            }
            .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 18).padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    PaperSectionLabel(title: "Report", gap: 0)
                    VStack(spacing: 0) {
                        ForEach(Array(exports.enumerated()), id: \.element.id) { index, export in
                            if index > 0 { WellDivider(leading: 0) }
                            row(export, selected: export.id == (picked ?? exports.first?.id))
                        }
                    }
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    Text("Opens as an Excel file. Use its share button to save it to Files or send it to your accountant.")
                        .font(Theme.font(13)).foregroundStyle(Theme.subtleForeground)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4).padding(.top, 4)
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.bottom, 16)
            }
        }
        .background(Theme.canvas)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ export: ReportExport, selected: Bool) -> some View {
        Button { picked = export.id } label: {
            HStack(alignment: .center, spacing: 12) {
                Text(export.label).font(Theme.font(16)).foregroundStyle(Theme.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if selected {
                    PaperIcon(.check, size: 12, color: .white)
                        .frame(width: 22, height: 22).background(Theme.brand, in: Circle())
                } else {
                    Circle().strokeBorder(Theme.borderStrong, lineWidth: 1.5).frame(width: 22, height: 22)
                }
            }
            .padding(.horizontal, PaperCardMetrics.inset)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("export-report-\(export.id)")
    }
}
