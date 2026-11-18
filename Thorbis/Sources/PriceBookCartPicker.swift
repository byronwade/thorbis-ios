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
    /// Paper 33: the picker as Add materials' "Price book" segment. The other segments' names in
    /// order ("Scan", "Paste"); choosing one closes the picker and hands that name to `switchMode`,
    /// so the host can reopen `AddMaterialsSheet` in that mode. Empty: no segments.
    var materialModes: [String] = []
    var switchMode: ((String) -> Void)? = nil

    private static let priceBookMode = "Price book"

    @State private var modeTab = "Price book"
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
            if typeSize.isAccessibilitySize {
                searchHeader
            } else {
                header
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if typeSize.isAccessibilitySize {
                        titleHeader.padding(.horizontal, Theme.gutter)
                        if !materialModes.isEmpty { modeTabs }
                    }
                    if let notice { ErrorBanner(message: notice).padding(.horizontal, PaperCardMetrics.margin) }
                    if let error { ErrorBanner(message: error).padding(.horizontal, PaperCardMetrics.margin) }
                    if !canUsePriceBook, addCustomLine == nil {
                        PaperEmptyState(symbol: "book.closed", title: "Price Book unavailable",
                                        message: unavailableReason ?? "This account cannot select Price Book items.")
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
        .paperPageGround()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Paper 33: the commit with the keyboard circle beside it. Each "+" has already added its
            // item, so the commit says Done rather than Paper's "Add 1 item · $28.00".
            PaperActionBar(title: added == 0 ? "Done" : "Done · \(added) \(added == 1 ? "item" : "items")",
                           identifier: "price-book-done", action: { dismiss() }) {
                MaterialsKeyboardButton(label: focus == .search ? "Hide keyboard" : "Search the price book") {
                    focus = focus == .search ? nil : .search
                }
            }
        }
        .onChange(of: modeTab) { _, value in
            guard value != Self.priceBookMode else { return }
            // Tell the host first, so it reopens Add materials once this sheet has closed.
            switchMode?(value)
            dismiss()
        }
        .sensoryFeedback(.success, trigger: added)
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

    /// Paper 33: the close circle, "Add materials" at 34 Bold, the Add materials segments when this
    /// is one of them (else where the picks go), then the search field (a card, radius 14) with the
    /// category filter circle inside it.
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperCircleButton(symbol: "xmark", label: "Close", size: 44, fill: Theme.card, action: { dismiss() })
                .padding(.horizontal, PaperCardMetrics.margin)
            titleHeader
                .padding(.horizontal, Theme.gutter).padding(.top, 14)
            if !materialModes.isEmpty {
                modeTabs.padding(.top, 16)
            }
            searchControls
                .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 14)
        }
        .padding(.top, 14).padding(.bottom, 10)
    }

    private var titleHeader: some View {
        // The estimate builder has several places a pick can go; Add materials has one.
        PaperPageTitle(title: "Add materials", subtitle: materialModes.isEmpty ? "To \(destination)" : nil,
                       columnInset: Theme.gutter, top: 0)
    }

    /// Scan · Paste · Price book, with Price book chosen (Paper 33).
    private var modeTabs: some View {
        PaperTabs(options: materialModes + [Self.priceBookMode], selection: $modeTab)
            .accessibilityIdentifier("materials-mode")
    }

    private var searchHeader: some View {
        searchControls
            .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 18).padding(.bottom, 10)
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted).accessibilityHidden(true)
                    TextField(canUsePriceBook ? "Search price book" : "Type a custom item", text: $query, prompt: .placeholder(canUsePriceBook ? "Search or ask" : "Type a custom item"))
                        .font(Theme.font(16))
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
                    if canUsePriceBook {
                        // Paper 33: the filter circle sits inside the field's trailing edge.
                        ThorbisMenu(items: PriceBookKindFilter.allCases.map { filter in
                            ThorbisMenuItem(filter.title, isSelected: filter == kind) { kind = filter }
                        }, title: "Category", accessibilityLabel: "Category") {
                            PaperCircleLabel(symbol: "line.3.horizontal.decrease", size: 40,
                                             fill: kind == .all ? Theme.fill : Theme.brandSurface)
                        }
                        .accessibilityValue(kind.title)
                        .sensoryFeedback(.selection, trigger: kind)
                    }
                }
                .padding(.leading, 12).padding(.trailing, canUsePriceBook ? 2 : 12)
                .frame(minHeight: 48)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                if typeSize.isAccessibilitySize {
                    PaperCircleButton(symbol: "xmark", label: "Close", size: 44, fill: Theme.card, action: { dismiss() })
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
        guard canUsePriceBook, session.can("pricebook.view", feature: "price_book"),
              session.priceBookAuthority == context.authority,
              catalog.isCurrent(context, api: api) else { return }
        if let message = addItem(item) {
            error = message
            return
        }
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
