import Foundation

/// The one path by which body-extraction results reach a capture.
public struct EnrichmentService: Sendable {
    let store: Store

    public init(store: Store) {
        self.store = store
    }

    /// Claims a pending capture for extraction and starts an attempt. Returns nil when the
    /// capture is absent or already claimed, so racing processes produce one winner and the
    /// losers treat it as a no-op.
    @discardableResult
    public func claim(_ id: Int64, now: Date = Date()) throws -> Capture? {
        try store.claimForEnrichment(id: id, now: now)
    }

    /// Records what extraction produced and moves the capture to its terminal state. The
    /// full-text index picks up the body through the store's triggers.
    @discardableResult
    public func complete(
        _ id: Int64, with result: BodyExtractionResult, now: Date = Date()
    ) throws -> Capture {
        try store.applyExtraction(
            id: id,
            body: result.body,
            bodyStatus: result.status,
            bodySource: result.source,
            enrichmentState: enrichmentState(for: result.status),
            now: now)
    }

    private func enrichmentState(for status: BodyStatus) -> EnrichmentState {
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
