import CapKit
import Foundation

/// Tab-first enrichment for a capture the app just made: read the rendered page from the
/// browser it came from, fall back to the network fetch silently, record what happened.
/// Never throws — a capture that cannot be enriched stays a capture.
@MainActor
struct BodyEnricher {
    let enrichment: EnrichmentService
    let pipeline = BodyExtractionPipeline()
    let tabExtractor = TabExtractor()

    func enrich(_ capture: Capture) async {
        guard let id = capture.id,
            let urlString = capture.url,
            let url = URL(string: urlString)
        else {
            return
        }
        guard (try? enrichment.claim(id)) != nil else {
            return
        }

        let result = await extract(for: capture, url: url)
        _ = try? enrichment.complete(id, with: result)
    }

    private func extract(for capture: Capture, url: URL) async -> BodyExtractionResult {
        if let bundleID = capture.sourceAppBundleID,
            let tabHTML = try? tabExtractor.extractHTML(fromBrowserWithBundleID: bundleID)
        {
            let fromTab = await pipeline.extract(tabHTML: tabHTML, url: url)
            if fromTab.status != .failed {
                return fromTab
            }
        }
        return await pipeline.extract(url: url)
    }
}
