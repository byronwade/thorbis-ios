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

    func body(content: Content) -> some View {
        let exports = ReportExport.available(session)
        content
            .toolbar {
                if !exports.isEmpty {
                    ThorbisToolbarItem(placement: .topBarTrailing) {
                        ThorbisMenu(items: exports.map { export in
                            ThorbisMenuItem(export.label, icon: "tablecells") { open(export) }
                        }, title: "Download as Excel", accessibilityLabel: "Download as Excel") {
                            if preview.loading {
                                ProgressView()
                            } else {
                                Image(systemName: "square.and.arrow.down")
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: Binding(get: { preview.url != nil }, set: { if !$0 { preview.clear() } })) {
                if let url = preview.url { NativeDocumentPreview(url: url).ignoresSafeArea() }
            }
            .alert("The file did not download", isPresented: Binding(get: { preview.error != nil }, set: { if !$0 { preview.clear() } })) {
                Button("OK", role: .cancel) { preview.clear() }
            } message: {
                Text(preview.error ?? "")
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
