import SwiftUI

private struct PriceBookPickerLoadScope: Equatable {
    let context: PriceBookCatalogContext
    let apiGeneration: UUID
}

/// The price book as a cart (EB-01..EB-07): the search field is focused when it opens, this
/// device's favourites and recent items come first, the category sits in a filter circle, and
/// every "+" adds one more without closing. "Done · 4 items" goes back to the builder.
struct PriceBookCartPicker: View {
    /// Where the picks go, e.g. "Option 2 · Repair and protect".
    let destination: String
    let canUsePriceBook: Bool
    var unavailableReason: String? = nil
    var searchIdentifier = "price-book-search"
    /// A limit that still applies while adding (e.g. a draft that can't be saved yet). The builder's
    /// banner sits under this sheet, so the picker repeats it rather than hide it while they add.
    var notice: String? = nil
    let quantityInDraft: (String) -> Int?
    let secondaryPriceText: (PriceBookListItem) -> String?
    /// Adds one; returns the reason when the draft refused it (shown here), nil when added.
    let addItem: (PriceBookListItem) -> String?
    /// A custom item: the picker closes and the new line opens for its price.
    let addCustomLine: ((String) -> Void)?
    let refresh: (_ force: Bool) async -> Void

    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @ObservedObject private var catalog = PriceBookCatalog.shared
    @State private var query = ""
    @State private var kind = PriceBookKindFilter.all
    @State private var added = 0
    @State private var error: String?
    @FocusState private var focus: EstimateBuilderFocus?
    #if DEBUG
    @State private var previewRevalidated = false
    #endif

    private var context: PriceBookCatalogContext {
        .init(organizationID: session.activeOrganization?.id, sessionGeneration: session.generation, authority: session.priceBookAuthority)
    }

    var body: some View {
        VStack(spacing: 0) {
            #if DEBUG
            if EstimateRecoveryPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-estimate-recovery-trace") {
                TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                    Text("Sample picker trace").accessibilityIdentifier("estimate-picker-event-trace")
                        .accessibilityValue(EstimateRecoveryPreview.shared.eventTrace)
                }
            }
            #endif
            if typeSize.isAccessibilitySize {
                searchHeader
            } else {
                header
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if typeSize.isAccessibilitySize {
                        titleHeader.padding(.horizontal, Theme.gutter)
                    }
                    if let notice { ErrorBanner(message: notice).padding(.horizontal, Theme.gutter) }
                    if let error { ErrorBanner(message: error).padding(.horizontal, Theme.gutter) }
                    if !canUsePriceBook, addCustomLine == nil {
                        ContentUnavailableView("Price Book unavailable", systemImage: "book.closed",
                                               description: Text(unavailableReason ?? "This account cannot select Price Book items."))
                    } else {
                        PriceBookResultsList(
                            catalog: catalog, context: context, query: query, kind: kind, canUsePriceBook: canUsePriceBook,
                            quantityInCurrentDraft: quantityInDraft, secondaryPriceText: secondaryPriceText,
                            addItem: add, addCustomLine: addCustomLine.map { custom in { text in custom(text); dismiss() } },
                            retry: { Task { await refresh(true) } }
                        )
                    }
                }
                .padding(.top, 4)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await refresh(true) }
        }
        .background(Theme.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PaperActionBar(title: added == 0 ? "Done" : "Done · \(added) \(added == 1 ? "item" : "items")",
                           symbol: added == 0 ? nil : "checkmark", identifier: "price-book-done") { dismiss() }
        }
        .sensoryFeedback(.success, trigger: added)
        #if DEBUG
        .onAppear { if EstimateRecoveryPreview.enabled { EstimateRecoveryPreview.shared.record("picker-sheet-appear") } }
        .onDisappear { if EstimateRecoveryPreview.enabled { EstimateRecoveryPreview.shared.record("picker-sheet-disappear") } }
        #endif
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task(id: PriceBookPickerLoadScope(context: context, apiGeneration: api.requestGeneration)) {
            await refresh(false)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            #if DEBUG
            if PaperPreview.enabled, PaperPreview.screen == "builder-picker" { await previewFillCart(); return }
            #endif
            focus = .search
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            titleHeader
            searchControls
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 18).padding(.bottom, 10)
    }

    private var titleHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add items").font(Theme.font(20, weight: .medium)).foregroundStyle(Theme.foreground)
                Text("To \(destination)").font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if !typeSize.isAccessibilitySize {
                PaperCircleButton(symbol: "xmark", label: "Close", size: 36, action: { dismiss() })
            }
        }
    }

    private var searchHeader: some View {
        searchControls
            .padding(.horizontal, Theme.gutter).padding(.top, 18).padding(.bottom, 10)
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted).accessibilityHidden(true)
                    TextField(canUsePriceBook ? "Search price book" : "Type a custom item", text: $query, prompt: .placeholder(canUsePriceBook ? "Search price book" : "Type a custom item"))
                        .font(Theme.font(17))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .focused($focus, equals: .search)
                        .accessibilityLabel(canUsePriceBook ? "Search price book" : "Custom item")
                        .accessibilityIdentifier(searchIdentifier)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.leading, 14)
                .frame(minHeight: 50)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).stroke(Theme.border))
                if typeSize.isAccessibilitySize {
                    PaperCircleButton(symbol: "xmark", label: "Close", size: 44, action: { dismiss() })
                }
                if canUsePriceBook {
                    ThorbisMenu(items: PriceBookKindFilter.allCases.map { filter in
                        ThorbisMenuItem(filter.title, isSelected: filter == kind) { kind = filter }
                    }, title: "Category", accessibilityLabel: "Category") {
                        PaperCircleLabel(symbol: "line.3.horizontal.decrease", size: 44,
                                         fill: kind == .all ? Theme.fill : Theme.brandSurface, bordered: true)
                    }
                    .accessibilityValue(kind.title)
                    .sensoryFeedback(.selection, trigger: kind)
                }
            }
            #if DEBUG
            if PaperPreview.enabled, ProcessInfo.processInfo.arguments.contains("--paper-preview-picker-revalidation") {
                Button("Refresh sample authority") {
                    Task { await session.revalidate(); previewRevalidated = true }
                }.accessibilityIdentifier("price-book-preview-revalidate")
                if previewRevalidated {
                    Text("Sample authority refreshed").accessibilityIdentifier("price-book-preview-revalidated")
                }
            }
            #endif
            if kind != .all {
                Text("Showing \(kind.title.lowercased())").font(Theme.font(13)).foregroundStyle(Theme.muted)
            }
        }
    }

    private func add(_ item: PriceBookListItem) {
        #if DEBUG
        if EstimateRecoveryPreview.enabled { EstimateRecoveryPreview.shared.record("picker-add-tapped") }
        #endif
        guard canUsePriceBook, session.can("pricebook.view", feature: "price_book"),
              session.priceBookAuthority == context.authority,
              catalog.isCurrent(context, api: api) else {
            #if DEBUG
            if EstimateRecoveryPreview.enabled { EstimateRecoveryPreview.shared.record("picker-add-denied") }
            #endif
            return
        }
        if let message = addItem(item) {
            #if DEBUG
            if EstimateRecoveryPreview.enabled { EstimateRecoveryPreview.shared.record("picker-draft-refused") }
            #endif
            error = message
            return
        }
        #if DEBUG
        if EstimateRecoveryPreview.enabled { EstimateRecoveryPreview.shared.record("picker-added") }
        #endif
        error = nil
        catalog.recordUse(item.id)
        added += 1
    }

    #if DEBUG
    /// Screenshot only: three picks so the cart shows its count.
    private func previewFillCart() async {
        for _ in 0..<20 where catalog.items.isEmpty { try? await Task.sleep(for: .milliseconds(150)) }
        let picks = Array(catalog.items.prefix(3))
        for (index, item) in picks.enumerated() {
            add(item)
            if index == 1 { add(item) }
        }
    }
    #endif
}
