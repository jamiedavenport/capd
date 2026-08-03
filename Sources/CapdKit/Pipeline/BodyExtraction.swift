import Foundation

/// Readable text pulled out of a page, before classification.
public struct ExtractedBody: Sendable, Equatable {
    public var text: String
    public var title: String?
    public var hasPasswordField: Bool

    public init(text: String, title: String? = nil, hasPasswordField: Bool = false) {
        self.text = text
        self.title = title
        self.hasPasswordField = hasPasswordField
    }
}

/// What body extraction produced for a capture, ready to persist. Codable because the
/// fetch child hands one to the agent as JSON over a pipe.
public struct BodyExtractionResult: Sendable, Equatable, Codable {
    public var body: String?
    public var status: BodyStatus
    public var source: BodySource
    public var title: String?

    public init(body: String?, status: BodyStatus, source: BodySource, title: String? = nil) {
        self.body = body
        self.status = status
        self.source = source
        self.title = title
    }

    /// A thin body is stored anyway — the user did see those words, and a refetch replaces
    /// them. A failed extraction stores nothing.
    public init(classifying extracted: ExtractedBody?, source: BodySource) {
        let status = BodyClassifier.classify(extracted)
        self.init(
            body: status == .failed ? nil : extracted?.text,
            status: status,
            source: source,
            title: status == .failed ? nil : extracted?.title)
    }

    /// The enrichment state this outcome lands the capture on.
    public var enrichmentState: EnrichmentState {
        switch status {
        case .ok, .none:
            .ok
        case .thin:
            .thin
        case .failed:
            .failed
        }
    }
}

/// Runs extraction end to end for one capture: Readability first, SwiftSoup as salvage,
/// classification last. Never throws — failure is a `.failed` result the capture survives.
public struct BodyExtractionPipeline: Sendable {
    public init() {}

    /// Extracts from HTML read out of a live browser tab; nothing touches the network.
    @MainActor
    public func extract(tabHTML: String, url: URL) async -> BodyExtractionResult {
        guard FetchPolicy.withinByteLimit(snapshotUTF8Count: tabHTML.utf8.count) else {
            return BodyExtractionResult(classifying: nil, source: .tab)
        }
        let fetcher = try? ReadabilityFetcher()
        let readable = await fetcher?.extractReadable(fromHTML: tabHTML, baseURL: url)
        let extracted = readable ?? SoupExtractor.extract(html: tabHTML, url: url)
        return BodyExtractionResult(classifying: extracted, source: .tab)
    }

    /// Fetches the page itself, under `FetchPolicy`'s hardening.
    @MainActor
    public func extract(url: URL) async -> BodyExtractionResult {
        guard FetchPolicy.isFetchable(url), let fetcher = try? ReadabilityFetcher() else {
            return BodyExtractionResult(classifying: nil, source: .fetch)
        }
        switch await fetcher.fetchAndExtract(url) {
        case .extracted(let extracted):
            return BodyExtractionResult(classifying: extracted, source: .fetch)
        case .snapshot(let html):
            let salvaged = SoupExtractor.extract(html: html, url: url)
            return BodyExtractionResult(classifying: salvaged, source: .fetch)
        case .failed:
            return BodyExtractionResult(classifying: nil, source: .fetch)
        }
    }
}

/// Decides whether extracted text is a real body, a login/paywall stub, or nothing.
public enum BodyClassifier {
    /// Below this many words a page has no body worth trusting.
    public static let thinWordCount = 120

    /// Below this many words, login signals mean a wall; above it they are page furniture.
    public static let wallSuspectWordCount = 500

    static let loginSignals = [
        "sign in",
        "log in",
        "sign up",
        "create an account",
        "create a free account",
        "subscribe to continue",
        "continue reading",
        "already a subscriber",
        "enable javascript",
        "javascript is disabled",
        "verify you are human",
        "checking your browser",
        "access denied",
    ]

    public static func classify(_ extracted: ExtractedBody?) -> BodyStatus {
        guard let extracted else { return .failed }

        let wordCount = extracted.text.split(whereSeparator: \.isWhitespace).count
        if wordCount == 0 {
            return .failed
        }
        if wordCount < thinWordCount {
            return .thin
        }
        if wordCount < wallSuspectWordCount {
            if extracted.hasPasswordField {
                return .thin
            }
            let lowered = extracted.text.lowercased()
            if loginSignals.count(where: { lowered.contains($0) }) >= 2 {
                return .thin
            }
        }
        return .ok
    }
}
