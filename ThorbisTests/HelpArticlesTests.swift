import XCTest
@testable import Thorbis

final class HelpArticlesTests: XCTestCase {
    private func ids(_ query: String) -> [String] { HelpSearch.results(query).map(\.id) }

    // MARK: Search

    func testSearchFindsAnArticleByItsTitleKeywordsAndSteps() {
        XCTAssertEqual(ids("invoice").first, "invoice-issue")
        XCTAssertTrue(ids("qr").contains("payment-link"))
        XCTAssertTrue(ids("wifi").contains("offline"))
        XCTAssertTrue(ids("Wrap up").contains("job-start-finish"))
        XCTAssertTrue(ids("technician").contains("team-add"))
    }

    func testEveryTypedWordMustMatch() {
        XCTAssertTrue(ids("cash signal").contains("payment-collect"))
        XCTAssertFalse(ids("cash zebra").contains("payment-collect"))
        XCTAssertTrue(ids("zebra").isEmpty)
    }

    func testSearchIgnoresCaseAccentsPunctuationAndSpaces() {
        XCTAssertEqual(ids("  INVOICE  "), ids("invoice"))
        XCTAssertEqual(ids("ínvoice"), ids("invoice"))
        XCTAssertEqual(ids("invoice?"), ids("invoice"))
        XCTAssertTrue(ids("didn\u{2019}t text").contains("text-not-received"))
        XCTAssertTrue(ids("didn't text").contains("text-not-received"))
    }

    func testEmptySearchReturnsNothing() {
        XCTAssertTrue(ids("").isEmpty)
        XCTAssertTrue(ids("   ").isEmpty)
        XCTAssertTrue(ids("?!").isEmpty)
    }

    func testTitleMatchesRankAboveKeywordAndBodyMatches() {
        let title = HelpArticle(id: "title", category: "A", title: "Refund a payment", summary: "x", steps: [HelpStep(symbol: "a", text: "x")])
        let keyword = HelpArticle(id: "keyword", category: "A", title: "Money back", summary: "x",
                                  steps: [HelpStep(symbol: "a", text: "x")], keywords: ["refund"])
        let body = HelpArticle(id: "body", category: "A", title: "Payments", summary: "x",
                               steps: [HelpStep(symbol: "a", text: "Choose Refund from the menu.")])
        let other = HelpArticle(id: "other", category: "A", title: "Schedule", summary: "x", steps: [HelpStep(symbol: "a", text: "x")])
        let all = [other, body, keyword, title]
        XCTAssertEqual(HelpSearch.results("refund", in: all).map(\.id), ["title", "keyword", "body"])
        XCTAssertEqual(HelpSearch.score(title, words: ["refund"]), 3)
        XCTAssertEqual(HelpSearch.score(keyword, words: ["refund"]), 2)
        XCTAssertEqual(HelpSearch.score(body, words: ["refund"]), 1)
        XCTAssertEqual(HelpSearch.score(other, words: ["refund"]), 0)
        // Equal scores keep the catalogue's order.
        XCTAssertEqual(HelpSearch.results("x", in: [other, body]).map(\.id), ["other", "body"])
    }

    // MARK: Catalogue

    func testCatalogueIsWellFormed() {
        let articles = HelpCatalog.articles
        XCTAssertTrue((12...18).contains(articles.count), "\(articles.count) articles")
        XCTAssertEqual(Set(articles.map(\.id)).count, articles.count, "article ids repeat")
        for article in articles {
            XCTAssertTrue(HelpCatalog.categories.contains(article.category), "\(article.id) has an unlisted topic")
            XCTAssertFalse(article.title.isEmpty)
            XCTAssertFalse(article.summary.isEmpty)
            XCTAssertTrue((2...6).contains(article.steps.count), "\(article.id) has \(article.steps.count) steps")
            for step in article.steps {
                XCTAssertFalse(step.symbol.isEmpty)
                XCTAssertTrue(step.text.hasSuffix(".") || step.text.hasSuffix("?"), "\(article.id): \(step.text)")
            }
            XCTAssertFalse(article.related.contains(article.id), "\(article.id) points at itself")
            for other in article.related {
                XCTAssertNotNil(HelpCatalog.article(other), "\(article.id) points at a missing article, \(other)")
            }
        }
        for category in HelpCatalog.categories {
            XCTAssertTrue(articles.contains { $0.category == category }, "\(category) has no article")
        }
    }

    func testCatalogueCoversTheAppsMainWork() {
        for topic in ["schedule", "job", "estimate", "invoice", "payment", "customer", "messages", "offline", "menu", "settings"] {
            XCTAssertFalse(ids(topic).isEmpty, "nothing answers \(topic)")
        }
    }

    func testCommonQuestionsAndSharedTextExist() throws {
        XCTAssertEqual(HelpCatalog.commonQuestions.compactMap(HelpCatalog.article).count, HelpCatalog.commonQuestions.count)
        let article = try XCTUnwrap(HelpCatalog.article("payment-collect"))
        XCTAssertTrue(article.shareText.hasPrefix("Collect payment on site\n\n1. "))
        XCTAssertTrue(article.shareText.contains("\n4. "))
        XCTAssertEqual(HelpCatalog.related(to: article).map(\.id), ["payment-link", "offline"])
    }

    func testHelpNeverNamesASupportContact() {
        // The app defines no support address or number, so no article may promise one.
        for article in HelpCatalog.articles {
            let words = article.shareText.lowercased()
            XCTAssertFalse(words.contains("support@"), article.id)
            XCTAssertFalse(words.contains("call us"), article.id)
            XCTAssertFalse(words.contains("contact support"), article.id)
        }
    }

    func testToursHaveStepsWithUniqueIDs() {
        XCTAssertEqual(HelpTours.all.count, 3)
        let steps = HelpTours.all.flatMap(\.steps)
        XCTAssertEqual(Set(steps.map(\.id)).count, steps.count)
        for tour in HelpTours.all {
            XCTAssertTrue((2...5).contains(tour.steps.count))
            // The tours explain in words over Help; they never point at another screen's control.
            XCTAssertTrue(tour.steps.allSatisfy { $0.target == nil })
        }
        XCTAssertEqual(HelpTours.title(HelpTours.firstJob), "Your first job, start to finish")
        XCTAssertEqual(HelpTours.title(HelpTours.gettingPaid), "Getting paid on site")
    }
}
