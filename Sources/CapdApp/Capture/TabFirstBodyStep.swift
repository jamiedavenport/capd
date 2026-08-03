import CapdKit
import Foundation

/// Body extraction for a capture the app just made: read the rendered page from the
/// browser it came from, fall back to the network fetch silently, record what happened.
/// Never throws — a capture that cannot be enriched stays a capture.
struct TabFirstBodyStep: ProcessingStep {
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
    private func extract(for capture: Capture, url: URL) async -> BodyExtractionResult {
        let pipeline = BodyExtractionPipeline()
        if let bundleID = capture.sourceAppBundleID,
            let tabHTML = try? TabExtractor().extractHTML(fromBrowserWithBundleID: bundleID)
        {
            let fromTab = await pipeline.extract(tabHTML: tabHTML, url: url)
            if fromTab.status != .failed {
                return fromTab
            }
        }
        return await pipeline.extract(url: url)
    }
}
