import SwiftUI

// Help (Paper 98): the title, search, "Take a tour", "Common questions", then every article by
// topic. Paper's "Talk to us" (support chat, 98B, and a phone number) is not drawn: the app
// defines no support address or number, and there is no help desk to chat with.

struct HelpView: View {
    @State private var query = ""
    @State private var opened: HelpArticle?
    @State private var tour: GuidedTour?

    init() {}

    var body: some View {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let results = HelpSearch.results(needle)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaperHeader(title: "Help", subtitle: "Answers and tours for this app")
                LearnSearchField(query: $query, prompt: "Search help", label: "Search help", identifier: "help-search")
                    .paperCardMargin().padding(.top, 16)
                VStack(alignment: .leading, spacing: 22) {
                    if !needle.isEmpty {
                        searchResults(results, needle: needle)
                    } else {
                        tours
                        questions
                        ForEach(HelpCatalog.categories, id: \.self) { category in
                            topic(category)
                        }
                    }
                    LearnFootnote(text: "These answers are part of the app, so they open with no signal.")
                }
                .paperCardMargin().padding(.top, 22).padding(.bottom, 32)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("help-root")
        .thorbisDestination(item: $opened) { HelpArticleView(article: $0) }
        .guidedTour(tour) { tour = nil }
    }

    @ViewBuilder private func searchResults(_ results: [HelpArticle], needle: String) -> some View {
        if results.isEmpty {
            PaperEmptyState(symbol: "magnifyingglass", title: "No answers found",
                            message: "Nothing in Help matches \u{201C}\(needle)\u{201D}. Try one word, like invoice, payment or offline.",
                            actionTitle: "Clear search") { query = "" }
        } else {
            PaperSection("Answers", count: results.count) {
                ForEach(results) { article in
                    if article.id != results.first?.id { WellDivider() }
                    articleRow(article, showsCategory: true)
                }
            }
            .accessibilityIdentifier("help-results")
        }
    }

    /// Paper 98 "Take a tour": a play mark in the brand ink, the tour's name, a chevron; 56 tall.
    private var tours: some View {
        PaperSection("Take a tour") {
            ForEach(HelpTours.all, id: \.name) { item in
                if item.name != HelpTours.all.first?.name { WellDivider(leading: 50) }
                Button { tour = item } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "play.circle").font(.system(size: 21, weight: .regular))
                            .foregroundStyle(Theme.brandText).frame(width: 22).accessibilityHidden(true)
                        Text(HelpTours.title(item)).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        chevron
                    }
                    .padding(.leading, 16).padding(.trailing, 14).padding(.vertical, 9)
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .accessibilityHint("Starts the tour, \(item.steps.count) steps")
                .accessibilityIdentifier("help-tour-\(item.steps.first?.id ?? "")")
            }
        }
    }

    /// Paper 98 "Common questions": the question in 16 Medium and a chevron; 56 tall.
    private var questions: some View {
        let articles = HelpCatalog.commonQuestions.compactMap(HelpCatalog.article)
        return PaperSection("Common questions") {
            ForEach(articles) { article in
                if article.id != articles.first?.id { WellDivider() }
                Button { opened = article } label: {
                    HStack(spacing: 12) {
                        Text(article.title).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        chevron
                    }
                    .padding(.leading, 16).padding(.trailing, 14).padding(.vertical, 9)
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .accessibilityIdentifier("help-question-\(article.id)")
            }
        }
    }

    @ViewBuilder private func topic(_ category: String) -> some View {
        let articles = HelpCatalog.articles.filter { $0.category == category }
        if !articles.isEmpty {
            PaperSection(category) {
                ForEach(articles) { article in
                    if article.id != articles.first?.id { WellDivider() }
                    articleRow(article, showsCategory: false)
                }
            }
        }
    }

    private func articleRow(_ article: HelpArticle, showsCategory: Bool) -> some View {
        Button { opened = article } label: {
            PaperListRow(title: article.title, subtitle: article.summary, meta: showsCategory ? article.category : nil,
                         subtitleLines: 3) { chevron }
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the answer")
        .accessibilityIdentifier("help-article-\(article.id)")
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.muted).accessibilityHidden(true)
    }
}

/// Paper 98A: the topic in the brand ink, the title in 28 Bold, one muted line, the steps on one
/// card (a 64 tile, "Step 1" over the words), a quiet note, then related answers. "Was this
/// helpful?" is not drawn: there is nowhere for the answer to go.
struct HelpArticleView: View {
    let article: HelpArticle
    @State private var opened: HelpArticle?

    var body: some View {
        let related = HelpCatalog.related(to: article)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(article.category).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.brandText)
                    Text(article.title).font(Theme.heading()).tracking(-0.56)
                        .foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("help-article-title")
                    Text(article.summary).font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 14)
                VStack(alignment: .leading, spacing: 0) {
                    PaperCard {
                        ForEach(Array(article.steps.enumerated()), id: \.offset) { index, step in
                            if index > 0 { WellDivider() }
                            stepRow(step, number: index + 1, last: index == article.steps.count - 1 && article.steps.count > 1)
                        }
                    }
                    if let note = article.note {
                        Text(note).font(Theme.font(13)).foregroundStyle(Theme.subtle)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4).padding(.top, 10)
                    }
                    if !related.isEmpty {
                        PaperSection("Related articles") {
                            ForEach(related) { other in
                                if other.id != related.first?.id { WellDivider() }
                                Button { opened = other } label: {
                                    HStack(spacing: 10) {
                                        Text(other.title).font(Theme.font(16)).foregroundStyle(Theme.foreground)
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(Theme.muted).accessibilityHidden(true)
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 8)
                                    .frame(minHeight: 52)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(RowPressStyle())
                                .accessibilityIdentifier("help-related-\(other.id)")
                            }
                        }
                        .padding(.top, 20)
                    }
                }
                .paperCardMargin().padding(.top, 18).padding(.bottom, 32)
            }
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ThorbisToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: article.shareText) {
                    PaperCircleLabel(symbol: "square.and.arrow.up", size: 44, fill: Theme.card)
                }
                .accessibilityLabel("Share this answer")
                .accessibilityIdentifier("help-article-share")
            }
        }
        .thorbisDestination(item: $opened) { HelpArticleView(article: $0) }
    }

    /// One step: a 64 tile (radius 16) with the step's mark, "Step 1" in 13 Semibold, the words in 15.
    private func stepRow(_ step: HelpStep, number: Int, last: Bool) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: step.symbol).font(.system(size: 26, weight: .regular))
                .foregroundStyle(last ? Theme.success : Theme.brandText)
                .frame(width: 64, height: 64)
                .background(last ? Theme.successSurface : Theme.brandSurface,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Step \(number)").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                Text(step.text).font(Theme.font(15)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}
