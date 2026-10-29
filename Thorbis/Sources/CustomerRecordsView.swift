import SwiftUI

/// The customer's photos, notes, documents, estimates, invoices, and activity,
/// each list still grouped under the job it came from.
struct CustomerRecordsView: View {
    let compilation: CustomerJobCompilation
    let customerID: String

    /// The record a Records-tab activity row opens. A payment with no invoice id stays closed.
    static func activityDestination(_ entry: CustomerHistoryEntry, customerID: String) -> ActivityDestination? {
        ActivityDestinationMapping.customerHistory(entry, customerID: customerID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            mediaSection("Photos", total: compilation.photoCount, groups: compilation.photos, symbol: "photo")
            textSection("Notes", total: compilation.noteCount, groups: compilation.notes, symbol: "note.text") { $0.body }
            mediaSection("Documents", total: compilation.documentCount, groups: compilation.documents, symbol: "doc")
            linkedSection("Estimates", total: compilation.estimateCount, groups: compilation.estimates, symbol: "doc.text", extra: compilation.estimatesOffJob.map { ($0.title, PaperRoute.estimate($0.id)) }) { estimate in
                (estimate.title, PaperRoute.estimate(estimate.id))
            }
            linkedSection("Invoices", total: compilation.invoiceCount, groups: compilation.invoices, symbol: "doc.plaintext", extra: compilation.invoicesOffJob.map { (CustomerRecordLabel.invoice($0), PaperRoute.invoice($0.id)) }) { invoice in
                (CustomerRecordLabel.invoice(invoice), PaperRoute.invoice(invoice.id))
            }
            activitySection
        }
    }

    private func mediaSection(_ title: String, total: Int, groups: [CustomerJobGroup<MediaAssetRecord>], symbol: String) -> some View {
        section(title, total: total, symbol: symbol, groups: groups) { asset in
            Text(asset.caption.flatMap { $0.isEmpty ? nil : $0 } ?? asset.originalFilename)
                .font(Theme.font(15)).foregroundStyle(Theme.foreground).lineLimit(2)
        }
    }

    private func textSection(_ title: String, total: Int, groups: [CustomerJobGroup<JobNoteRecord>], symbol: String, line: @escaping (JobNoteRecord) -> String) -> some View {
        section(title, total: total, symbol: symbol, groups: groups) { note in
            Text(line(note)).font(Theme.font(15)).foregroundStyle(Theme.foreground).lineLimit(3)
        }
    }

    private func linkedSection<Item: Identifiable>(_ title: String, total: Int, groups: [CustomerJobGroup<Item>], symbol: String, extra: [(String, PaperRoute)], row: @escaping (Item) -> (String, PaperRoute)) -> some View where Item: Equatable {
        VStack(alignment: .leading, spacing: 8) {
            heading(title, count: total, symbol: symbol)
            if groups.isEmpty && extra.isEmpty {
                Text("None yet").font(Theme.font(15)).foregroundStyle(Theme.muted)
            }
            ForEach(groups, id: \.jobID) { group in
                jobHeading(group.title, jobID: group.jobID, count: group.count)
                ForEach(group.items) { item in
                    let pair = row(item)
                    NavigationLink(value: pair.1) { rowLabel(pair.0) }.buttonStyle(RowPressStyle())
                }
            }
            if !extra.isEmpty {
                Text("Not on a job").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted).padding(.top, 4)
                ForEach(Array(extra.enumerated()), id: \.offset) { _, pair in
                    NavigationLink(value: pair.1) { rowLabel(pair.0) }.buttonStyle(RowPressStyle())
                }
            }
        }
    }

    private func section<Item: Equatable>(_ title: String, total: Int, symbol: String, groups: [CustomerJobGroup<Item>], @ViewBuilder row: @escaping (Item) -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            heading(title, count: total, symbol: symbol)
            if groups.isEmpty {
                Text("None yet").font(Theme.font(15)).foregroundStyle(Theme.muted)
            }
            ForEach(groups, id: \.jobID) { group in
                jobHeading(group.title, jobID: group.jobID, count: group.count)
                ForEach(Array(group.items.enumerated()), id: \.offset) { _, item in
                    row(item).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Activity", count: compilation.activityCount + compilation.accountActivity.count, symbol: "clock")
            if compilation.activity.isEmpty && compilation.accountActivity.isEmpty {
                Text("None yet").font(Theme.font(15)).foregroundStyle(Theme.muted)
            }
            ForEach(compilation.activity, id: \.jobID) { group in
                jobHeading(group.title, jobID: group.jobID, count: group.count)
                ForEach(group.items) { entry in
                    ActivityLink(destination: ActivityDestinationMapping.customerHistory(entry, customerID: customerID)) {
                        Text(entry.summary).font(Theme.font(15)).foregroundStyle(Theme.foreground).lineLimit(3)
                    }
                }
            }
            if !compilation.accountActivity.isEmpty {
                Text("Account").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted).padding(.top, 4)
                ForEach(compilation.accountActivity) { entry in
                    ActivityLink(destination: ActivityDestinationMapping.customerHistory(entry, customerID: customerID)) {
                        Text(entry.summary).font(Theme.font(15)).foregroundStyle(Theme.foreground).lineLimit(3)
                    }
                }
            }
        }
    }

    private func heading(_ title: String, count: Int, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Theme.muted)
            Text(title).font(Theme.font(13, weight: .medium))
            Text("\(count)").font(Theme.font(12))
        }.foregroundStyle(Theme.muted).accessibilityAddTraits(.isHeader)
    }

    private func jobHeading(_ title: String, jobID: String, count: Int) -> some View {
        NavigationLink(value: PaperRoute.job(jobID)) {
            HStack(spacing: 6) {
                Text(title).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
                Text("\(count)").font(Theme.font(12)).foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
            }.frame(minHeight: 44)
        }.buttonStyle(RowPressStyle())
    }

    private func rowLabel(_ title: String) -> some View {
        HStack {
            Text(title).font(Theme.font(15)).foregroundStyle(Theme.foreground).lineLimit(2)
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
    }
}
