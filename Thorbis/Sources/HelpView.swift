import SwiftUI

// Help (Paper 98): the title, search, "Take a tour" and "Common questions". Every other answer is
// found by searching, as Paper draws no topic lists. Paper's "Talk to us" (support chat, 98B, and
// a phone number) is not drawn: the app defines no support address or number, and there is no
// help desk to chat with.

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
                searchField.paperCardMargin().padding(.top, 16)
                VStack(alignment: .leading, spacing: 22) {
                    if !needle.isEmpty {
                        searchResults(results, needle: needle)
                    } else {
                        tours
                        questions
                    }
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
                        PaperIcon(.helpPlay, size: 22, color: Theme.brandText).accessibilityHidden(true)
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

    /// Paper 98's search: an 18 magnifier and 16pt words on a 50pt quiet well, radius 14.
    private var searchField: some View {
        HStack(spacing: 8) {
            PaperIcon(.search, size: 18, color: Theme.muted).accessibilityHidden(true)
            TextField("", text: $query, prompt: .placeholder("Search help"))
                .font(Theme.font(16)).foregroundStyle(Theme.foreground)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search)
                .frame(minHeight: 50)
                .accessibilityLabel("Search help")
                .accessibilityIdentifier("help-search")
            if !query.isEmpty {
                Button { query = "" } label: {
                    PaperIcon(.close, size: 12, color: Theme.muted)
                        .frame(width: 22, height: 22).background(Theme.quietFill, in: Circle())
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14).padding(.trailing, query.isEmpty ? 14 : 2)
        .frame(minHeight: 50)
        .background(Theme.quietFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        PaperIcon(.chevronRight, size: 16, color: Theme.muted).accessibilityHidden(true)
    }
}

extension PaperGlyph {
    /// Paper 98's tour mark: a 9 circle and an open play triangle, 1.6 strokes on a 22 box.
    static let helpPlay = PaperGlyph(box: 22, [.circle(11, 11, 9, 1.6), .stroke("M9.2 7.6L14.4 11L9.2 14.4Z", 1.6)])
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
                .padding(.horizontal, Theme.gutter).padding(.top, PaperHeaderMetrics.titleTopUnderBar)
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
