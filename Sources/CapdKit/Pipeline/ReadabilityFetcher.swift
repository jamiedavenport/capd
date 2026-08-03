import Foundation
import WebKit

/// Runs Readability.js in an offscreen web view: on tab HTML handed to it, and on pages it
/// fetches itself under `FetchPolicy`.
@MainActor
public final class ReadabilityFetcher {
    public enum FetchOutcome {
        case extracted(ExtractedBody)
        /// Readability produced nothing usable; the caller salvages this HTML instead.
        case snapshot(html: String)
        case failed
    }

    private let readabilitySource: String

    public init() throws {
        guard
            let url = Bundle.module.url(forResource: "Readability", withExtension: "js")
        else {
            throw CocoaError(.fileNoSuchFile)
        }
        readabilitySource = try String(contentsOf: url, encoding: .utf8)
    }

    /// Extracts from HTML that already rendered elsewhere. The web view stays on a blank
    /// page and parses the string with `DOMParser`, so nothing here touches the network.
    public func extractReadable(fromHTML html: String, baseURL: URL) async -> ExtractedBody? {
        let webView = Self.makeWebView()
        let navigator = Navigator(target: nil)
        webView.navigationDelegate = navigator
        webView.loadHTMLString("<!DOCTYPE html><html><body></body></html>", baseURL: nil)
        guard await navigator.awaitOutcome(for: Self.blankPageDeadline) == .finished else {
            return nil
        }
        return await runReadability(in: webView, runner: Self.tabRunner, arguments: ["html": html])
    }

    public func fetchAndExtract(_ url: URL) async -> FetchOutcome {
        guard FetchPolicy.isFetchable(url) else {
            return .failed
        }

        let webView = Self.makeWebView()
        let navigator = Navigator(target: url)
        webView.navigationDelegate = navigator

        var request = URLRequest(url: url)
        request.timeoutInterval = TimeInterval(FetchPolicy.timeout.components.seconds)
        webView.load(request)

        switch await navigator.awaitOutcome(for: FetchPolicy.timeout) {
        case .finished:
            guard let html = await outerHTML(of: webView),
                FetchPolicy.withinByteLimit(snapshotUTF8Count: html.utf8.count)
            else {
                return .failed
            }
            if let extracted = await runReadability(in: webView, runner: Self.pageRunner) {
                return .extracted(extracted)
            }
            return .snapshot(html: html)

        case .timedOut:
            webView.stopLoading()
            guard let html = await outerHTML(of: webView),
                FetchPolicy.withinByteLimit(snapshotUTF8Count: html.utf8.count)
            else {
                return .failed
            }
            return .snapshot(html: html)

        case .blocked, .tooLarge, .failed:
            return .failed
        }
    }

    private static let blankPageDeadline: Duration = .seconds(5)

    private static func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.suppressesIncrementalRendering = true
        // No WKUIDelegate is set, so window.open goes nowhere.
        return WKWebView(frame: .zero, configuration: configuration)
    }

    private func outerHTML(of webView: WKWebView) async -> String? {
        let result = try? await webView.callAsyncJavaScript(
            "return document.documentElement.outerHTML;", contentWorld: .defaultClient)
        return result as? String
    }

    private struct RunnerPayload: Decodable {
        let text: String
        let title: String?
        let hasPasswordField: Bool
    }

    private func runReadability(
        in webView: WKWebView, runner: String, arguments: [String: Any] = [:]
    ) async -> ExtractedBody? {
        let body = readabilitySource + "\n" + runner
        guard
            let result = try? await webView.callAsyncJavaScript(
                body, arguments: arguments, contentWorld: .defaultClient),
            let json = result as? String, !json.isEmpty,
            let payload = try? JSONDecoder().decode(RunnerPayload.self, from: Data(json.utf8))
        else {
            return nil
        }

        let text = payload.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !text.isEmpty else {
            return nil
        }
        return ExtractedBody(
            text: text, title: payload.title, hasPasswordField: payload.hasPasswordField)
    }

    /// The runner returns a JSON string, or "" for nothing, because a JavaScript null does
    /// not round-trip cleanly through `callAsyncJavaScript`.
    private static func runner(preparing documentExpression: String) -> String {
        """
        const doc = \(documentExpression);
        const hasPasswordField = doc.querySelector("input[type=password]") !== null;
        let article = null;
        try {
            article = new Readability(doc).parse();
        } catch (error) {
            article = null;
        }
        if (!article || !article.textContent || !article.textContent.trim()) {
            return "";
        }
        return JSON.stringify({
            text: article.textContent,
            title: article.title || null,
            hasPasswordField: hasPasswordField,
        });
        """
    }

    private static let tabRunner = runner(
        preparing: #"new DOMParser().parseFromString(html, "text/html")"#)

    /// Readability mutates the document it parses, so the live page is cloned first.
    private static let pageRunner = runner(preparing: "document.cloneNode(true)")
}

@MainActor
private final class Navigator: NSObject, WKNavigationDelegate {
    enum Outcome {
        case finished
        case blocked
        case tooLarge
        case failed
        case timedOut
    }

    /// nil allows every navigation, for the blank page hosting the `DOMParser` path.
    private let target: URL?
    private var blockedByPolicy = false
    private var tooLargeByPolicy = false
    private var continuation: CheckedContinuation<Outcome, Never>?

    init(target: URL?) {
        self.target = target
    }

    func awaitOutcome(for deadline: Duration) async -> Outcome {
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: deadline)
            self?.settle(.timedOut)
        }
        defer { timeout.cancel() }
        return await withCheckedContinuation { continuation = $0 }
    }

    private func settle(_ outcome: Outcome) {
        continuation?.resume(returning: outcome)
        continuation = nil
    }

    private func failureOutcome() -> Outcome {
        if tooLargeByPolicy {
            return .tooLarge
        }
        if blockedByPolicy {
            return .blocked
        }
        return .failed
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let target else {
            return .allow
        }
        guard navigationAction.targetFrame?.isMainFrame == true else {
            return .cancel
        }
        guard let candidate = navigationAction.request.url,
            FetchPolicy.allowsNavigation(from: target, to: candidate)
        else {
            blockedByPolicy = true
            return .cancel
        }
        return .allow
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        guard target != nil, navigationResponse.isForMainFrame else {
            return .allow
        }
        let response = navigationResponse.response
        guard FetchPolicy.withinByteLimit(reportedLength: response.expectedContentLength) else {
            tooLargeByPolicy = true
            return .cancel
        }
        if let mimeType = response.mimeType, !mimeType.localizedCaseInsensitiveContains("html") {
            blockedByPolicy = true
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        settle(.finished)
    }

    func webView(
        _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error
    ) {
        settle(failureOutcome())
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        settle(failureOutcome())
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        settle(.failed)
    }
}
