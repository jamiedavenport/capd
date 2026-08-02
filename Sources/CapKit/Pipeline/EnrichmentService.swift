import Foundation

/// The one path by which enrichment results reach a capture.
public struct EnrichmentService: Sendable {
    /// Claims a capture gets before a reclaim declares it failed.
    public static let maxAttempts = 3

    /// How long a `fetching` claim may sit before another process may presume its owner
    /// dead. Generous next to the 15-second fetch timeout because OCR has no such cap.
    public static let staleClaimAge: TimeInterval = 120

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

    /// Claims the oldest pending capture; nil means the queue is empty.
    @discardableResult
    public func claimNext(now: Date = Date()) throws -> Capture? {
        try store.claimNextForEnrichment(now: now)
    }

    /// Records what extraction produced and moves the capture to its terminal state. The
    /// full-text index picks up the body through the store's triggers.
    @discardableResult
    public func complete(
        _ id: Int64, with result: BodyExtractionResult, now: Date = Date()
    ) throws -> Capture {
        try store.completeEnrichment(
            id: id,
            result: StepResult(bodyExtraction: result),
            state: result.enrichmentState,
            now: now)
    }

    /// Returns abandoned claims to the queue: `fetching` rows older than `age` go back to
    /// `pending`, or to `failed` once their attempts are spent. Pass nil to reclaim every
    /// `fetching` row, which is only safe when no other process can be mid-enrichment.
    @discardableResult
    public func reclaimStale(
        olderThan age: TimeInterval? = EnrichmentService.staleClaimAge,
        now: Date = Date()
    ) throws -> Int {
        try store.reclaimStaleEnrichments(
            before: age.map { now.addingTimeInterval(-$0) },
            maxAttempts: Self.maxAttempts,
            now: now)
    }

    public func pendingCount() throws -> Int {
        try store.pendingEnrichmentCount()
    }
}
