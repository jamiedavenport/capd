import Foundation

public enum EnrichmentError: Error, Equatable, Sendable {
    case captureNotFound(Int64)
    case notClaimable(EnrichmentState)
    case illegalTransition(from: EnrichmentState, to: EnrichmentState)
}

/// The one path by which extraction results reach a capture.
public struct EnrichmentService: Sendable {
    let store: Store

    public init(store: Store) {
        self.store = store
    }

    /// Claims a pending capture for extraction and starts an attempt. Whichever process
    /// claims first wins; the loser gets `notClaimable` and should walk away.
    public func claim(_ id: Int64, at date: Date = Date()) throws -> Capture {
        try store.claimForEnrichment(id: id, at: date)
    }

    /// Records what extraction produced and moves the capture to its terminal state. The
    /// full-text index picks up the body through the store's triggers.
    public func complete(
        _ id: Int64, with result: BodyExtractionResult, at date: Date = Date()
    ) throws -> Capture {
        try store.applyExtraction(
            id: id,
            body: result.body,
            bodyStatus: result.status,
            bodySource: result.source,
            enrichmentState: enrichmentState(for: result.status),
            at: date)
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
