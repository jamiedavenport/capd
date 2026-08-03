import Foundation

/// The one path by which enrichment reaches a capture: claim it, run every applicable
/// step, write the merged outcome.
///
/// The service, not the steps, owns the state machine — there is no legal path from
/// `pending` straight to `ok`, and steps stay pure so they never need write access.
public struct EnrichmentService: Sendable {
    /// Claims a capture gets before a reclaim declares it failed.
    public static let maxAttempts = 3

    /// How long a `fetching` claim may sit before another process may presume its owner
    /// dead. Generous next to the 15-second fetch timeout because OCR has no such cap.
    public static let staleClaimAge: TimeInterval = 120

    let store: Store
    let steps: [any ProcessingStep]

    public init(store: Store, steps: [any ProcessingStep] = []) {
        self.store = store
        self.steps = steps
    }

    /// Processes one capture. Returns nil when it is absent or not pending, so racing
    /// processes produce one winner and the losers treat it as a no-op.
    @discardableResult
    public func process(captureID: Int64) async throws -> Capture? {
        guard let claimed = try store.claimForEnrichment(id: captureID) else {
            return nil
        }
        return try await enrich(claimed, id: captureID)
    }

    /// Claims and processes the oldest pending capture; nil means the queue is empty.
    @discardableResult
    public func processNext() async throws -> Capture? {
        guard let claimed = try store.claimNextForEnrichment(), let id = claimed.id else {
            return nil
        }
        return try await enrich(claimed, id: id)
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

    private func enrich(_ claimed: Capture, id: Int64) async throws -> Capture {
        let context = ProcessingContext(paths: store.paths)
        var merged = StepResult()
        do {
            for step in steps where step.applies(to: claimed) {
                merged.merge(try await step.run(claimed, context: context))
            }
        } catch {
            // The failure is recorded before rethrowing so the row never sticks in fetching.
            _ = try store.completeEnrichment(id: id, result: StepResult(), state: .failed)
            Log.pipeline.error("capture \(id) enrichment failed: \(String(describing: error))")
            throw error
        }

        let completed = try store.completeEnrichment(
            id: id, result: merged, state: merged.enrichmentState)
        Log.pipeline.info(
            "capture \(id) enriched: \(completed.enrichmentState.rawValue, privacy: .public)")
        return completed
    }
}
