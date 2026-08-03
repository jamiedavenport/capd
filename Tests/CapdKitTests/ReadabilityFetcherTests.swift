import Foundation
import Testing

@testable import CapdKit

/// Real WebKit, which is flake-prone headless, so CI skips these. Run locally with
/// `CAPD_WEBKIT_TESTS=1 swift test --filter ReadabilityFetcher`.
@Suite(
    "ReadabilityFetcher",
    .enabled(if: ProcessInfo.processInfo.environment["CAPD_WEBKIT_TESTS"] == "1"))
struct ReadabilityFetcherTests {
    @Test("Readability pulls the article body out of tab HTML")
    @MainActor
    func tabHTMLExtractsTheArticle() async throws {
        let fetcher = try ReadabilityFetcher()
        let extracted = try #require(
            await fetcher.extractReadable(fromHTML: fixture("article"), baseURL: articleURL))

        #expect(extracted.text.contains("migratory patterns of the alpine chough"))
        #expect(!extracted.text.contains("SITE-NAV-LINK"))
        #expect(BodyClassifier.classify(extracted) == .ok)
    }

    @Test("A login page keeps its password field through the DOMParser path")
    @MainActor
    func loginPageReportsThePasswordField() async throws {
        let fetcher = try ReadabilityFetcher()
        let extracted = await fetcher.extractReadable(
            fromHTML: try fixture("login"), baseURL: articleURL)

        if let extracted {
            #expect(extracted.hasPasswordField)
            #expect(BodyClassifier.classify(extracted) == .thin)
        }
    }
}

/// The one test allowed to touch the network, hence its own gate: run locally with
/// `CAPD_NETWORK_TESTS=1 swift test --filter ReadabilityFetcher`.
@Suite(
    "ReadabilityFetcher live fetch",
    .enabled(if: ProcessInfo.processInfo.environment["CAPD_NETWORK_TESTS"] == "1"))
struct ReadabilityFetcherLiveFetchTests {
    @Test("A tiny real page comes back thin through the salvage tier")
    @MainActor
    func exampleDomainFetchesAsThin() async throws {
        let url = try #require(URL(string: "https://example.com/"))
        let result = await BodyExtractionPipeline().extract(url: url)

        #expect(result.status == .thin)
        #expect(result.source == .fetch)
        #expect(try #require(result.body).contains("documentation examples"))
    }
}

private let articleURL = URL(string: "https://example.com/article")!

private func fixture(_ name: String) throws -> String {
    let url = try #require(
        Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
}
