import Foundation
import Testing

@testable import CapdKit

@Suite("SoupExtractor")
struct SoupExtractorTests {
    @Test("An article keeps its body and loses the chrome")
    func articleKeepsBodyDropsChrome() throws {
        let extracted = try #require(
            SoupExtractor.extract(html: try fixture("article"), url: articleURL))

        #expect(extracted.text.contains("migratory patterns of the alpine chough"))
        #expect(extracted.title == "Migratory Patterns of the Alpine Chough")
        #expect(!extracted.hasPasswordField)
        for chrome in [
            "SITE-MASTHEAD", "SITE-NAV-LINK", "FOOTER-COPYRIGHT", "TRACKING-SNIPPET",
            "RELATED-STORIES-WIDGET",
        ] {
            #expect(!extracted.text.contains(chrome))
        }
        #expect(BodyClassifier.classify(extracted) == .ok)
    }

    @Test("A login page is detected before its form is pruned")
    func loginPageDetectsPasswordField() throws {
        let extracted = try #require(
            SoupExtractor.extract(html: try fixture("login"), url: articleURL))

        #expect(extracted.hasPasswordField)
        #expect(BodyClassifier.classify(extracted) == .thin)
    }

    @Test("A paywall reads as thin without any password field")
    func paywallClassifiesThin() throws {
        let extracted = try #require(
            SoupExtractor.extract(html: try fixture("paywall"), url: articleURL))

        #expect(!extracted.hasPasswordField)
        #expect(BodyClassifier.classify(extracted) == .thin)
    }

    @Test("A long article with a login widget is still an article")
    func loginWidgetDoesNotSinkALongArticle() throws {
        let extracted = try #require(
            SoupExtractor.extract(
                html: try fixture("article-with-login-widget"), url: articleURL))

        #expect(extracted.hasPasswordField)
        #expect(BodyClassifier.classify(extracted) == .ok)
    }

    @Test("A short benign page is thin, an empty one is nothing")
    func shortAndEmptyPages() throws {
        let short = try #require(
            SoupExtractor.extract(html: try fixture("short"), url: articleURL))
        #expect(BodyClassifier.classify(short) == .thin)

        #expect(SoupExtractor.extract(html: try fixture("empty"), url: articleURL) == nil)
        #expect(SoupExtractor.extract(html: "", url: articleURL) == nil)
    }

    @Test("Whitespace collapses to single spaces")
    func whitespaceCollapses() throws {
        let html = "<html><body><main><p>alpha\n\n   beta\t gamma</p></main></body></html>"
        let extracted = try #require(SoupExtractor.extract(html: html, url: nil))
        #expect(extracted.text == "alpha beta gamma")
    }
}

private let articleURL = URL(string: "https://example.com/article")

private func fixture(_ name: String) throws -> String {
    let url = try #require(
        Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
}
