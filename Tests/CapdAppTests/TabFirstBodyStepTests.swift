import Foundation
import Testing

@testable import CapdApp
@testable import CapdAppUI
@testable import CapdKit

@MainActor
@Suite("TabFirstBodyStep")
struct TabFirstBodyStepTests {
    @MainActor
    final class Harness {
        var tabHTML: String?
        var tabResult = BodyExtractionResult(body: "from tab", status: .ok, source: .tab)
        let fetchResult = BodyExtractionResult(body: "from fetch", status: .ok, source: .fetch)
        var askedBrowsers: [Browser] = []
        var extractedHTML: [String] = []
        var fetched: [URL] = []

        let url = URL(string: "https://example.com/article")!

        var step: TabFirstBodyStep {
            TabFirstBodyStep(
                tabHTML: { [self] browser in
                    askedBrowsers.append(browser)
                    return tabHTML
                },
                extractFromTab: { [self] html, _ in
                    extractedHTML.append(html)
                    return tabResult
                },
                fetch: { [self] url in
                    fetched.append(url)
                    return fetchResult
                })
        }

        func extract(sourceAppBundleID: String?) async -> BodyExtractionResult {
            let capture = Capture(
                kind: .link, url: url.absoluteString, sourceAppBundleID: sourceAppBundleID,
                createdAt: Date(timeIntervalSinceReferenceDate: 0))
            return await step.extract(for: capture, url: url)
        }
    }

    @Test("A readable tab is used without touching the network")
    func tabBodyWins() async {
        let harness = Harness()
        harness.tabHTML = "<html>page</html>"

        let result = await harness.extract(sourceAppBundleID: Browser.dia.rawValue)

        #expect(result == harness.tabResult)
        #expect(harness.askedBrowsers == [.dia])
        #expect(harness.extractedHTML == ["<html>page</html>"])
        #expect(harness.fetched.isEmpty)
    }

    @Test("A thin tab body is kept")
    func thinTabBodyIsKept() async {
        let harness = Harness()
        harness.tabHTML = "<html>page</html>"
        harness.tabResult = BodyExtractionResult(body: "short", status: .thin, source: .tab)

        let result = await harness.extract(sourceAppBundleID: Browser.safari.rawValue)

        #expect(result == harness.tabResult)
        #expect(harness.fetched.isEmpty)
    }

    @Test("A tab that cannot be read falls back to fetching")
    func unreadableTabFallsBack() async {
        let harness = Harness()

        let result = await harness.extract(sourceAppBundleID: Browser.chrome.rawValue)

        #expect(result == harness.fetchResult)
        #expect(harness.askedBrowsers == [.chrome])
        #expect(harness.extractedHTML.isEmpty)
        #expect(harness.fetched == [harness.url])
    }

    @Test("Tab HTML that fails extraction falls back to fetching")
    func failedTabExtractionFallsBack() async {
        let harness = Harness()
        harness.tabHTML = "<html></html>"
        harness.tabResult = BodyExtractionResult(body: nil, status: .failed, source: .tab)

        let result = await harness.extract(sourceAppBundleID: Browser.arc.rawValue)

        #expect(result == harness.fetchResult)
        #expect(harness.fetched == [harness.url])
    }

    @Test(
        "A capture from outside a browser goes straight to fetching",
        arguments: [nil, "com.apple.dt.Xcode"] as [String?])
    func nonBrowserSourceFetches(bundleID: String?) async {
        let harness = Harness()
        harness.tabHTML = "<html>page</html>"

        let result = await harness.extract(sourceAppBundleID: bundleID)

        #expect(result == harness.fetchResult)
        #expect(harness.askedBrowsers.isEmpty)
    }

    @Test("Only link captures with a URL are processed")
    func appliesToLinks() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let step = TabFirstBodyStep()
        #expect(step.applies(to: Capture(kind: .link, url: "https://example.com", createdAt: now)))
        #expect(!step.applies(to: Capture(kind: .link, createdAt: now)))
        #expect(!step.applies(to: Capture(kind: .text, createdAt: now)))
    }
}
