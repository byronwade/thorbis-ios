import SwiftUI

/// "Copy a past estimate": start a new estimate from one already written. Only the name and the
/// lines come across, as plain typed lines at the prices they had; approval, signature, option
/// packages, discounts and the customer stay behind.
enum EstimateCopy {
    static let note = "Check prices before sending."
    static let limit = 12

    /// An estimate worth offering: it has lines of its own, all priced in US dollars.
    static func isCopyable(_ estimate: EstimateRecord) -> Bool {
        !estimate.lines.isEmpty && estimate.lines.allSatisfy { $0.unitPrice.currency == "USD" }
    }

    private static func newestFirst(_ estimates: [EstimateRecord]) -> [EstimateRecord] {
        estimates.sorted {
            let left = JobFiltering.date($0.updatedAt) ?? .distantPast, right = JobFiltering.date($1.updatedAt) ?? .distantPast
            return left == right ? $0.id > $1.id : left > right
        }
    }

    /// This customer's recent estimates, newest first.
    static func forCustomer(_ estimates: [EstimateRecord], customerID: String, limit: Int = limit) -> [EstimateRecord] {
        guard !customerID.isEmpty else { return [] }
        return Array(newestFirst(estimates.filter { $0.customerId == customerID && isCopyable($0) }).prefix(limit))
    }

    /// The person's own recent estimates for other customers, newest first.
    static func ownOthers(_ estimates: [EstimateRecord], actorID: String?, customerID: String, limit: Int = limit) -> [EstimateRecord] {
        guard let actorID, !actorID.isEmpty else { return [] }
        return Array(newestFirst(estimates.filter {
            $0.createdByUserId == actorID && $0.customerId != customerID && isCopyable($0)
        }).prefix(limit))
    }

    /// "12.50" for 1250.
    static func priceText(_ cents: Int) -> String {
        let fraction = cents % 100
        return "\(cents / 100).\(fraction < 10 ? "0" : "")\(fraction)"
    }

    /// Whether a line comes across: a price the new-estimate form can hold. Credits and discounts
    /// (negative lines) never do.
    static func copies(_ line: FieldLine) -> Bool {
        line.unitPrice.currency == "USD" && (0...100_000_000).contains(line.unitPrice.amount) && (1...100_000).contains(line.quantity)
            && !line.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The copied lines as new typed lines: fresh identities, no link to the old estimate or to
    /// the price book, the old price as it was. Work or Materials is kept where it was stored.
    static func lines(from estimate: EstimateRecord) -> [EstimateRevisionLineDraft] {
        estimate.lines.filter(copies).map { line in
            EstimateRevisionLineDraft(description: line.description, quantity: String(line.quantity),
                                      unitPrice: priceText(line.unitPrice.amount), source: .manual,
                                      group: line.group.flatMap(EstimateLineGroup.init(rawValue:)) ?? .work,
                                      showToCustomer: line.showToCustomer ?? true)
        }
    }

    /// How many of the estimate's lines were left behind (discounts, credits, unpriceable lines).
    static func leftOut(_ estimate: EstimateRecord) -> Int {
        estimate.lines.count - estimate.lines.filter(copies).count
    }

    /// The copied name fills an empty Name; a name already typed is kept.
    static func title(current: String, copied: String) -> String {
        current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? copied : current
    }

    /// The one line shown after a copy.
    static func note(leftOut: Int) -> String {
        leftOut > 0 ? "\(note) Discounts and credits weren\u{2019}t copied." : note
    }

    /// "Danielle Marlowe · $340.00 · Nov 3": who it was for, its total and when it was last changed.
    static func detail(_ estimate: EstimateRecord, customerName: String?, timeZone: TimeZone = .current) -> String {
        let total = paperLinesTotal(estimate.lines).map { money($0, currency: "USD") }
        var day: String?
        if let date = JobFiltering.date(estimate.updatedAt) {
            let formatter = DateFormatter()
            formatter.timeZone = timeZone
            formatter.dateFormat = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year) ? "MMM d" : "MMM d, yyyy"
            day = formatter.string(from: date)
        }
        return [customerName, total, day].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }
}

/// The sheet behind "Copy a past estimate": this customer's estimates first, then the person's own.
struct EstimateCopySheet: View {
    let customerID: String
    let onChoose: (EstimateRecord) -> Void
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var customerEstimates: [EstimateRecord] = []
    @State private var ownEstimates: [EstimateRecord] = []
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ThorbisSheetHeader(title: "Copy a past estimate", subtitle: "Its name and items start your new one", onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error { ErrorBanner(message: error, action: .init(title: "Try again") { await load() }, outer: 0) }
                    if !loaded, error == nil {
                        SkeletonRows(count: 4, leading: false, inset: 0)
                    } else if loaded, customerEstimates.isEmpty, ownEstimates.isEmpty, error == nil {
                        PaperEmptyState(symbol: "doc.on.doc", title: "Nothing to copy yet",
                                        message: "Estimates you write show up here to start the next one.")
                    }
                    if !customerEstimates.isEmpty { section("For this customer", customerEstimates, showsCustomer: false) }
                    if !ownEstimates.isEmpty { section(customerEstimates.isEmpty ? "Your estimates" : "Your other estimates", ownEstimates, showsCustomer: true) }
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 8).padding(.bottom, 24)
            }
        }
        .background(Theme.canvas)
        .presentationDetents([.medium, .large])
        .task { await load() }
    }

    private func section(_ title: String, _ estimates: [EstimateRecord], showsCustomer: Bool) -> some View {
        PaperSection(title) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(estimates) { estimate in
                    if estimate.id != estimates.first?.id { WellDivider() }
                    Button { onChoose(estimate); dismiss() } label: {
                        PaperListRow(title: estimate.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Estimate" : estimate.title,
                                     subtitle: EstimateCopy.detail(estimate, customerName: showsCustomer ? store.customerName(estimate.customerId) : nil),
                                     meta: "\(estimate.lines.count) item\(estimate.lines.count == 1 ? "" : "s")", subtitleLines: 2) { EmptyView() }
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityHint("Copies its name and items into the new estimate")
                    .accessibilityIdentifier("estimate-copy-\(estimate.id)")
                }
            }
            .padding(.vertical, PaperCardMetrics.edge)
        }
    }

    /// The estimate lists the app already reads: this customer's, and the workspace list the
    /// person may see (theirs are picked out of it). No new server route.
    private func load() async {
        guard session.can("estimate.view", feature: "estimates") else { loaded = true; return }
        async let customerRead: [EstimateRecord]? = customerID.isEmpty ? [] : (try? await api.fieldEstimates(customerID: customerID))
        async let allRead: [EstimateRecord]? = try? await api.fieldEstimates()
        let (forCustomer, all) = await (customerRead, allRead)
        guard !Task.isCancelled else { return }
        customerEstimates = EstimateCopy.forCustomer(forCustomer ?? all ?? [], customerID: customerID)
        ownEstimates = EstimateCopy.ownOthers(all ?? [], actorID: session.user?.id, customerID: customerID)
        error = forCustomer == nil && all == nil ? "Couldn\u{2019}t load past estimates. Check your signal and try again." : nil
        loaded = true
    }
}
