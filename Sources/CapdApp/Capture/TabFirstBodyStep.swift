import CapdAppUI
import CapdKit
import Foundation

/// Body extraction for a capture the app just made: read the rendered page from the
/// browser it came from, fall back to the network fetch silently, record what happened.
/// Never throws — a capture that cannot be enriched stays a capture.
struct TabFirstBodyStep: ProcessingStep {
    var tabHTML: @MainActor @Sendable (Browser) -> String? = {
        try? TabExtractor().extractHTML(from: $0)
    }
    var extractFromTab: @MainActor @Sendable (_ html: String, URL) async -> BodyExtractionResult =
        {
            await BodyExtractionPipeline().extract(tabHTML: $0, url: $1)
        }
    var fetch: @MainActor @Sendable (URL) async -> BodyExtractionResult = {
        await BodyExtractionPipeline().extract(url: $0)
    }

    func applies(to capture: Capture) -> Bool {
        capture.kind == .link && capture.url != nil
    }

    func run(_ capture: Capture, context: ProcessingContext) async throws -> StepResult {
        guard let urlString = capture.url, let url = URL(string: urlString) else {
            return StepResult(
                bodyExtraction: BodyExtractionResult(body: nil, status: .failed, source: .fetch))
        }
        return StepResult(bodyExtraction: await extract(for: capture, url: url))
    }

    @MainActor
    func extract(for capture: Capture, url: URL) async -> BodyExtractionResult {
        if let browser = capture.sourceAppBundleID.flatMap(Browser.init(bundleID:)),
            let html = tabHTML(browser)
        {
            let fromTab = await extractFromTab(html, url)
            if fromTab.status != .failed {
                return fromTab
            }
        }
        return await fetch(url)
    }
}
