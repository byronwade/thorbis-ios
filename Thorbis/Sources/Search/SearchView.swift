import SwiftUI
import ThorbisCore

/// Workspace search over `/v1/search`, debounced as you type.
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var searching = false
    @State private var error: String?

    var body: some View {
        List {
            if let error {
                InlineError(message: error) { await search() }.sheetRow()
            }
            if query.trimmed.isEmpty {
                Section("Recent jobs") {
                    ForEach(model.jobs.prefix(8)) { job in
                        NavigationLink(value: Route.job(job.id)) { JobRow(job: job) }.sheetRow()
                    }
                }
            } else if results.isEmpty, !searching, error == nil {
                ContentUnavailableView.search(text: query).listRowBackground(Color.clear)
            } else {
                ForEach(results) { result in
                    row(result).sheetRow()
                }
            }
        }
        .thorbisList()
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Jobs, customers, invoices")
        .overlay { if searching, results.isEmpty { ProgressView() } }
        .task(id: query) {
            // Debounce: wait for a pause in typing before asking the server.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    @ViewBuilder
    private func row(_ result: SearchResult) -> some View {
        let label = VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(result.title).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                Spacer()
                if let status = result.status { Self.badge(type: result.resultType, status: status) }
            }
            HStack(spacing: Theme.Space.xs) {
                Text(result.resultType.capitalized)
                if let subtitle = result.subtitle { Text("· \(subtitle)") }
            }
            .font(.subheadline)
            .foregroundStyle(Theme.inkSecondary)
        }
        switch result.destination {
        case let .job(id): NavigationLink(value: Route.job(id)) { label }
        case let .customer(id): NavigationLink(value: Route.customer(id)) { label }
        case let .estimate(id): NavigationLink(value: Route.estimate(id)) { label }
        case let .invoice(id): NavigationLink(value: Route.invoice(id)) { label }
        case .unsupported: label
        }
    }

    /// Status as word plus symbol, using the same badge as the record's own screens.
    @ViewBuilder
    static func badge(type: String, status: String) -> some View {
        switch type {
        case "job" where JobStatus(rawValue: status) != nil: StatusBadge(JobStatus(rawValue: status)!)
        case "estimate" where EstimateStatus(rawValue: status) != nil: StatusBadge(EstimateStatus(rawValue: status)!)
        case "invoice" where InvoiceStatus(rawValue: status) != nil: StatusBadge(InvoiceStatus(rawValue: status)!)
        default:
            StatusBadge(text: status.replacingOccurrences(of: "_", with: " ").capitalized, symbol: "circle.dashed")
        }
    }

    private func search() async {
        let text = query.trimmed
        guard !text.isEmpty else {
            results = []
            error = nil
            searching = false
            return
        }
        searching = true
        // Only the search for the text still in the field may change what's shown.
        defer { if text == query.trimmed { searching = false } }
        do {
            let found = try await model.api.search(text)
            guard text == query.trimmed, !Task.isCancelled else { return }
            results = found
            error = nil
        } catch {
            // Typing cancels the previous search; that isn't a failure.
            guard text == query.trimmed, !Task.isCancelled else { return }
            self.error = model.message(for: error)
        }
    }
}
